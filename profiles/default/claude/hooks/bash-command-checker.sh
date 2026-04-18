#!/bin/bash
# PreToolUse hook: validates Bash commands against the allow list in settings.json.
# Multi-line commands are allowed only if every meaningful statement's first token is allowed.
# Derives the allow list from Bash() permissions — single source of truth.
# Input: JSON via stdin with tool_input.command

SETTINGS="${CLAUDE_SETTINGS_FILE:-$HOME/.claude/settings.json}"
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""')
CWD=$(echo "$INPUT" | jq -r '.cwd // ""')

[ -z "$COMMAND" ] && echo '{}' && exit 0

# Returns 0 if the given first-token resolves to a file that was Write'd or
# Edit'd earlier in this session's transcript. Canonicalizes both sides via
# os.path.realpath to handle symlinks. Fail-safe: returns 1 on any
# missing/unreadable transcript or jq/python error. Never approves on error.
session_authored() {
    local token="$1"
    [ -z "$TRANSCRIPT_PATH" ] && return 1
    [ -r "$TRANSCRIPT_PATH" ] || return 1
    local authored
    authored=$(jq -rc 'select(.message.content[]? | .type=="tool_use" and (.name=="Write" or .name=="Edit")) | .message.content[] | select(.type=="tool_use" and (.name=="Write" or .name=="Edit")) | .input.file_path' "$TRANSCRIPT_PATH" 2>/dev/null) || return 1
    [ -z "$authored" ] && return 1
    CWD="$CWD" TOKEN="$token" AUTHORED="$authored" python3 -c '
import os, sys
cwd = os.environ.get("CWD") or os.getcwd()
tok = os.environ.get("TOKEN", "")
if not tok:
    sys.exit(1)
probe = tok if os.path.isabs(tok) else os.path.join(cwd, tok)
probe = os.path.realpath(probe)
for line in os.environ.get("AUTHORED", "").splitlines():
    if not line:
        continue
    if os.path.realpath(line) == probe:
        sys.exit(0)
sys.exit(1)
' 2>/dev/null
}

# Extract allowed prefixes from Bash() permissions in settings.json
# Bash(git:*) -> git, Bash(defaults read:*) -> defaults, Bash([:*) -> [
ALLOW_LIST=$(jq -r '.permissions.allow[]? // empty' "$SETTINGS" 2>/dev/null \
    | sed -n 's/^Bash(\([^: ]*\).*/\1/p' \
    | sort -u)

# Add shell builtins/syntax that are always safe as line starters
BUILTINS="if
then
else
elif
fi
for
while
until
do
done
case
esac
#
{
}
sleep
wait
kill
pkill
pgrep
read
trap
return
exit
break
continue
shift
set
unset
local
declare
typeset"

ALLOW_LIST=$(printf '%s\n%s' "$ALLOW_LIST" "$BUILTINS")

# Preprocess: join backslash-continuation lines, strip quoted strings,
# and split semicolons so each "statement" can be checked independently.
preprocess() {
    python3 -c "
import sys

text = sys.stdin.read()

# Phase 1: Join backslash-continuation lines
lines = text.split('\n')
joined = []
buf = ''
for line in lines:
    stripped = line.rstrip()
    if stripped.endswith('\\\\'):
        # Accumulate continuation: drop trailing backslash, join with space
        buf += stripped[:-1] + ' '
    else:
        buf += line
        joined.append(buf)
        buf = ''
if buf:
    joined.append(buf)

text = '\n'.join(joined)

# Phase 2: Remove content inside quoted strings to avoid inner lines
# being parsed as commands. Replace with placeholder tokens.
result = []
i = 0
n = len(text)
while i < n:
    c = text[i]
    if c == \"'\":
        # Single-quoted string: find closing quote (no escapes inside)
        j = text.find(\"'\", i + 1)
        if j == -1:
            j = n - 1
        result.append(\"'Q'\")
        i = j + 1
    elif c == '\"':
        # Double-quoted string: find closing quote, skip backslash-escaped chars
        j = i + 1
        while j < n:
            if text[j] == '\\\\':
                j += 2
                continue
            if text[j] == '\"':
                break
            j += 1
        if j >= n:
            j = n - 1
        result.append('\"Q\"')
        i = j + 1
    else:
        result.append(c)
        i += 1

sys.stdout.write(''.join(result))
" <<< "$1"
}

PROCESSED=$(preprocess "$COMMAND")

# Fail-safe: if preprocessing produced nothing for a non-empty command, defer
# to default permission flow rather than auto-allowing.
[ -z "$PROCESSED" ] && echo '{}' && exit 0

all_allowed=true
used_session_authored=false
in_heredoc=""
while IFS= read -r line; do
    # Track heredoc state -- skip body lines
    if [ -n "$in_heredoc" ]; then
        stripped="${line#"${line%%[![:space:]]*}"}"
        [ "$stripped" = "$in_heredoc" ] && in_heredoc=""
        continue
    fi

    # Detect heredoc start (<<EOF, <<'EOF', <<"EOF", <<-EOF)
    if echo "$line" | grep -qE '<<-?\s*'"'"'?"?[A-Za-z_]' 2>/dev/null; then
        in_heredoc=$(echo "$line" | sed -n "s/.*<<-*[[:space:]]*['\"]\\{0,1\\}\([A-Za-z_][A-Za-z_0-9]*\)['\"]\\{0,1\\}.*/\1/p")
    fi

    # Skip blank lines
    stripped="${line#"${line%%[![:space:]]*}"}"
    [ -z "$stripped" ] && continue

    # Split on semicolons and check each statement
    IFS=';' read -ra stmts <<< "$stripped"
    for stmt in "${stmts[@]}"; do
        # Trim leading whitespace
        stmt="${stmt#"${stmt%%[![:space:]]*}"}"
        [ -z "$stmt" ] && continue

        # Extract first token
        first=$(echo "$stmt" | awk '{print $1}')

        # Skip variable assignments (FOO=bar, FOO="bar", etc.)
        case "$first" in
            *=*) continue ;;
        esac

        # Skip shell operators that start continuation lines or backgrounded cmds
        case "$first" in
            '||'|'&&'|'|'|'|&'|')'|';;') continue ;;
        esac

        # Allow variable expansion as command ($VAR, ${VAR})
        case "$first" in
            '$'*) continue ;;
        esac

        # Allow explicit paths; also allow bare relatives (foo/bar) if session-authored.
        case "$first" in
            /*|./*|../*) continue ;;
            */*) if session_authored "$first"; then used_session_authored=true; continue; fi ;;
        esac

        # Strip path prefix in case a relative path slipped through
        base="${first##*/}"

        if ! echo "$ALLOW_LIST" | grep -qFx "$base" 2>/dev/null; then
            all_allowed=false
            break 2
        fi
    done
done <<< "$PROCESSED"

if [ "$all_allowed" = true ]; then
    if [ "$used_session_authored" = true ]; then
        echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"All command prefixes are in allow list (includes session-authored provenance)"}}'
    else
        echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"All command prefixes are in allow list"}}'
    fi
else
    echo '{}'
fi
