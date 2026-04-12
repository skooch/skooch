#!/usr/bin/env zsh
# Test three-way sync helper: direction detection, conflict handling

source "${0:A:h}/harness.sh"

# --- Setup: create test files for sync_config ---

sync_setup() {
    local local_file="$TEST_HOME/local_config.json"
    local source_file="$TEST_DOTFILES/sync_source.json"
    local expected_file=$(mktemp)

    echo '{"version": 1}' > "$source_file"
    echo '{"version": 1}' > "$local_file"
    cp "$source_file" "$expected_file"

    # Create snapshot so sync can detect direction
    printf '%s\t%s\n' "$local_file" "$(_platform_md5 "$local_file")" > "$PROFILE_STATE_DIR/snapshot-local"

    echo "$local_file" "$expected_file" "$source_file"
}

# --- Already in sync ---

_TEST_NAME="sync_config returns 0 when files match"
local files=($(sync_setup))
local local_f="${files[1]}" expected_f="${files[2]}" source_f="${files[3]}"
_profile_sync_config "test" "$local_f" "$expected_f" "$source_f"
assert_eq "0" "$?"
rm -f "$expected_f"

# --- Profile changed, local unchanged (profile -> local) ---

_TEST_NAME="sync_config detects profile -> local direction"
local files=($(sync_setup))
local local_f="${files[1]}" expected_f="${files[2]}" source_f="${files[3]}"
echo '{"version": 2}' > "$source_f"
cp "$source_f" "$expected_f"
local output=$(echo "y" | _profile_sync_config "test" "$local_f" "$expected_f" "$source_f" 2>&1)
assert_contains "$output" "profile -> local"

_TEST_NAME="sync_config profile->local updates local file"
local local_content=$(cat "$local_f")
assert_contains "$local_content" '"version": 2'
rm -f "$expected_f"

# --- Local changed, profile unchanged (local -> profile) ---

_TEST_NAME="sync_config detects local -> profile direction"
local files=($(sync_setup))
local local_f="${files[1]}" expected_f="${files[2]}" source_f="${files[3]}"
echo '{"version": 3, "local_edit": true}' > "$local_f"
local output=$(echo "y" | _profile_sync_config "test" "$local_f" "$expected_f" "$source_f" 2>&1)
assert_contains "$output" "local -> profile"
rm -f "$expected_f"

# --- No local file (create) ---

_TEST_NAME="sync_config creates missing local file"
local source_f="$TEST_DOTFILES/sync_source.json"
echo '{"fresh": true}' > "$source_f"
local expected_f=$(mktemp)
cp "$source_f" "$expected_f"
local new_local="$TEST_HOME/new_config.json"
rm -f "$new_local"
local output=$(_profile_sync_config "test" "$new_local" "$expected_f" "$source_f" 2>&1)
assert_contains "$output" "created"
assert_file_exists "$new_local"
rm -f "$expected_f" "$new_local"

# --- No snapshot (defaults to profile -> local) ---

_TEST_NAME="sync_config defaults to profile->local when no snapshot"
rm -f "$PROFILE_STATE_DIR/snapshot-local"
local source_f="$TEST_DOTFILES/sync_source.json"
echo '{"source": true}' > "$source_f"
local expected_f=$(mktemp)
cp "$source_f" "$expected_f"
local local_f="$TEST_HOME/no_snap.json"
echo '{"old": true}' > "$local_f"
local output=$(echo "y" | _profile_sync_config "test" "$local_f" "$expected_f" "$source_f" 2>&1)
assert_contains "$output" "profile -> local"
rm -f "$expected_f" "$local_f"

# --- Both changed (conflict) — choose apply profile ---

_TEST_NAME="sync_config detects conflict when both changed"
local files=($(sync_setup))
local local_f="${files[1]}" expected_f="${files[2]}" source_f="${files[3]}"
# Change both sides
echo '{"version": 10, "source_edit": true}' > "$source_f"
cp "$source_f" "$expected_f"
echo '{"version": 20, "local_edit": true}' > "$local_f"
# Choose option 2 (apply profile)
local output=$(echo "2" | _profile_sync_config "test" "$local_f" "$expected_f" "$source_f" 2>&1)
assert_contains "$output" "CONFLICT"

_TEST_NAME="sync_config conflict option 2 applies profile version"
local local_content=$(cat "$local_f")
assert_contains "$local_content" "source_edit"
rm -f "$expected_f"

