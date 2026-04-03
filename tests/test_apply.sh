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

_TEST_NAME="apply_git ignores local cache config files"
mkdir -p "$TEST_HOME/.config/git"
echo "[url \"http://127.0.0.1:1234/github.com/\"]" > "$TEST_HOME/.config/git/cache.inc"
rm -f "$TEST_HOME/.gitconfig"
_profile_apply_git "default" > /dev/null 2>&1
git_content=$(cat "$TEST_HOME/.gitconfig")
assert_not_contains "$git_content" ".config/git/cache.inc"

# Restore
echo '{"extra": true}' > "$PROFILES_DIR/testprofile/claude/settings.json"
printf '[tools]\nnode = "lts"\n' > "$PROFILES_DIR/default/mise/config.toml"
printf '[tools]\npython = "3.12"\n' > "$PROFILES_DIR/testprofile/mise/config.toml"

# --- _profile_apply_tmux ---

_TEST_NAME="apply_tmux copies winning profile tmux.conf to home"
mkdir -p "$PROFILES_DIR/default/tmux"
echo "set -g mouse on" > "$PROFILES_DIR/default/tmux/tmux.conf"
_profile_apply_tmux "default" > /dev/null 2>&1
assert_eq "set -g mouse on" "$(cat "$TEST_HOME/.tmux.conf")"

_TEST_NAME="apply_tmux last profile wins"
mkdir -p "$PROFILES_DIR/testprofile/tmux"
echo "set -g mouse off" > "$PROFILES_DIR/testprofile/tmux/tmux.conf"
_profile_apply_tmux "testprofile" > /dev/null 2>&1
assert_eq "set -g mouse off" "$(cat "$TEST_HOME/.tmux.conf")"

# --- _profile_apply_claude: CLAUDE.md symlink ---

_TEST_NAME="apply_claude symlinks CLAUDE.md"
echo "# Test instructions" > "$PROFILES_DIR/default/claude/CLAUDE.md"
rm -f "$TEST_HOME/.claude/CLAUDE.md"
_profile_apply_claude "default" > /dev/null 2>&1
assert_symlink "$TEST_HOME/.claude/CLAUDE.md" "$PROFILES_DIR/default/claude/CLAUDE.md"

_TEST_NAME="apply_claude CLAUDE.md last profile wins"
mkdir -p "$PROFILES_DIR/testprofile/claude"
echo '{"extra": true}' > "$PROFILES_DIR/testprofile/claude/settings.json"
echo "# Override instructions" > "$PROFILES_DIR/testprofile/claude/CLAUDE.md"
rm -f "$TEST_HOME/.claude/CLAUDE.md"
_profile_apply_claude "testprofile" > /dev/null 2>&1
assert_symlink "$TEST_HOME/.claude/CLAUDE.md" "$PROFILES_DIR/testprofile/claude/CLAUDE.md"
rm -f "$PROFILES_DIR/testprofile/claude/CLAUDE.md"

# --- _profile_apply_claude: system-prompt.md symlink ---

_TEST_NAME="apply_claude symlinks system-prompt.md"
echo "# Test prompt" > "$PROFILES_DIR/default/claude/system-prompt.md"
rm -f "$TEST_HOME/.claude/system-prompt.md"
_profile_apply_claude "default" > /dev/null 2>&1
assert_symlink "$TEST_HOME/.claude/system-prompt.md" "$PROFILES_DIR/default/claude/system-prompt.md"

_TEST_NAME="apply_claude system-prompt.md last profile wins"
mkdir -p "$PROFILES_DIR/testprofile/claude"
echo '{"extra": true}' > "$PROFILES_DIR/testprofile/claude/settings.json"
echo "# Override prompt" > "$PROFILES_DIR/testprofile/claude/system-prompt.md"
rm -f "$TEST_HOME/.claude/system-prompt.md"
_profile_apply_claude "testprofile" > /dev/null 2>&1
assert_symlink "$TEST_HOME/.claude/system-prompt.md" "$PROFILES_DIR/testprofile/claude/system-prompt.md"
rm -f "$PROFILES_DIR/testprofile/claude/system-prompt.md"

# --- _profile_apply_claude: hooks ---

_TEST_NAME="apply_claude symlinks hook scripts"
mkdir -p "$PROFILES_DIR/default/claude/hooks"
echo '#!/bin/bash' > "$PROFILES_DIR/default/claude/hooks/test-hook.sh"
chmod +x "$PROFILES_DIR/default/claude/hooks/test-hook.sh"
rm -f "$TEST_HOME/.claude/hooks/test-hook.sh"
_profile_apply_claude "default" > /dev/null 2>&1
assert_symlink "$TEST_HOME/.claude/hooks/test-hook.sh" "$PROFILES_DIR/default/claude/hooks/test-hook.sh"

_TEST_NAME="apply_claude hooks union across profiles"
mkdir -p "$PROFILES_DIR/testprofile/claude/hooks"
echo '#!/bin/bash' > "$PROFILES_DIR/testprofile/claude/hooks/other-hook.sh"
rm -f "$TEST_HOME/.claude/hooks/test-hook.sh" "$TEST_HOME/.claude/hooks/other-hook.sh"
_profile_apply_claude "testprofile" > /dev/null 2>&1
assert_symlink "$TEST_HOME/.claude/hooks/test-hook.sh" "$PROFILES_DIR/default/claude/hooks/test-hook.sh"
assert_symlink "$TEST_HOME/.claude/hooks/other-hook.sh" "$PROFILES_DIR/testprofile/claude/hooks/other-hook.sh"

# --- _profile_apply_claude: skills ---

_TEST_NAME="apply_claude symlinks skill directories"
mkdir -p "$PROFILES_DIR/default/claude/skills/my-skill"
echo "# My skill" > "$PROFILES_DIR/default/claude/skills/my-skill/SKILL.md"
rm -rf "$TEST_HOME/.claude/skills/my-skill"
_profile_apply_claude "default" > /dev/null 2>&1
if [[ -L "$TEST_HOME/.claude/skills/my-skill" ]]; then
    local skill_target=$(readlink "$TEST_HOME/.claude/skills/my-skill")
    assert_eq "$PROFILES_DIR/default/claude/skills/my-skill" "$skill_target"
else
    fail "'$TEST_HOME/.claude/skills/my-skill' is not a symlink"
fi

# Clean up test fixtures
rm -rf "$PROFILES_DIR/default/claude/hooks" "$PROFILES_DIR/default/claude/skills"
rm -rf "$PROFILES_DIR/testprofile/claude/hooks"
rm -f "$PROFILES_DIR/default/claude/CLAUDE.md" "$PROFILES_DIR/default/claude/system-prompt.md"

# --- _profile_apply_tmux ---

_TEST_NAME="apply_tmux skips when no tmux config exists"
rm -rf "$PROFILES_DIR/default/tmux" "$PROFILES_DIR/testprofile/tmux"
rm -f "$TEST_HOME/.tmux.conf"
_profile_apply_tmux "default" > /dev/null 2>&1
assert_eq "1" "$([[ ! -f "$TEST_HOME/.tmux.conf" ]] && echo 1 || echo 0)"

_test_summary
