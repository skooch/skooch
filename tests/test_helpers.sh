#!/usr/bin/env zsh
# Test helper functions: collect_dirs, snapshot_files, read_brew, dedup, etc.

source "${0:A:h}/harness.sh"

# --- _profile_collect_dirs ---

_TEST_NAME="collect_dirs includes default first"
local result=$(_profile_collect_dirs "testprofile")
local first_line=$(echo "$result" | head -1)
assert_contains "$first_line" "/default"

_TEST_NAME="collect_dirs includes named profile"
assert_contains "$result" "/testprofile"

_TEST_NAME="collect_dirs does not duplicate default when active_set=default"
local result_default=$(_profile_collect_dirs "default")
local count=$(echo "$result_default" | grep -c "default")
assert_eq "1" "$count" "default should appear exactly once"

_TEST_NAME="collect_dirs with multiple profiles"
mkdir -p "$PROFILES_DIR/extra"
local result_multi=$(_profile_collect_dirs "testprofile extra")
assert_contains "$result_multi" "/testprofile"
assert_contains "$result_multi" "/extra"
rm -rf "$PROFILES_DIR/extra"

# --- _profile_snapshot_files ---

_TEST_NAME="snapshot_files includes claude/settings.json"
local snap_files=$(_profile_snapshot_files "$PROFILES_DIR/default")
assert_contains "$snap_files" "claude/settings.json"

_TEST_NAME="snapshot_files includes codex/config.toml"
assert_contains "$snap_files" "codex/config.toml"

_TEST_NAME="snapshot_files includes codex/hooks.json"
assert_contains "$snap_files" "codex/hooks.json"

_TEST_NAME="snapshot_files includes git/config"
assert_contains "$snap_files" "git/config"

_TEST_NAME="snapshot_files includes mise/config.toml"
assert_contains "$snap_files" "mise/config.toml"

_TEST_NAME="snapshot_files includes vscode/settings.json"
assert_contains "$snap_files" "vscode/settings.json"

_TEST_NAME="snapshot_files includes iterm/profile.json"
assert_contains "$snap_files" "iterm/profile.json"

_TEST_NAME="snapshot_files includes Brewfile"
assert_contains "$snap_files" "Brewfile"

_TEST_NAME="snapshot_files includes tmux/tmux.conf"
assert_contains "$snap_files" "tmux/tmux.conf"

_TEST_NAME="snapshot_files includes claude/CLAUDE.md"
assert_contains "$snap_files" "claude/CLAUDE.md"

_TEST_NAME="snapshot_files includes claude/system-prompt.md"
assert_contains "$snap_files" "claude/system-prompt.md"

_TEST_NAME="snapshot_files includes claude/statusline.sh"
assert_contains "$snap_files" "claude/statusline.sh"

_TEST_NAME="snapshot_files includes claude/sync-plugins.sh"
assert_contains "$snap_files" "claude/sync-plugins.sh"

_TEST_NAME="snapshot_files includes claude/read-once/hook.sh"
assert_contains "$snap_files" "claude/read-once/hook.sh"

_TEST_NAME="snapshot_files includes codex/rules/default.rules"
assert_contains "$snap_files" "codex/rules/default.rules"

_TEST_NAME="snapshot_files includes codex hook files"
assert_contains "$snap_files" "codex/hooks/permission_bridge.py"

_TEST_NAME="snapshot_files includes codex agent files"
assert_contains "$snap_files" "codex/agents/explorer.toml"

_TEST_NAME="snapshot_files includes claude hook scripts"
mkdir -p "$PROFILES_DIR/default/claude/hooks"
echo '#!/bin/bash' > "$PROFILES_DIR/default/claude/hooks/test-hook.sh"
local snap_with_hooks=$(_profile_snapshot_files "$PROFILES_DIR/default")
assert_contains "$snap_with_hooks" "claude/hooks/test-hook.sh"

_TEST_NAME="snapshot_files includes claude skill SKILL.md"
mkdir -p "$PROFILES_DIR/default/claude/skills/my-skill"
echo "# skill" > "$PROFILES_DIR/default/claude/skills/my-skill/SKILL.md"
local snap_with_skills=$(_profile_snapshot_files "$PROFILES_DIR/default")
assert_contains "$snap_with_skills" "claude/skills/my-skill/SKILL.md"
rm -rf "$PROFILES_DIR/default/claude/hooks" "$PROFILES_DIR/default/claude/skills"

# --- shared profile-tree helpers ---