# --- Conflict with option 1 (keep local) ---

_TEST_NAME="sync_config conflict option 1 keeps local"
local files=($(sync_setup))
local local_f="${files[1]}" expected_f="${files[2]}" source_f="${files[3]}"
echo '{"version": 10}' > "$source_f"
cp "$source_f" "$expected_f"
echo '{"version": 20, "my_local": true}' > "$local_f"
local output=$(echo "1" | _profile_sync_config "test" "$local_f" "$expected_f" "$source_f" 2>&1)
assert_contains "$output" "CONFLICT"

_TEST_NAME="sync_config conflict option 1 updates profile source"
local src_content=$(cat "$source_f")
assert_contains "$src_content" "my_local"
rm -f "$expected_f"

# --- Conflict without input must fail safe ---

_TEST_NAME="sync_config conflict without input returns review-required"
local files=($(sync_setup))
local local_f="${files[1]}" expected_f="${files[2]}" source_f="${files[3]}"
echo '{"version": 10}' > "$source_f"
cp "$source_f" "$expected_f"
echo '{"version": 20, "local_edit": true}' > "$local_f"
local empty_input=$(mktemp)
local conflict_output=$(mktemp)
_PROFILE_INPUT="$empty_input"
_profile_sync_config "test" "$local_f" "$expected_f" "$source_f" > "$conflict_output" 2>&1
local rc=$?
rm -f "$empty_input"
assert_eq "2" "$rc"
rm -f "$conflict_output"

_TEST_NAME="sync_config conflict without input leaves profile source unchanged"
local src_content=$(cat "$source_f")
assert_not_contains "$src_content" "local_edit"
rm -f "$expected_f"
_PROFILE_INPUT=/dev/stdin

# --- Return values ---

_TEST_NAME="sync_config returns 0 when already in sync"
local files=($(sync_setup))
local local_f="${files[1]}" expected_f="${files[2]}" source_f="${files[3]}"
_profile_sync_config "test" "$local_f" "$expected_f" "$source_f" > /dev/null 2>&1
assert_eq "0" "$?"
rm -f "$expected_f"

_TEST_NAME="sync_config returns 1 when changes applied"
local files=($(sync_setup))
local local_f="${files[1]}" expected_f="${files[2]}" source_f="${files[3]}"
echo '{"changed": true}' > "$source_f"
cp "$source_f" "$expected_f"
echo "y" | _profile_sync_config "test" "$local_f" "$expected_f" "$source_f" > /dev/null 2>&1
assert_eq "1" "$?"
rm -f "$expected_f"

# --- _profile_sync_tmux ---

HOME="$TEST_HOME"
_TEST_NAME="sync_tmux delegates to sync_config with winning source"
mkdir -p "$PROFILES_DIR/default/tmux"
echo "set -g mouse on" > "$PROFILES_DIR/default/tmux/tmux.conf"
echo "set -g mouse on" > "$TEST_HOME/.tmux.conf"
printf '%s\t%s\n' "$TEST_HOME/.tmux.conf" "$(_platform_md5 "$TEST_HOME/.tmux.conf")" >> "$PROFILE_STATE_DIR/snapshot-local"
_profile_sync_tmux "default" > /dev/null 2>&1
assert_eq "0" "$?"

# --- _profile_sync_claude ---

_TEST_NAME="sync_claude symlinks statusline.sh and read-once hook"
echo '#!/bin/bash' > "$PROFILES_DIR/default/claude/statusline.sh"
mkdir -p "$PROFILES_DIR/default/claude/read-once"
echo '#!/bin/bash' > "$PROFILES_DIR/default/claude/read-once/hook.sh"
echo "old statusline" > "$TEST_HOME/.claude/statusline.sh"
mkdir -p "$TEST_HOME/.claude/read-once"
echo "old hook" > "$TEST_HOME/.claude/read-once/hook.sh"
_profile_sync_claude "default" > /dev/null 2>&1
assert_symlink "$TEST_HOME/.claude/statusline.sh" "$PROFILES_DIR/default/claude/statusline.sh"

_TEST_NAME="sync_claude symlinks nested read-once hook"
assert_symlink "$TEST_HOME/.claude/read-once/hook.sh" "$PROFILES_DIR/default/claude/read-once/hook.sh"
rm -f "$PROFILES_DIR/default/claude/statusline.sh"
rm -rf "$PROFILES_DIR/default/claude/read-once"

