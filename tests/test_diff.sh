#!/usr/bin/env zsh
# Test diff/preview helpers for generic profile-tree behavior.

source "${0:A:h}/harness.sh"

HOME="$TEST_HOME"
mkdir -p "$TEST_HOME/.claude" "$TEST_HOME/.codex"

_TEST_NAME="diff_structured_profile_config reports missing codex config"
local config_diff=$(_profile_diff_structured_profile_config "default" "codex" "config.toml" "$TEST_HOME/.codex" "toml" "codex (~/.codex/config.toml)" "diff" 2>&1)
assert_contains "$config_diff" "codex (~/.codex/config.toml)"

_TEST_NAME="diff_structured_profile_config reports new file creation"
assert_contains "$config_diff" "new file would be created"

_TEST_NAME="diff_last_wins_paths reports missing nested codex rules file"
local rules_diff=$(_profile_diff_last_wins_paths "default" "codex" "$TEST_HOME/.codex" "codex" "diff" "${_CODEX_LAST_WINS_PATHS[@]}" 2>&1)
assert_contains "$rules_diff" "codex/rules/default.rules"

_TEST_NAME="diff_union_file_collection reports missing codex hook link"
local hooks_diff=$(_profile_diff_union_file_collection "default" "codex" "hooks" "*" "$TEST_HOME/.codex" "codex/hooks" "diff" 2>&1)
assert_contains "$hooks_diff" "codex/hooks/permission_bridge.py"

_TEST_NAME="diff_skills reports missing shared skill link"
mkdir -p "$PROFILES_DIR/default/skills/shared/my-skill"
echo "# skill" > "$PROFILES_DIR/default/skills/shared/my-skill/SKILL.md"
local skills_diff=$(_profile_diff_skills "default" 2>&1)
assert_contains "$skills_diff" "skills/my-skill"

_TEST_NAME="diff_skills is quiet when skills are linked"
_profile_apply_skills "default" > /dev/null 2>&1
local quiet_skills_diff=$(_profile_diff_skills "default" 2>&1)
assert_eq "" "$quiet_skills_diff"
rm -rf "$PROFILES_DIR/default/skills"

_TEST_NAME="diff_derived_symlink reports missing codex AGENTS bridge"
echo "# instructions" > "$PROFILES_DIR/default/claude/CLAUDE.md"
_profile_apply_claude "default" > /dev/null 2>&1
local agents_diff=$(_profile_diff_derived_symlink "codex/AGENTS.md (~/.codex/AGENTS.md)" "$TEST_HOME/.claude/CLAUDE.md" "$TEST_HOME/.codex/AGENTS.md" 2>&1)
assert_contains "$agents_diff" "codex/AGENTS.md (~/.codex/AGENTS.md)"

_TEST_NAME="diff_derived_symlink is quiet when bridge is correct"
ln -sf "$TEST_HOME/.claude/CLAUDE.md" "$TEST_HOME/.codex/AGENTS.md"
local quiet_agents_diff=$(_profile_diff_derived_symlink "codex/AGENTS.md (~/.codex/AGENTS.md)" "$TEST_HOME/.claude/CLAUDE.md" "$TEST_HOME/.codex/AGENTS.md" 2>&1)
assert_eq "" "$quiet_agents_diff"
rm -f "$PROFILES_DIR/default/claude/CLAUDE.md"

_test_summary
