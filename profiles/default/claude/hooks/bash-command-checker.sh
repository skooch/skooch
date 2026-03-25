#!/bin/bash
# PreToolUse hook: validates Bash commands against the allow list in settings.json.
# Multi-line commands are allowed only if every meaningful line's first token is allowed.
# Derives the allow list from Bash() permissions — single source of truth.
# Input: JSON via stdin with tool_input.command

SETTINGS="$HOME/.claude/settings.json"
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

[ -z "$COMMAND" ] && echo '{}' && exit 0

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
#"

ALLOW_LIST=$(printf '%s\n%s' "$ALLOW_LIST" "$BUILTINS")

# Build a regex from the allow list, escaping regex metacharacters
ALLOW_RE=$(echo "$ALLOW_LIST" | sed '/^$/d' \
    | sed 's/\./\\./g; s/\[/\\[/g; s/\*/\\*/g; s/\+/\\+/g; s/\?/\\?/g' \
    | tr '\n' '|' | sed 's/|$//')

all_allowed=true
in_heredoc=""
while IFS= read -r line; do
    # Track heredoc state — skip body lines
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

    # Extract first token
    first=$(echo "$stripped" | awk '{print $1}')

    # Skip variable assignments (FOO=bar, FOO="bar", etc.)
    case "$first" in
        *=*) continue ;;
    esac

    # Skip shell operators that start continuation lines
    case "$first" in
        '||'|'&&'|'|'|'|&'|')'|';;') continue ;;
    esac

    # Strip path prefix for absolute paths (/usr/bin/env -> env)
    base="${first##*/}"

    if ! echo "$base" | grep -qxE "$ALLOW_RE" 2>/dev/null; then
        all_allowed=false
        break
    fi
done <<< "$COMMAND"

if [ "$all_allowed" = true ]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"All command prefixes are in allow list"}}'
else
    echo '{}'
fi