# --- _profile_sync_mise ---

mise() {
    case "$1" in
        ls)
            echo '{"node":["22.0.0"],"python":["3.12.0"]}'
            ;;
        install)
            echo "MOCK_MISE_INSTALL"
            ;;
        uninstall)
            echo "MOCK_MISE_UNINSTALL: $*"
            ;;
    esac
    return 0
}

_TEST_NAME="sync_mise symlinks single-source config.toml"
cat > "$PROFILES_DIR/default/mise/config.toml" << 'EOF'
[settings]
trusted_config_paths = ["~/projects", "~/blinq"]

[tools]
node = "lts"
EOF
mkdir -p "$TEST_HOME/.config/mise"
echo '[tools]
node = "lts"' > "$TEST_HOME/.config/mise/config.toml"
printf '%s\t%s\n' "$TEST_HOME/.config/mise/config.toml" "$(_platform_md5 "$TEST_HOME/.config/mise/config.toml")" >> "$PROFILE_STATE_DIR/snapshot-local"
_profile_sync_mise "default" > /dev/null 2>&1
assert_symlink "$TEST_HOME/.config/mise/config.toml" "$PROFILES_DIR/default/mise/config.toml"

_TEST_NAME="sync_mise creates merged config.toml for multiple sources"
cat > "$PROFILES_DIR/testprofile/mise/config.toml" << 'EOF'
[settings]
not_found_auto_install = true

[tools]
python = "3.12"
EOF
rm -f "$TEST_HOME/.config/mise/config.toml"
_profile_sync_mise "testprofile" > /dev/null 2>&1
assert_not_symlink "$TEST_HOME/.config/mise/config.toml" "multiple mise sources should merge into a regular file"
local synced_mise_config=$(cat "$TEST_HOME/.config/mise/config.toml")
assert_contains "$synced_mise_config" 'trusted_config_paths = ["~/projects", "~/blinq"]'
_TEST_NAME="sync_mise merged config.toml includes later-profile tools"
assert_contains "$synced_mise_config" 'python = "3.12"'

# --- _profile_sync_codex ---

_TEST_NAME="sync_codex symlinks single-source config.toml"
rm -f "$PROFILES_DIR/testprofile/codex/config.toml"
rm -f "$TEST_HOME/.codex/config.toml"
_profile_sync_codex "default" > /dev/null 2>&1
assert_symlink "$TEST_HOME/.codex/config.toml" "$PROFILES_DIR/default/codex/config.toml"
cat > "$PROFILES_DIR/testprofile/codex/config.toml" << 'EOF'
approval_policy = "on-request"

[features]
shell_snapshot = true
EOF

_TEST_NAME="sync_codex creates merged config.toml for multiple sources"
rm -f "$TEST_HOME/.codex/config.toml"
_profile_sync_codex "testprofile" > /dev/null 2>&1
assert_not_symlink "$TEST_HOME/.codex/config.toml"
local synced_codex_config=$(cat "$TEST_HOME/.codex/config.toml")
assert_contains "$synced_codex_config" 'model = "gpt-5.4"'
_TEST_NAME="sync_codex merged config.toml includes nested merged values"
assert_contains "$synced_codex_config" 'shell_snapshot = true'

_TEST_NAME="sync_codex creates merged hooks.json for multiple sources"
rm -f "$TEST_HOME/.codex/hooks.json"
_profile_sync_codex "testprofile" > /dev/null 2>&1
assert_not_symlink "$TEST_HOME/.codex/hooks.json"
local synced_codex_hooks=$(cat "$TEST_HOME/.codex/hooks.json")
assert_contains "$synced_codex_hooks" "SessionStart"
_TEST_NAME="sync_codex merged hooks.json includes later profile hook entries"
assert_contains "$synced_codex_hooks" "Stop"

_TEST_NAME="sync_codex syncs local rules edits back to winning profile"
ln -sf "$PROFILES_DIR/default/codex/config.toml" "$TEST_HOME/.codex/config.toml"
ln -sf "$PROFILES_DIR/default/codex/hooks.json" "$TEST_HOME/.codex/hooks.json"
mkdir -p "$TEST_HOME/.codex/rules"
echo 'prefix_rule(pattern = ["cat"], decision = "allow")' > "$TEST_HOME/.codex/rules/default.rules"
printf '%s\t%s\n' "$TEST_HOME/.codex/rules/default.rules" "$(_platform_md5 "$PROFILES_DIR/default/codex/rules/default.rules")" >> "$PROFILE_STATE_DIR/snapshot-local"
echo "y" | _profile_sync_codex "default" > /dev/null 2>&1
local synced_rules_source=$(cat "$PROFILES_DIR/default/codex/rules/default.rules")
assert_contains "$synced_rules_source" 'pattern = ["cat"]'

