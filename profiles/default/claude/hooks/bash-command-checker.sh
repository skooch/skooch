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

# Additional project roots drawn from permissions.additionalDirectories
# in settings.json. These are directories the user has already granted
# session-wide trust for Read/Write — extending that trust to
# bash/sh/zsh/dash script execution under any of them matches the
# existing security model (the agent can already drop files there).
ADDL_DIRS=$(jq -r '.permissions.additionalDirectories[]? // empty' "$SETTINGS" 2>/dev/null)

# Returns 0 if $1 is a bare path (not a flag) that resolves to an existing
# regular file inside:
#   (a) the nearest .git-bearing ancestor of CWD (the project root), or
#   (b) any entry in permissions.additionalDirectories
# Used to auto-allow interpreter invocations like "bash tests/run.sh" or
# "sh ~/projects/other-repo/scripts/foo" without requiring `bash` in the
# allow list, while still prompting for scripts outside these trusted trees.
project_local_script() {
    local candidate="$1"
    [ -z "$candidate" ] && return 1
    [ -z "$CWD" ] && return 1
    case "$candidate" in -*) return 1 ;; esac
    CWD="$CWD" CAND="$candidate" ADDL="$ADDL_DIRS" python3 -c '
import os, sys
cwd = os.environ.get("CWD") or os.getcwd()
cand = os.environ.get("CAND", "")
if not cand:
    sys.exit(1)
# Walk up from CWD looking for .git; fall back to CWD if none found.
root = os.path.abspath(cwd)
while True:
    if os.path.exists(os.path.join(root, ".git")):
        break
    parent = os.path.dirname(root)
    if parent == root:
        root = os.path.abspath(cwd)
        break
    root = parent
root = os.path.realpath(root)

# Expand additionalDirectories entries (with ~ expansion and realpath).
addl_roots = []
for line in os.environ.get("ADDL", "").splitlines():
    d = line.strip()
    if not d:
        continue
    d = os.path.expanduser(d)
    try:
        d = os.path.realpath(d)
    except Exception:
        continue
    if os.path.isdir(d):
        addl_roots.append(d)

path = cand if os.path.isabs(cand) else os.path.join(cwd, cand)
try:
    path = os.path.realpath(path)
except Exception:
    sys.exit(1)
if not os.path.isfile(path):
    sys.exit(1)
for r in [root] + addl_roots:
    if path == r or path.startswith(r + os.sep):
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

# Match a command basename against the allow list.
# Patterns containing '*' are matched as bash globs (so "xtensa-esp32s3-elf*"
# from Bash(xtensa-esp32s3-elf*:*) matches "xtensa-esp32s3-elf-nm"). Non-glob
# patterns match literally, avoiding surprises from shell metachars like '['
# appearing in command names.
allow_match() {
    local base="$1"
    local pattern
    while IFS= read -r pattern; do
        [ -z "$pattern" ] && continue
        if [[ "$pattern" == *\** ]]; then
            # shellcheck disable=SC2254  # glob expansion intentional
            [[ "$base" == $pattern ]] && return 0
        else
            [ "$base" = "$pattern" ] && return 0
        fi
    done <<< "$ALLOW_LIST"
    return 1
}

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

# Strip subshell / command-substitution parens. preprocess() has already
# replaced quoted content with "Q" / 'Q' placeholders, so remaining '(' and
# ')' sit outside strings. Replacing them with spaces exposes the inner
# statements to the per-token allow-list check — otherwise a leading '(' glues
# to the first command (e.g. "(echo foo") producing a bogus first token that
# nothing matches. Also works around Claude Code's built-in parser emitting
# "Unhandled node type: ;" on (a; b) groups, though only for the hook's own
# decision; the built-in prompt still fires until upstream is fixed.
PROCESSED="${PROCESSED//(/ }"
PROCESSED="${PROCESSED//)/ }"

# Normalise pipeline / conditional operators into statement separators so
# every sub-command is checked independently. Order matters: replace the
# double-char operators first, otherwise "||" would become ";;" via a
# premature "|" pass. preprocess() has already replaced quoted content
# with "Q" / 'Q' placeholders, so these `|` `&` characters are structural
# operators, not literal text.
PROCESSED="${PROCESSED//&&/;}"
PROCESSED="${PROCESSED//||/;}"
PROCESSED="${PROCESSED//|&/;}"
PROCESSED="${PROCESSED//|/;}"

# Fail-safe: if preprocessing produced nothing for a non-empty command, defer
# to default permission flow rather than auto-allowing.
[ -z "$PROCESSED" ] && echo '{}' && exit 0

all_allowed=true
used_session_authored=false
used_local_script=false
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

        # Fast path: "bash script.sh" / "zsh script.sh" style invocations
        # where the script lives inside the project tree. Gated on the raw
        # $COMMAND being free of URLs, backticks, and $(...) substitutions
        # — dynamic construction warrants manual review. Second token must
        # be a bare path (no leading '-' flag like `bash -c "..."`).
        case "$base" in
            bash|sh|zsh|dash)
                case "$COMMAND" in
                    *'http://'*|*'https://'*|*'ftp://'*|*'file://'*) ;;
                    *'$('*|*'`'*) ;;
                    *)
                        second=$(echo "$stmt" | awk '{print $2}')
                        if project_local_script "$second"; then
                            used_local_script=true
                            continue
                        fi
                        ;;
                esac
                ;;
        esac

        if ! allow_match "$base"; then
            all_allowed=false
            break 2
        fi
    done
done <<< "$PROCESSED"

if [ "$all_allowed" = true ]; then
    reason="All command prefixes are in allow list"
    provenance=""
    [ "$used_session_authored" = true ] && provenance="session-authored"
    if [ "$used_local_script" = true ]; then
        provenance="${provenance:+$provenance and }project-local script"
    fi
    [ -n "$provenance" ] && reason="$reason (includes $provenance provenance)"
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"%s"}}\n' "$reason"
else
    echo '{}'
fi
