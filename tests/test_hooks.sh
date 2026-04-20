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

# Fake settings.json with a controlled allow list
cat > "$TEST_SETTINGS" <<'EOF'
{
    "permissions": {
        "allow": [
            "Bash(git:*)",
            "Bash(ls:*)",
            "Bash(echo:*)",
            "Bash([:*)",
            "Bash(xtensa-esp32s3-elf*:*)"
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