_TEST_NAME="sync_codex enforces codex hook symlinks"
rm -f "$TEST_HOME/.codex/config.toml" "$TEST_HOME/.codex/hooks.json"
mkdir -p "$PROFILES_DIR/testprofile/codex/hooks" "$TEST_HOME/.codex/hooks"
echo '#!/usr/bin/env python3' > "$PROFILES_DIR/testprofile/codex/hooks/extra.py"
echo "old hook" > "$TEST_HOME/.codex/hooks/permission_bridge.py"
echo "old launcher" > "$TEST_HOME/.codex/hooks/run-with-python3"
echo "old extra" > "$TEST_HOME/.codex/hooks/extra.py"
_profile_sync_codex "testprofile" > /dev/null 2>&1
assert_symlink "$TEST_HOME/.codex/hooks/permission_bridge.py" "$PROFILES_DIR/default/codex/hooks/permission_bridge.py"
_TEST_NAME="sync_codex enforces shared python launcher symlink"
assert_symlink "$TEST_HOME/.codex/hooks/run-with-python3" "$PROFILES_DIR/default/codex/hooks/run-with-python3"
_TEST_NAME="sync_codex enforces unioned codex agent symlinks"
mkdir -p "$PROFILES_DIR/testprofile/codex/agents" "$TEST_HOME/.codex/agents"
echo 'name = "worker"' > "$PROFILES_DIR/testprofile/codex/agents/worker.toml"
echo "old agent" > "$TEST_HOME/.codex/agents/worker.toml"
_profile_sync_codex "testprofile" > /dev/null 2>&1
assert_symlink "$TEST_HOME/.codex/agents/worker.toml" "$PROFILES_DIR/testprofile/codex/agents/worker.toml"

_TEST_NAME="sync_skills links shared skill to both agents"
mkdir -p "$PROFILES_DIR/default/skills/shared/layout-check"
echo "# Layout check" > "$PROFILES_DIR/default/skills/shared/layout-check/SKILL.md"
rm -rf "$TEST_HOME/.codex/skills/layout-check" "$TEST_HOME/.claude/skills/layout-check"
_profile_sync_skills "default" > /dev/null 2>&1
assert_symlink "$TEST_HOME/.claude/skills/layout-check" "$PROFILES_DIR/default/skills/shared/layout-check"

# --- Reverse skill sync (orphan ingestion) ---

_TEST_NAME="sync_skills ingests orphan skill from claude"
rm -rf "$PROFILES_DIR/default/skills/shared/orphan-skill"
mkdir -p "$TEST_HOME/.claude/skills/orphan-skill"
cat > "$TEST_HOME/.claude/skills/orphan-skill/SKILL.md" <<'SKILL'
---
name: orphan-skill
description: >
  A test orphan skill for reverse sync
---
# Orphan Skill
SKILL
rm -rf "$TEST_HOME/.codex/skills/orphan-skill"
_profile_sync_skills "default" > /dev/null 2>&1
if [[ -d "$PROFILES_DIR/default/skills/shared/orphan-skill" ]]; then
    pass
else
    fail "orphan skill was not ingested into profiles"
fi

_TEST_NAME="sync_skills scaffolds openai.yaml for ingested orphan"
if [[ -f "$PROFILES_DIR/default/skills/shared/orphan-skill/agents/openai.yaml" ]]; then
    pass
else
    fail "agents/openai.yaml was not scaffolded"
fi

_TEST_NAME="sync_skills replaces orphan with symlink after ingestion"
assert_symlink "$TEST_HOME/.claude/skills/orphan-skill" "$PROFILES_DIR/default/skills/shared/orphan-skill"

_TEST_NAME="sync_skills routes ingested orphan to codex too"
assert_symlink "$TEST_HOME/.codex/skills/orphan-skill" "$PROFILES_DIR/default/skills/shared/orphan-skill"

