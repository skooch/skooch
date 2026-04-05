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

# --- _profile_apply_mise ---

_TEST_NAME="apply_mise symlinks config.toml for single source"
cat > "$PROFILES_DIR/default/mise/config.toml" << 'EOF'
[settings]
trusted_config_paths = ["~/projects"]

[tools]
node = "lts"
EOF
rm -f "$TEST_HOME/.config/mise/config.toml"
_profile_apply_mise "default" > /dev/null 2>&1
assert_symlink "$TEST_HOME/.config/mise/config.toml" "$PROFILES_DIR/default/mise/config.toml"

_TEST_NAME="apply_mise single-source symlink stays current when source changes"
cat > "$PROFILES_DIR/default/mise/config.toml" << 'EOF'
[settings]
trusted_config_paths = ["~/projects", "~/blinq"]

[tools]
node = "lts"
EOF
local apply_mise_live_content=$(cat "$TEST_HOME/.config/mise/config.toml")
assert_contains "$apply_mise_live_content" "~/blinq"

_TEST_NAME="apply_mise merges config.toml for multiple sources"
cat > "$PROFILES_DIR/default/mise/config.toml" << 'EOF'
[settings]
trusted_config_paths = ["~/projects"]

[tools]
node = "lts"
EOF
cat > "$PROFILES_DIR/testprofile/mise/config.toml" << 'EOF'
[settings]
not_found_auto_install = true

[tools]
python = "3.12"
EOF
rm -f "$TEST_HOME/.config/mise/config.toml"
_profile_apply_mise "testprofile" > /dev/null 2>&1
assert_not_symlink "$TEST_HOME/.config/mise/config.toml" "multiple mise sources should merge into a regular file"
local apply_mise_merged_content=$(cat "$TEST_HOME/.config/mise/config.toml")
assert_contains "$apply_mise_merged_content" 'trusted_config_paths = ["~/projects"]'
_TEST_NAME="apply_mise merged config.toml includes tools from later profiles"
assert_contains "$apply_mise_merged_content" 'python = "3.12"'

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

# --- _profile_apply_claude: statusline.sh symlink ---

_TEST_NAME="apply_claude symlinks statusline.sh"
echo '#!/bin/bash' > "$PROFILES_DIR/default/claude/statusline.sh"
rm -f "$TEST_HOME/.claude/statusline.sh"
_profile_apply_claude "default" > /dev/null 2>&1
assert_symlink "$TEST_HOME/.claude/statusline.sh" "$PROFILES_DIR/default/claude/statusline.sh"

_TEST_NAME="apply_claude statusline.sh last profile wins"
mkdir -p "$PROFILES_DIR/testprofile/claude"
echo '{"extra": true}' > "$PROFILES_DIR/testprofile/claude/settings.json"
echo '#!/bin/bash' > "$PROFILES_DIR/testprofile/claude/statusline.sh"
rm -f "$TEST_HOME/.claude/statusline.sh"
_profile_apply_claude "testprofile" > /dev/null 2>&1
assert_symlink "$TEST_HOME/.claude/statusline.sh" "$PROFILES_DIR/testprofile/claude/statusline.sh"
rm -f "$PROFILES_DIR/testprofile/claude/statusline.sh"

# --- _profile_apply_claude: sync-plugins.sh symlink ---

_TEST_NAME="apply_claude symlinks sync-plugins.sh"
echo '#!/bin/bash' > "$PROFILES_DIR/default/claude/sync-plugins.sh"
rm -f "$TEST_HOME/.claude/sync-plugins.sh"
_profile_apply_claude "default" > /dev/null 2>&1
assert_symlink "$TEST_HOME/.claude/sync-plugins.sh" "$PROFILES_DIR/default/claude/sync-plugins.sh"

# --- _profile_apply_claude: read-once/hook.sh symlink ---

_TEST_NAME="apply_claude symlinks read-once hook"
mkdir -p "$PROFILES_DIR/default/claude/read-once"
echo '#!/bin/bash' > "$PROFILES_DIR/default/claude/read-once/hook.sh"
rm -f "$TEST_HOME/.claude/read-once/hook.sh"
_profile_apply_claude "default" > /dev/null 2>&1
assert_symlink "$TEST_HOME/.claude/read-once/hook.sh" "$PROFILES_DIR/default/claude/read-once/hook.sh"

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