_TEST_NAME="resolve_last_wins_source handles nested paths"
mkdir -p "$PROFILES_DIR/testprofile/codex/rules"
echo 'prefix_rule(pattern = ["cat"], decision = "allow")' > "$PROFILES_DIR/testprofile/codex/rules/default.rules"
local nested_source=$(_profile_resolve_last_wins_source "testprofile" "codex" "rules/default.rules")
assert_eq "$PROFILES_DIR/testprofile/codex/rules/default.rules" "$nested_source"
rm -f "$PROFILES_DIR/testprofile/codex/rules/default.rules"

_TEST_NAME="collect_union_file_sources keys by basename with last profile wins"
mkdir -p "$PROFILES_DIR/default/codex/hooks" "$PROFILES_DIR/testprofile/codex/hooks"
echo "default" > "$PROFILES_DIR/default/codex/hooks/shared.py"
echo "override" > "$PROFILES_DIR/testprofile/codex/hooks/shared.py"
echo "extra" > "$PROFILES_DIR/testprofile/codex/hooks/extra.py"
local union_files=$(_profile_collect_union_file_sources "testprofile" "codex" "hooks" "*")
assert_contains "$union_files" $'shared.py\t'"$PROFILES_DIR/testprofile/codex/hooks/shared.py"
_TEST_NAME="collect_union_file_sources includes additional basenames"
assert_contains "$union_files" $'extra.py\t'"$PROFILES_DIR/testprofile/codex/hooks/extra.py"
rm -f "$PROFILES_DIR/default/codex/hooks/shared.py" "$PROFILES_DIR/testprofile/codex/hooks/shared.py" "$PROFILES_DIR/testprofile/codex/hooks/extra.py"

_TEST_NAME="collect_union_dir_sources keys by dirname with last profile wins"
mkdir -p "$PROFILES_DIR/default/claude/skills/shared-skill" "$PROFILES_DIR/testprofile/claude/skills/shared-skill" "$PROFILES_DIR/testprofile/claude/skills/extra-skill"
echo "# default" > "$PROFILES_DIR/default/claude/skills/shared-skill/SKILL.md"
echo "# override" > "$PROFILES_DIR/testprofile/claude/skills/shared-skill/SKILL.md"
echo "# extra" > "$PROFILES_DIR/testprofile/claude/skills/extra-skill/SKILL.md"
local union_dirs=$(_profile_collect_union_dir_sources "testprofile" "claude" "skills")
assert_contains "$union_dirs" $'shared-skill\t'"$PROFILES_DIR/testprofile/claude/skills/shared-skill"
_TEST_NAME="collect_union_dir_sources includes additional dirnames"
assert_contains "$union_dirs" $'extra-skill\t'"$PROFILES_DIR/testprofile/claude/skills/extra-skill"
rm -rf "$PROFILES_DIR/default/claude/skills" "$PROFILES_DIR/testprofile/claude/skills"

_TEST_NAME="merge_toml_files deep merges tables and replaces arrays"
local toml_one=$(mktemp)
local toml_two=$(mktemp)
local toml_out=$(mktemp)
cat > "$toml_one" << 'EOF'
model = "gpt-5.4"
notify = ["one", "two"]

[features]
codex_hooks = true
shell_snapshot = false

[nested.alpha]
value = 1
items = ["a"]
EOF
cat > "$toml_two" << 'EOF'
notify = ["override"]

[features]
shell_snapshot = true

[nested.alpha]
items = ["b"]

[nested.beta]
flag = true
EOF
_profile_merge_toml_files "$toml_out" "$toml_one" "$toml_two"
local merged_toml=$(cat "$toml_out")
assert_contains "$merged_toml" 'model = "gpt-5.4"'
_TEST_NAME="merge_toml_files replaces arrays with rightmost file"
assert_contains "$merged_toml" 'notify = ["override"]'
_TEST_NAME="merge_toml_files preserves nested scalar values"
assert_contains "$merged_toml" 'value = 1'
_TEST_NAME="merge_toml_files replaces nested arrays"
assert_contains "$merged_toml" 'items = ["b"]'
_TEST_NAME="merge_toml_files adds new nested tables"
assert_contains "$merged_toml" 'flag = true'
rm -f "$toml_one" "$toml_two" "$toml_out"

# --- _profile_read_brew_packages ---

_TEST_NAME="read_brew_packages parses brew lines"
local brewfile=$(mktemp)
cat > "$brewfile" << 'EOF'
brew "git"
brew "jq"
cask "firefox"
tap "homebrew/cask"
# comment line
EOF
local pkgs=$(_profile_read_brew_packages "$brewfile")
assert_contains "$pkgs" "brew:git"
assert_contains "$pkgs" "brew:jq"
assert_contains "$pkgs" "cask:firefox"
assert_contains "$pkgs" "tap:homebrew/cask"
rm -f "$brewfile"