_TEST_NAME="sync_skills skips orphan without SKILL.md"
rm -rf "$PROFILES_DIR/default/skills/shared/junk-dir"
mkdir -p "$TEST_HOME/.claude/skills/junk-dir"
echo "not a skill" > "$TEST_HOME/.claude/skills/junk-dir/README.md"
_profile_sync_skills "default" > /dev/null 2>&1
if [[ ! -d "$PROFILES_DIR/default/skills/shared/junk-dir" ]]; then
    pass
else
    fail "junk dir without SKILL.md should not be ingested"
fi
rm -rf "$TEST_HOME/.claude/skills/junk-dir"

_TEST_NAME="sync_skills skips orphan that already exists in profiles"
mkdir -p "$PROFILES_DIR/default/skills/shared/existing-skill"
echo "# existing" > "$PROFILES_DIR/default/skills/shared/existing-skill/SKILL.md"
mkdir -p "$TEST_HOME/.claude/skills/existing-skill"
echo "# local copy" > "$TEST_HOME/.claude/skills/existing-skill/SKILL.md"
local existing_before=$(<"$PROFILES_DIR/default/skills/shared/existing-skill/SKILL.md")
_profile_sync_skills "default" > /dev/null 2>&1
local existing_after=$(<"$PROFILES_DIR/default/skills/shared/existing-skill/SKILL.md")
if [[ "$existing_before" == "$existing_after" ]]; then
    pass
else
    fail "existing profile skill should not be overwritten by orphan"
fi

_TEST_NAME="apply_skills ingests orphans at apply time"
rm -rf "$PROFILES_DIR/default/skills/shared/apply-orphan"
mkdir -p "$TEST_HOME/.claude/skills/apply-orphan"
echo -e "---\nname: apply-orphan\n---\n# test" > "$TEST_HOME/.claude/skills/apply-orphan/SKILL.md"
_profile_apply_skills "default" > /dev/null 2>&1
if [[ -d "$PROFILES_DIR/default/skills/shared/apply-orphan" ]]; then
    pass
else
    fail "apply mode should ingest orphans"
fi
rm -rf "$TEST_HOME/.claude/skills/apply-orphan" "$PROFILES_DIR/default/skills/shared/apply-orphan"

# Clean up reverse sync test artifacts
rm -rf "$PROFILES_DIR/default/skills/shared/orphan-skill" "$PROFILES_DIR/default/skills/shared/existing-skill"

_TEST_NAME="sync_codex restores AGENTS bridge"
echo "# Instructions" > "$PROFILES_DIR/default/claude/CLAUDE.md"
_profile_apply_claude "default" > /dev/null 2>&1
rm -f "$TEST_HOME/.codex/config.toml" "$TEST_HOME/.codex/hooks.json"
echo "old agents" > "$TEST_HOME/.codex/AGENTS.md"
_profile_sync_codex "default" > /dev/null 2>&1
assert_symlink "$TEST_HOME/.codex/AGENTS.md" "$TEST_HOME/.claude/CLAUDE.md"

# --- Regression: prompts must work inside while-read loops (stdin redirected) ---

_TEST_NAME="sync_config conflict prompt works inside while-read loop"
local files=($(sync_setup))
local local_f="${files[1]}" expected_f="${files[2]}" source_f="${files[3]}"
echo '{"version": 99}' > "$source_f"
cp "$source_f" "$expected_f"
echo '{"version": 100, "local_conflict": true}' > "$local_f"
# Simulate calling _profile_sync_config from inside a while-read loop (like VSCode settings sync does).
# Before the fix, the read for conflict choice consumed from the here-string instead of user input.
local instances="Label1|/tmp/dir1|/tmp/cli1"
local loop_tmpout=$(mktemp)
local loop_input=$(mktemp)
echo "2" > "$loop_input"
_PROFILE_INPUT="$loop_input"
while IFS='|' read -r _label _dir _cli; do
    [[ -z "$_label" ]] && continue
    _profile_sync_config "test" "$local_f" "$expected_f" "$source_f" > "$loop_tmpout" 2>&1
done <<< "$instances"
rm -f "$loop_input"
local loop_output=$(cat "$loop_tmpout")
rm -f "$loop_tmpout"
assert_contains "$loop_output" "CONFLICT"

_TEST_NAME="sync_config conflict choice applied correctly inside while-read loop"
local local_content=$(cat "$local_f")
assert_contains "$local_content" '"version": 99'
rm -f "$expected_f"