_TEST_NAME="apply_skills symlinks shared skill into claude"
mkdir -p "$PROFILES_DIR/default/skills/shared/my-skill"
echo "# My skill" > "$PROFILES_DIR/default/skills/shared/my-skill/SKILL.md"
rm -rf "$TEST_HOME/.claude/skills/my-skill" "$TEST_HOME/.codex/skills/my-skill"
_profile_apply_skills "default" > /dev/null 2>&1
if [[ -L "$TEST_HOME/.claude/skills/my-skill" ]]; then
    local skill_target=$(readlink "$TEST_HOME/.claude/skills/my-skill")
    assert_eq "$PROFILES_DIR/default/skills/shared/my-skill" "$skill_target"
else
    fail "'$TEST_HOME/.claude/skills/my-skill' is not a symlink"
fi

# --- _profile_apply_claude: commands ---

_TEST_NAME="apply_claude symlinks command markdown files"
mkdir -p "$PROFILES_DIR/default/claude/commands"
echo "# Command" > "$PROFILES_DIR/default/claude/commands/test-command.md"
rm -f "$TEST_HOME/.claude/commands/test-command.md"
_profile_apply_claude "default" > /dev/null 2>&1
assert_symlink "$TEST_HOME/.claude/commands/test-command.md" "$PROFILES_DIR/default/claude/commands/test-command.md"

# --- _profile_apply_codex ---

_TEST_NAME="apply_codex symlinks config.toml for single source"
rm -f "$TEST_HOME/.codex/config.toml"
_profile_apply_codex "default" > /dev/null 2>&1
assert_symlink "$TEST_HOME/.codex/config.toml" "$PROFILES_DIR/default/codex/config.toml"

_TEST_NAME="apply_codex merges config.toml for multiple sources"
rm -f "$TEST_HOME/.codex/config.toml"
_profile_apply_codex "testprofile" > /dev/null 2>&1
assert_not_symlink "$TEST_HOME/.codex/config.toml" "multiple codex config sources should merge into a regular file"
local codex_config_content=$(cat "$TEST_HOME/.codex/config.toml")
assert_contains "$codex_config_content" 'model = "gpt-5.4"'
_TEST_NAME="apply_codex merged config.toml includes later profile values"
assert_contains "$codex_config_content" 'approval_policy = "on-request"'

_TEST_NAME="apply_codex merges hooks.json for multiple sources"
rm -f "$TEST_HOME/.codex/hooks.json"
_profile_apply_codex "testprofile" > /dev/null 2>&1
assert_not_symlink "$TEST_HOME/.codex/hooks.json" "multiple codex hooks sources should merge into a regular file"
if grep -q "SessionStart" "$TEST_HOME/.codex/hooks.json"; then
    pass
else
    fail "'SessionStart' not found in output"
fi
_TEST_NAME="apply_codex merged hooks.json keeps later hook entries"
if grep -q "Stop" "$TEST_HOME/.codex/hooks.json"; then
    pass
else
    fail "'Stop' not found in output"
fi

_TEST_NAME="apply_codex rules last profile wins"
mkdir -p "$PROFILES_DIR/testprofile/codex/rules"
echo 'prefix_rule(pattern = ["cat"], decision = "allow")' > "$PROFILES_DIR/testprofile/codex/rules/default.rules"
rm -f "$TEST_HOME/.codex/rules/default.rules"
_profile_apply_codex "testprofile" > /dev/null 2>&1
assert_symlink "$TEST_HOME/.codex/rules/default.rules" "$PROFILES_DIR/testprofile/codex/rules/default.rules"
rm -f "$PROFILES_DIR/testprofile/codex/rules/default.rules"

_TEST_NAME="apply_codex symlinks codex hooks"
mkdir -p "$PROFILES_DIR/testprofile/codex/hooks"
echo '#!/usr/bin/env python3' > "$PROFILES_DIR/testprofile/codex/hooks/extra_hook.py"
rm -f "$TEST_HOME/.codex/hooks/permission_bridge.py" "$TEST_HOME/.codex/hooks/run-with-python3" "$TEST_HOME/.codex/hooks/extra_hook.py"
_profile_apply_codex "testprofile" > /dev/null 2>&1
assert_symlink "$TEST_HOME/.codex/hooks/permission_bridge.py" "$PROFILES_DIR/default/codex/hooks/permission_bridge.py"
_TEST_NAME="apply_codex symlinks shared python launcher hook"
assert_symlink "$TEST_HOME/.codex/hooks/run-with-python3" "$PROFILES_DIR/default/codex/hooks/run-with-python3"
_TEST_NAME="apply_codex symlinks unioned extra codex hooks"
assert_symlink "$TEST_HOME/.codex/hooks/extra_hook.py" "$PROFILES_DIR/testprofile/codex/hooks/extra_hook.py"

