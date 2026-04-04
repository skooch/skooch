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

# Restore default
_PROFILE_INPUT=/dev/stdin

_test_summary