_TEST_NAME="sync_config profile->local prompt works inside while-read loop"
local files=($(sync_setup))
local local_f="${files[1]}" expected_f="${files[2]}" source_f="${files[3]}"
echo '{"version": 50}' > "$source_f"
cp "$source_f" "$expected_f"
local loop_tmpout=$(mktemp)
local loop_input=$(mktemp)
echo "y" > "$loop_input"
_PROFILE_INPUT="$loop_input"
while IFS='|' read -r _label _dir _cli; do
    [[ -z "$_label" ]] && continue
    _profile_sync_config "test" "$local_f" "$expected_f" "$source_f" > "$loop_tmpout" 2>&1
done <<< "$instances"
rm -f "$loop_input"
local loop_output=$(cat "$loop_tmpout")
rm -f "$loop_tmpout"
assert_contains "$loop_output" "profile -> local"

_TEST_NAME="sync_config profile->local applied correctly inside while-read loop"
local local_content=$(cat "$local_f")
assert_contains "$local_content" '"version": 50'
rm -f "$expected_f"

# --- profile sync must not checkpoint unresolved work ---

_TEST_NAME="profile sync keeps checkpoint stale when review is still required"
HOME="$TEST_HOME"
brew() {
    case "$1" in
        leaves)
            echo "git"
            ;;
        list)
            [[ "$2" == "--cask" ]] && return 0
            ;;
    esac
    return 0
}
mise() {
    case "$1" in
        ls)
            echo '{"node":["22.0.0"],"python":["3.12.0"]}'
            ;;
        install|uninstall)
            return 0
            ;;
    esac
    return 0
}
_profile_vscode_instances() {
    return 0
}

_test_write_managed() {
    local profiles="$1"
    local -a managed=()
    local managed_path=""
    while IFS= read -r managed_path; do
        [[ -n "$managed_path" ]] && managed+=("$managed_path")
    done < <(_profile_managed_paths_for_record "$profiles")
    _profile_write_managed "${managed[@]}"
}

echo "testprofile" > "$PROFILE_ACTIVE_FILE"
_profile_apply_codex "testprofile" >/dev/null 2>&1
_test_write_managed "testprofile"
_profile_take_snapshot "testprofile"
local checkpoint_before=$(cat "$PROFILE_CHECKPOINT_FILE")
cat > "$PROFILES_DIR/default/codex/config.toml" << 'EOF'
model = "gpt-5.4-mini"

[features]
codex_hooks = true
EOF
cat > "$TEST_HOME/.codex/config.toml" << 'EOF'
model = "gpt-5.4"

[features]
codex_hooks = true
local_override = true
EOF
local empty_input=$(mktemp)
local sync_tmpout=$(mktemp)
_PROFILE_INPUT="$empty_input"
profile sync > "$sync_tmpout" 2>&1
local sync_rc=$?
local sync_output=$(cat "$sync_tmpout")
rm -f "$empty_input"
rm -f "$sync_tmpout"
assert_eq "2" "$sync_rc"

_TEST_NAME="profile sync does not update checkpoint when review is still required"
local checkpoint_after=$(cat "$PROFILE_CHECKPOINT_FILE")
assert_eq "$checkpoint_before" "$checkpoint_after"

_TEST_NAME="profile sync reports skipped checkpoint on unresolved review"
assert_contains "$sync_output" "Checkpoint not updated"
_PROFILE_INPUT=/dev/stdin

_TEST_NAME="profile sync does not checkpoint blocked derived symlink repairs"
HOME="$TEST_HOME"
brew() {
    case "$1" in
        leaves)
            echo "git"
            ;;
        list)
            [[ "$2" == "--cask" ]] && return 0
            ;;
    esac
    return 0
}
mise() {
    case "$1" in
        ls)
            echo '{"node":["22.0.0"]}'
            ;;
    esac
    return 0
}
_profile_vscode_instances() {
    return 0
}
echo "default" > "$PROFILE_ACTIVE_FILE"
echo "# Claude instructions" > "$PROFILES_DIR/default/claude/CLAUDE.md"
_profile_apply_claude "default" >/dev/null 2>&1
_profile_apply_codex "default" >/dev/null 2>&1
_profile_apply_mise "default" >/dev/null 2>&1
_test_write_managed "default"
_profile_take_snapshot "default"
local checkpoint_before_blocked=$(cat "$PROFILE_CHECKPOINT_FILE")
rm -f "$TEST_HOME/.codex/AGENTS.md"
mkdir -p "$TEST_HOME/.codex/AGENTS.md"
echo "blocked" > "$TEST_HOME/.codex/AGENTS.md/file.txt"
local blocked_tmpout=$(mktemp)
profile sync > "$blocked_tmpout" 2>&1
local blocked_rc=$?
local blocked_sync_output=$(cat "$blocked_tmpout")
rm -f "$blocked_tmpout"
assert_eq "2" "$blocked_rc"