_TEST_NAME="read_brew_packages ignores comments"
local brewfile2=$(mktemp)
echo '# brew "commented"' > "$brewfile2"
echo 'brew "real"' >> "$brewfile2"
local pkgs2=$(_profile_read_brew_packages "$brewfile2")
assert_not_contains "$pkgs2" "commented"
assert_contains "$pkgs2" "brew:real"
rm -f "$brewfile2"

# --- _profile_read_extensions ---

_TEST_NAME="read_extensions parses extension list"
local extfile=$(mktemp)
printf 'ext.one\next.two\n# comment\n  \next.three\n' > "$extfile"
local exts=$(_profile_read_extensions "$extfile")
assert_contains "$exts" "ext.one"
assert_contains "$exts" "ext.two"
assert_contains "$exts" "ext.three"
assert_not_contains "$exts" "comment"
rm -f "$extfile"

# --- _profile_dedup_dotfiles ---

_TEST_NAME="dedup removes duplicate lines"
cat > "$TEST_DOTFILES/.zshenv" << 'EOF'
# comment
export FOO=bar
export BAZ=qux
export FOO=bar
EOF
_profile_dedup_dotfiles > /dev/null 2>&1
local content=$(cat "$TEST_DOTFILES/.zshenv")
local foo_count=$(echo "$content" | grep -c "export FOO=bar")
assert_eq "1" "$foo_count"

_TEST_NAME="dedup preserves comments"
assert_contains "$content" "# comment"

_TEST_NAME="dedup preserves blank lines and structure keywords"
cat > "$TEST_DOTFILES/.zshrc" << 'EOF'
# top comment
if true; then
    echo hello
fi

done
esac
EOF
_profile_dedup_dotfiles > /dev/null 2>&1
local rc_content=$(cat "$TEST_DOTFILES/.zshrc")
assert_contains "$rc_content" "fi"
assert_contains "$rc_content" "done"
assert_contains "$rc_content" "esac"

_TEST_NAME="dedup preserves duplicate if-guards"
cat > "$TEST_DOTFILES/.zshenv" << 'ENVEOF'
if [[ "$(uname -s)" == "Darwin" ]]; then
    echo pnpm
fi
if [[ "$(uname -s)" == "Darwin" ]]; then
    echo jetbrains
fi
ENVEOF
_profile_dedup_dotfiles > /dev/null 2>&1
local env_content=$(cat "$TEST_DOTFILES/.zshenv")
local if_count=$(echo "$env_content" | grep -c 'if \[\[')
assert_eq "2" "$if_count"

# --- _profile_active ---

_TEST_NAME="active returns empty when no file"
rm -f "$PROFILE_ACTIVE_FILE"
local active=$(_profile_active)
assert_eq "" "$active"

_TEST_NAME="active returns content of active file"
echo "testprofile" > "$PROFILE_ACTIVE_FILE"
local active2=$(_profile_active)
assert_eq "testprofile" "$active2"

# --- _profile_target_paths ---

_TEST_NAME="target_paths includes gitconfig when git/config exists"
local targets=$(_profile_target_paths "testprofile")
assert_contains "$targets" ".gitconfig"

_TEST_NAME="target_paths includes claude settings when claude/settings.json exists"
assert_contains "$targets" ".claude/settings.json"

_TEST_NAME="target_paths includes CLAUDE.md when claude/CLAUDE.md exists"
echo "# test" > "$PROFILES_DIR/default/claude/CLAUDE.md"
local claude_md_targets=$(_profile_target_paths "default")
assert_contains "$claude_md_targets" ".claude/CLAUDE.md"

_TEST_NAME="target_paths includes codex AGENTS bridge when claude instructions exist"
assert_contains "$claude_md_targets" ".codex/AGENTS.md"

_TEST_NAME="target_paths includes system-prompt.md when claude/system-prompt.md exists"
echo "# test" > "$PROFILES_DIR/default/claude/system-prompt.md"
local sp_targets=$(_profile_target_paths "default")
assert_contains "$sp_targets" ".claude/system-prompt.md"

_TEST_NAME="target_paths includes codex config.toml when codex/config.toml exists"
assert_contains "$sp_targets" ".codex/config.toml"

_TEST_NAME="target_paths includes codex hooks.json when codex/hooks.json exists"
assert_contains "$sp_targets" ".codex/hooks.json"