_TEST_NAME="apply_codex symlinks codex agents"
mkdir -p "$PROFILES_DIR/testprofile/codex/agents"
echo 'name = "worker"' > "$PROFILES_DIR/testprofile/codex/agents/worker.toml"
rm -f "$TEST_HOME/.codex/agents/explorer.toml" "$TEST_HOME/.codex/agents/worker.toml"
_profile_apply_codex "testprofile" > /dev/null 2>&1
assert_symlink "$TEST_HOME/.codex/agents/explorer.toml" "$PROFILES_DIR/default/codex/agents/explorer.toml"
_TEST_NAME="apply_codex symlinks unioned codex agent overrides"
assert_symlink "$TEST_HOME/.codex/agents/worker.toml" "$PROFILES_DIR/testprofile/codex/agents/worker.toml"

_TEST_NAME="apply_skills routes codex-only skill to codex only"
mkdir -p "$PROFILES_DIR/default/skills/codex/codex-only-skill"
echo "# Codex only" > "$PROFILES_DIR/default/skills/codex/codex-only-skill/SKILL.md"
rm -rf "$TEST_HOME/.codex/skills/codex-only-skill" "$TEST_HOME/.claude/skills/codex-only-skill"
_profile_apply_skills "default" > /dev/null 2>&1
if [[ -L "$TEST_HOME/.codex/skills/codex-only-skill" ]]; then
    local codex_skill_target=$(readlink "$TEST_HOME/.codex/skills/codex-only-skill")
    assert_eq "$PROFILES_DIR/default/skills/codex/codex-only-skill" "$codex_skill_target"
else
    fail "'$TEST_HOME/.codex/skills/codex-only-skill' is not a symlink"
fi

_TEST_NAME="apply_skills does not route codex-only skill to claude"
if [[ -e "$TEST_HOME/.claude/skills/codex-only-skill" ]]; then
    fail "codex-only skill should not appear in claude"
else
    pass
fi

_TEST_NAME="apply_skills routes shared skill to both agents"
if [[ -L "$TEST_HOME/.codex/skills/my-skill" ]]; then
    pass
else
    fail "shared skill should appear in codex"
fi

_TEST_NAME="apply_codex creates AGENTS bridge to claude instructions"
echo "# Test instructions" > "$PROFILES_DIR/default/claude/CLAUDE.md"
_profile_apply_claude "default" > /dev/null 2>&1
rm -f "$TEST_HOME/.codex/AGENTS.md"
_profile_apply_codex "default" > /dev/null 2>&1
assert_symlink "$TEST_HOME/.codex/AGENTS.md" "$TEST_HOME/.claude/CLAUDE.md"

# Clean up test fixtures
rm -rf "$PROFILES_DIR/default/claude/hooks" "$PROFILES_DIR/default/skills"
rm -rf "$PROFILES_DIR/default/claude/read-once" "$PROFILES_DIR/default/claude/commands"
rm -rf "$PROFILES_DIR/testprofile/claude/hooks"
rm -f "$PROFILES_DIR/default/claude/CLAUDE.md" "$PROFILES_DIR/default/claude/system-prompt.md"
rm -f "$PROFILES_DIR/default/claude/statusline.sh" "$PROFILES_DIR/default/claude/sync-plugins.sh"
rm -rf "$PROFILES_DIR/testprofile/codex/hooks" "$PROFILES_DIR/testprofile/codex/agents"

# --- _profile_apply_tmux ---

_TEST_NAME="apply_tmux skips when no tmux config exists"
rm -rf "$PROFILES_DIR/default/tmux" "$PROFILES_DIR/testprofile/tmux"
rm -f "$TEST_HOME/.tmux.conf"
_profile_apply_tmux "default" > /dev/null 2>&1
assert_eq "1" "$([[ ! -f "$TEST_HOME/.tmux.conf" ]] && echo 1 || echo 0)"

_test_summary