_TEST_NAME="profile sync keeps checkpoint unchanged when derived symlink repair is blocked"
local checkpoint_after_blocked=$(cat "$PROFILE_CHECKPOINT_FILE")
assert_eq "$checkpoint_before_blocked" "$checkpoint_after_blocked"

_TEST_NAME="profile sync reports blocked derived symlink repair"
assert_contains "$blocked_sync_output" "AGENTS.md: skipped conflicting directory"
assert_contains "$blocked_sync_output" "Checkpoint not updated"

_TEST_NAME="profile sync prunes stale managed links after profile source removal"
HOME="$TEST_HOME"
rm -rf "$TEST_HOME/.codex/AGENTS.md"
echo "default" > "$PROFILE_ACTIVE_FILE"
_profile_apply_codex "default" >/dev/null 2>&1
_profile_apply_mise "default" >/dev/null 2>&1
_test_write_managed "default"
_profile_take_snapshot "default"
rm -f "$PROFILES_DIR/default/codex/hooks/permission_bridge.py"
local prune_tmpout=$(mktemp)
profile sync > "$prune_tmpout" 2>&1
local prune_rc=$?
local prune_output=$(cat "$prune_tmpout")
rm -f "$prune_tmpout"
assert_eq "1" "$prune_rc"

_TEST_NAME="profile sync removes stale managed hook symlink"
if [[ -e "$TEST_HOME/.codex/hooks/permission_bridge.py" || -L "$TEST_HOME/.codex/hooks/permission_bridge.py" ]]; then
    fail "stale hook symlink should be removed"
else
    pass
fi

_TEST_NAME="profile sync reports stale managed link pruning"
assert_contains "$prune_output" "Removed stale managed link: ~/.codex/hooks/permission_bridge.py"

_TEST_NAME="profile use surfaces blocked stale managed cleanup"
HOME="$TEST_HOME"
_profile_apply_cbm() {
    return 0
}
_profile_apply_git_cache() {
    return 0
}
_profile_vscode_instances() {
    return 0
}
echo "default" > "$PROFILE_ACTIVE_FILE"
echo "# Claude instructions" > "$PROFILES_DIR/default/claude/CLAUDE.md"
echo '#!/usr/bin/env python3' > "$PROFILES_DIR/default/codex/hooks/permission_bridge.py"
_profile_apply_claude "default" >/dev/null 2>&1
_profile_apply_codex "default" >/dev/null 2>&1
_profile_apply_mise "default" >/dev/null 2>&1
_test_write_managed "default"
_profile_take_snapshot "default"
local use_checkpoint_before=$(cat "$PROFILE_CHECKPOINT_FILE")
rm -f "$PROFILES_DIR/default/codex/hooks/permission_bridge.py"
rm -f "$TEST_HOME/.codex/hooks/permission_bridge.py"
mkdir -p "$TEST_HOME/.codex/hooks/permission_bridge.py"
echo "blocked" > "$TEST_HOME/.codex/hooks/permission_bridge.py/file.txt"
local use_tmpout=$(mktemp)
profile use default > "$use_tmpout" 2>&1
local use_rc=$?
local use_output=$(cat "$use_tmpout")
rm -f "$use_tmpout"
assert_eq "2" "$use_rc"

_TEST_NAME="profile use reports blocked stale managed cleanup"
assert_contains "$use_output" "Stale managed target requires review: ~/.codex/hooks/permission_bridge.py"
assert_contains "$use_output" "Checkpoint not updated because profile switch still requires review."

_TEST_NAME="profile use does not update checkpoint when stale cleanup is blocked"
local use_checkpoint_after=$(cat "$PROFILE_CHECKPOINT_FILE")
assert_eq "$use_checkpoint_before" "$use_checkpoint_after"

# Restore default
_PROFILE_INPUT=/dev/stdin

_test_summary