_TEST_NAME="target_paths includes statusline.sh when claude/statusline.sh exists"
echo '#!/bin/bash' > "$PROFILES_DIR/default/claude/statusline.sh"
local statusline_targets=$(_profile_target_paths "default")
assert_contains "$statusline_targets" ".claude/statusline.sh"

_TEST_NAME="target_paths includes sync-plugins.sh when claude/sync-plugins.sh exists"
echo '#!/bin/bash' > "$PROFILES_DIR/default/claude/sync-plugins.sh"
local sync_plugin_targets=$(_profile_target_paths "default")
assert_contains "$sync_plugin_targets" ".claude/sync-plugins.sh"

_TEST_NAME="target_paths includes read-once hook when claude/read-once/hook.sh exists"
mkdir -p "$PROFILES_DIR/default/claude/read-once"
echo '#!/bin/bash' > "$PROFILES_DIR/default/claude/read-once/hook.sh"
local read_once_targets=$(_profile_target_paths "default")
assert_contains "$read_once_targets" ".claude/read-once/hook.sh"

_TEST_NAME="target_paths includes claude hooks when hook scripts exist"
mkdir -p "$PROFILES_DIR/default/claude/hooks"
echo '#!/bin/bash' > "$PROFILES_DIR/default/claude/hooks/my-hook.sh"
local hook_targets=$(_profile_target_paths "default")
assert_contains "$hook_targets" ".claude/hooks/my-hook.sh"

_TEST_NAME="target_paths includes claude skills when skill dirs exist"
mkdir -p "$PROFILES_DIR/default/claude/skills/my-skill"
echo "# skill" > "$PROFILES_DIR/default/claude/skills/my-skill/SKILL.md"
local skill_targets=$(_profile_target_paths "default")
assert_contains "$skill_targets" ".claude/skills/my-skill"

_TEST_NAME="target_paths includes codex shared skills when skill dirs exist"
assert_contains "$skill_targets" ".codex/skills"

_TEST_NAME="target_paths includes claude commands when command files exist"
mkdir -p "$PROFILES_DIR/default/claude/commands"
echo "# command" > "$PROFILES_DIR/default/claude/commands/test-command.md"
local command_targets=$(_profile_target_paths "default")
assert_contains "$command_targets" ".claude/commands/test-command.md"

_TEST_NAME="target_paths includes codex rules when codex/rules/default.rules exists"
assert_contains "$command_targets" ".codex/rules/default.rules"

_TEST_NAME="target_paths includes codex hooks when codex hook files exist"
assert_contains "$command_targets" ".codex/hooks/permission_bridge.py"

_TEST_NAME="target_paths includes codex agents when codex agent files exist"
assert_contains "$command_targets" ".codex/agents/explorer.toml"

rm -rf "$PROFILES_DIR/default/claude/hooks" "$PROFILES_DIR/default/claude/skills"
rm -rf "$PROFILES_DIR/default/claude/read-once" "$PROFILES_DIR/default/claude/commands"
rm -f "$PROFILES_DIR/default/claude/CLAUDE.md" "$PROFILES_DIR/default/claude/system-prompt.md"
rm -f "$PROFILES_DIR/default/claude/statusline.sh" "$PROFILES_DIR/default/claude/sync-plugins.sh"

_TEST_NAME="target_paths includes tmux.conf when tmux/tmux.conf exists"
mkdir -p "$PROFILES_DIR/default/tmux"
echo "set -g mouse on" > "$PROFILES_DIR/default/tmux/tmux.conf"
local tmux_targets=$(_profile_target_paths "default")
assert_contains "$tmux_targets" ".tmux.conf"

# --- _profile_read_all_brew_packages ---

_TEST_NAME="read_all_brew_packages reads from all profile directories"
mkdir -p "$PROFILES_DIR/otherprofile"
echo 'brew "biome"' > "$PROFILES_DIR/otherprofile/Brewfile"
echo 'cask "1password-cli"' >> "$PROFILES_DIR/otherprofile/Brewfile"
local all_pkgs=$(_profile_read_all_brew_packages)
assert_contains "$all_pkgs" "brew:git"
assert_contains "$all_pkgs" "brew:biome"
assert_contains "$all_pkgs" "cask:1password-cli"

_TEST_NAME="read_all_brew_packages skips directories without Brewfile"
mkdir -p "$PROFILES_DIR/noBrew"
local all_pkgs2=$(_profile_read_all_brew_packages)
assert_not_contains "$all_pkgs2" "noBrew"
rm -rf "$PROFILES_DIR/noBrew" "$PROFILES_DIR/otherprofile"

_test_summary
