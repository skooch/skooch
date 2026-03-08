#!/usr/bin/env zsh
# Test apply functions: git, claude (symlink vs merge), mise merging logic

source "${0:A:h}/harness.sh"

# Override HOME for apply functions that write to $HOME
HOME="$TEST_HOME"
mkdir -p "$TEST_HOME/.config/mise" "$TEST_HOME/.claude"

# --- _profile_apply_git ---

_TEST_NAME="apply_git creates gitconfig with includes"
_profile_apply_git "testprofile" > /dev/null 2>&1
assert_file_exists "$TEST_HOME/.gitconfig"

_TEST_NAME="apply_git includes default config path"
local git_content=$(cat "$TEST_HOME/.gitconfig")
assert_contains "$git_content" "default/git/config"

# --- _profile_apply_claude (regression: symlink for single source) ---

_TEST_NAME="apply_claude symlinks for single source"
# Remove testprofile claude so only default exists
rm -f "$PROFILES_DIR/testprofile/claude/settings.json"
_profile_apply_claude "default" > /dev/null 2>&1
local target="$TEST_HOME/.claude/settings.json"
assert_symlink "$target" "$PROFILES_DIR/default/claude/settings.json"

_TEST_NAME="apply_claude merges for multiple sources"
echo '{"extra": true}' > "$PROFILES_DIR/testprofile/claude/settings.json"
rm -f "$TEST_HOME/.claude/settings.json"
_profile_apply_claude "testprofile" > /dev/null 2>&1
local target="$TEST_HOME/.claude/settings.json"
assert_not_symlink "$target" "multiple sources should produce a regular file"
local content=$(cat "$target")
assert_contains "$content" "test"
assert_contains "$content" "extra"

# --- Default double-counting regression ---

_TEST_NAME="apply_claude with active_set=default does not double-count"
rm -f "$TEST_HOME/.claude/settings.json"
rm -f "$PROFILES_DIR/testprofile/claude/settings.json"
_profile_apply_claude "default" > /dev/null 2>&1
# Should be a symlink (single source), not a merged file
assert_symlink "$TEST_HOME/.claude/settings.json" "$PROFILES_DIR/default/claude/settings.json"

# --- apply_git with active_set=default does not double-count ---

_TEST_NAME="apply_git with active_set=default has single include"
rm -f "$TEST_HOME/.gitconfig"
_profile_apply_git "default" > /dev/null 2>&1
local git_content=$(cat "$TEST_HOME/.gitconfig")
local include_count=$(echo "$git_content" | grep -c '\[include\]')
assert_eq "1" "$include_count" "default should only have one [include] block"

# Restore
echo '{"extra": true}' > "$PROFILES_DIR/testprofile/claude/settings.json"
printf '[tools]\nnode = "lts"\n' > "$PROFILES_DIR/default/mise/config.toml"
printf '[tools]\npython = "3.12"\n' > "$PROFILES_DIR/testprofile/mise/config.toml"

_test_summary
