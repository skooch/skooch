#!/usr/bin/env zsh
# Tests for ~/.claude hook scripts: bash-command-checker, subagent-spawn-logger,
# cbm-session-reminder, skill-auto-share.
#
# Hooks accept env-var overrides (CLAUDE_SETTINGS_FILE, CLAUDE_SUBAGENT_LOG)
# so we can test without hijacking $HOME (which would break mise-shimmed tools).

source "${0:A:h}/harness.sh"

REPO_HOOKS="${0:A:h}/../profiles/default/claude/hooks"
TEST_SETTINGS="$TEST_HOME/.claude/settings.json"
TEST_LOG="$TEST_HOME/.claude/hooks/subagent-spawns.log"
mkdir -p "$TEST_HOME/.claude/hooks"

# Fake settings.json with a controlled allow list plus an additional
# working directory so project-local-script tests can exercise the
# cross-project path (script lives outside CWD's git root but inside a
# session-trusted directory).
TEST_EXTRA_TREE="$TEST_HOME/extra-tree"
mkdir -p "$TEST_EXTRA_TREE/scripts"
touch "$TEST_EXTRA_TREE/scripts/external.sh"

cat > "$TEST_SETTINGS" <<EOF
{
    "permissions": {
        "allow": [
            "Bash(git:*)",
            "Bash(ls:*)",
            "Bash(echo:*)",
            "Bash([:*)",
            "Bash(xtensa-esp32s3-elf*:*)"
        ],
        "additionalDirectories": [
            "$TEST_EXTRA_TREE"
        ]
    }
}
EOF

# === bash-command-checker.sh ===
CHECKER="$REPO_HOOKS/bash-command-checker.sh"

_TEST_NAME="bash-command-checker allows known prefix"
result=$(echo '{"tool_input":{"command":"git status"}}' | CLAUDE_SETTINGS_FILE="$TEST_SETTINGS" "$CHECKER")
assert_contains "$result" '"permissionDecision":"allow"'

_TEST_NAME="bash-command-checker denies unknown prefix"
result=$(echo '{"tool_input":{"command":"obviouslynotallowed --foo"}}' | CLAUDE_SETTINGS_FILE="$TEST_SETTINGS" "$CHECKER")
assert_eq "{}" "$result"

_TEST_NAME="bash-command-checker allows multi-statement when every prefix is allowed"
result=$(echo '{"tool_input":{"command":"git status; ls -la; echo done"}}' | CLAUDE_SETTINGS_FILE="$TEST_SETTINGS" "$CHECKER")
assert_contains "$result" '"permissionDecision":"allow"'

_TEST_NAME="bash-command-checker denies multi-statement with one disallowed prefix"
result=$(echo '{"tool_input":{"command":"git status; rogue --do"}}' | CLAUDE_SETTINGS_FILE="$TEST_SETTINGS" "$CHECKER")
assert_eq "{}" "$result"

_TEST_NAME="bash-command-checker handles regex-meta tokens like [ via exact-match"
result=$(echo '{"tool_input":{"command":"[ -f foo ]"}}' | CLAUDE_SETTINGS_FILE="$TEST_SETTINGS" "$CHECKER")
assert_contains "$result" '"permissionDecision":"allow"'

_TEST_NAME="bash-command-checker allows glob-wildcard prefix (xtensa-esp32s3-elf* matches -nm)"
result=$(echo '{"tool_input":{"command":"xtensa-esp32s3-elf-nm /tmp/bin"}}' | CLAUDE_SETTINGS_FILE="$TEST_SETTINGS" "$CHECKER")
assert_contains "$result" '"permissionDecision":"allow"'

_TEST_NAME="bash-command-checker glob prefix does not over-match unrelated commands"
result=$(echo '{"tool_input":{"command":"xtensa-other-toolchain --foo"}}' | CLAUDE_SETTINGS_FILE="$TEST_SETTINGS" "$CHECKER")
assert_eq "{}" "$result"

_TEST_NAME="bash-command-checker strips subshell parens around allowed commands"
result=$(echo '{"tool_input":{"command":"(echo halt; echo resume) | ls"}}' | CLAUDE_SETTINGS_FILE="$TEST_SETTINGS" "$CHECKER")
assert_contains "$result" '"permissionDecision":"allow"'

_TEST_NAME="bash-command-checker subshell with disallowed inner stmt is denied"
result=$(echo '{"tool_input":{"command":"(echo halt; rogue --x)"}}' | CLAUDE_SETTINGS_FILE="$TEST_SETTINGS" "$CHECKER")
assert_eq "{}" "$result"

# Set up a fake project tree for project-local-script tests. Marking it
# with an empty .git dir triggers the root-walk to stop here.
TEST_PROJ="$TEST_HOME/fakeproj"
mkdir -p "$TEST_PROJ/tests" "$TEST_PROJ/.git"
touch "$TEST_PROJ/tests/run.sh"

_TEST_NAME="bash-command-checker allows 'bash <script>' inside project tree"
result=$(printf '{"cwd":"%s","tool_input":{"command":"bash tests/run.sh"}}' "$TEST_PROJ" \
    | CLAUDE_SETTINGS_FILE="$TEST_SETTINGS" "$CHECKER")
assert_contains "$result" '"permissionDecision":"allow"'
assert_contains "$result" 'project-local script'

_TEST_NAME="bash-command-checker allows 'bash <script>' with pipeline tail inside project"
result=$(printf '{"cwd":"%s","tool_input":{"command":"bash tests/run.sh 2>&1 | ls"}}' "$TEST_PROJ" \
    | CLAUDE_SETTINGS_FILE="$TEST_SETTINGS" "$CHECKER")
assert_contains "$result" '"permissionDecision":"allow"'

_TEST_NAME="bash-command-checker denies 'bash <script>' outside project tree"
result=$(printf '{"cwd":"%s","tool_input":{"command":"bash /etc/hosts"}}' "$TEST_PROJ" \
    | CLAUDE_SETTINGS_FILE="$TEST_SETTINGS" "$CHECKER")
assert_eq "{}" "$result"

_TEST_NAME="bash-command-checker denies 'bash -c' (flag rejects fast path)"
result=$(printf '{"cwd":"%s","tool_input":{"command":"bash -c '"'"'echo hi'"'"'"}}' "$TEST_PROJ" \
    | CLAUDE_SETTINGS_FILE="$TEST_SETTINGS" "$CHECKER")
assert_eq "{}" "$result"

_TEST_NAME="bash-command-checker denies 'bash <script>' with command substitution"
result=$(printf '{"cwd":"%s","tool_input":{"command":"bash tests/run.sh $(ls /)"}}' "$TEST_PROJ" \
    | CLAUDE_SETTINGS_FILE="$TEST_SETTINGS" "$CHECKER")
assert_eq "{}" "$result"

_TEST_NAME="bash-command-checker denies 'bash <script>' when command contains URL"
result=$(printf '{"cwd":"%s","tool_input":{"command":"bash tests/run.sh # https://evil.example"}}' "$TEST_PROJ" \
    | CLAUDE_SETTINGS_FILE="$TEST_SETTINGS" "$CHECKER")
assert_eq "{}" "$result"

_TEST_NAME="bash-command-checker allows absolute-path script under additionalDirectories (cross-project)"
result=$(printf '{"cwd":"%s","tool_input":{"command":"sh %s/scripts/external.sh arg1 arg2"}}' \
    "$TEST_PROJ" "$TEST_EXTRA_TREE" \
    | CLAUDE_SETTINGS_FILE="$TEST_SETTINGS" "$CHECKER")
assert_contains "$result" '"permissionDecision":"allow"'

_TEST_NAME="bash-command-checker denies absolute-path script outside all trusted roots"
result=$(printf '{"cwd":"%s","tool_input":{"command":"sh /etc/hostconfig"}}' "$TEST_PROJ" \
    | CLAUDE_SETTINGS_FILE="$TEST_SETTINGS" "$CHECKER")
assert_eq "{}" "$result"

_TEST_NAME="bash-command-checker allows && chain of two in-project scripts"
result=$(printf '{"cwd":"%s","tool_input":{"command":"sh tests/run.sh clean && sh tests/run.sh build"}}' "$TEST_PROJ" \
    | CLAUDE_SETTINGS_FILE="$TEST_SETTINGS" "$CHECKER")
assert_contains "$result" '"permissionDecision":"allow"'

_TEST_NAME="bash-command-checker denies && chain when second half is untrusted"
result=$(printf '{"cwd":"%s","tool_input":{"command":"sh tests/run.sh clean && sh /etc/hostconfig build"}}' "$TEST_PROJ" \
    | CLAUDE_SETTINGS_FILE="$TEST_SETTINGS" "$CHECKER")
assert_eq "{}" "$result"

_TEST_NAME="bash-command-checker denies pipe where second stage is untrusted"
result=$(printf '{"cwd":"%s","tool_input":{"command":"echo hi | rogue --x"}}' "$TEST_PROJ" \
    | CLAUDE_SETTINGS_FILE="$TEST_SETTINGS" "$CHECKER")
assert_eq "{}" "$result"

# === subagent-spawn-logger.sh ===
LOGGER="$REPO_HOOKS/subagent-spawn-logger.sh"

_TEST_NAME="subagent-spawn-logger writes log entry and emits additionalContext"
rm -f "$TEST_LOG" "$TEST_LOG.1"
result=$(echo '{"agent_id":"abc123","agent_type":"general-purpose"}' | CLAUDE_SUBAGENT_LOG="$TEST_LOG" "$LOGGER")
assert_contains "$result" '"hookEventName":"SubagentStart"'
assert_contains "$result" 'Three-tier'
assert_file_exists "$TEST_LOG"
assert_contains "$(cat "$TEST_LOG")" "type=general-purpose id=abc123"

_TEST_NAME="subagent-spawn-logger rotates log when it exceeds 1MB"
dd if=/dev/zero of="$TEST_LOG" bs=1024 count=1500 2>/dev/null
echo '{"agent_id":"x","agent_type":"x"}' | CLAUDE_SUBAGENT_LOG="$TEST_LOG" "$LOGGER" >/dev/null
assert_file_exists "$TEST_LOG.1"

# === cbm-session-reminder ===
REMINDER="$REPO_HOOKS/cbm-session-reminder"

_TEST_NAME="cbm-session-reminder prints discovery protocol text"
result=$("$REMINDER" </dev/null)
assert_contains "$result" "Code Discovery Protocol"
assert_contains "$result" "search_graph"

# === skill-auto-share.sh ===
SHARER="$REPO_HOOKS/skill-auto-share.sh"

_TEST_NAME="skill-auto-share is a no-op for non-SKILL.md files"
result=$(echo '{"tool_input":{"file_path":"/tmp/foo.txt"}}' | "$SHARER")
assert_eq "" "$result"

_TEST_NAME="skill-auto-share is a no-op for SKILL.md outside agent skill dirs"
result=$(echo '{"tool_input":{"file_path":"/tmp/random/SKILL.md"}}' | "$SHARER")
assert_eq "" "$result"

_test_summary
