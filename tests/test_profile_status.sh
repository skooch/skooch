#!/usr/bin/env zsh
# Test profile status and checkpoint messaging

source "${0:A:h}/harness.sh"

HOME="$TEST_HOME"

echo "default" > "$PROFILE_ACTIVE_FILE"

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

_test_apply_baseline() {
    echo "default" > "$PROFILE_ACTIVE_FILE"
    _profile_apply_claude "default" >/dev/null 2>&1
    _profile_apply_codex "default" >/dev/null 2>&1
    _profile_apply_mise "default" >/dev/null 2>&1
    _profile_apply_git "default" >/dev/null 2>&1
    local -a managed=()
    local managed_path=""
    while IFS= read -r managed_path; do
        [[ -n "$managed_path" ]] && managed+=("$managed_path")
    done < <(_profile_managed_paths_for_record "default")
    _profile_write_managed "${managed[@]}"
}

_test_apply_baseline

_TEST_NAME="profile status reports missing checkpoint"
rm -f "$PROFILE_CHECKPOINT_FILE"
local missing_output=$(profile status 2>/dev/null)
assert_contains "$missing_output" "No checkpoint found"

_TEST_NAME="profile checkpoint creates checkpoint file"
local checkpoint_output=$(profile checkpoint 2>/dev/null)
assert_contains "$checkpoint_output" "Checkpoint updated"
assert_file_exists "$PROFILE_CHECKPOINT_FILE"

_TEST_NAME="profile checkpoint blocks unsafe remote state"
local remote_block_log=$(mktemp)
(
    _profile_check_remote() {
        _PROFILE_REMOTE_STATE="behind"
        _PROFILE_REMOTE_MESSAGE="Dotfiles repo is 1 commit(s) behind upstream."
        return 0
    }
    profile checkpoint
) >"$remote_block_log" 2>&1
local remote_block_rc=$?
local remote_block_output=$(cat "$remote_block_log")
rm -f "$remote_block_log"
assert_eq "1" "$remote_block_rc"
assert_contains "$remote_block_output" "Remote: Dotfiles repo is 1 commit(s) behind upstream."
assert_contains "$remote_block_output" "Pull or reconcile upstream changes before running 'profile checkpoint'."

_TEST_NAME="profile status distinguishes stale checkpoint from reconcile work"
ln -sf "$PROFILES_DIR/default/codex/config.toml" "$TEST_HOME/.codex/config.toml"
echo 'model = "gpt-5.4-mini"' > "$PROFILES_DIR/default/codex/config.toml"
local stale_output=$(profile status 2>/dev/null)
assert_contains "$stale_output" "Checkpoint: stale"
assert_contains "$stale_output" "Managed targets already match the canonical profile state"
assert_contains "$stale_output" "profile checkpoint"

_TEST_NAME="profile status reports safe sync actions separately"
cat > "$PROFILES_DIR/default/vscode/settings.json" << 'EOF'
{"editor.fontSize": 18}
EOF
mkdir -p "$TEST_HOME/.config/Code/User"
cat > "$TEST_HOME/.config/Code/User/settings.json" << 'EOF'
{"editor.fontSize": 14}
EOF
cat > "$TEST_HOME/.config/Code/User/keybindings.json" << 'EOF'
[]
EOF
cat > "$TEST_HOME/mock-code" << 'EOF'
#!/bin/zsh
case "$1" in
    --list-extensions)
        printf '%s\n' ext.default
        ;;
esac
EOF
chmod +x "$TEST_HOME/mock-code"
_profile_vscode_instances() {
    echo "MockCode|$TEST_HOME/.config/Code/User|$TEST_HOME/mock-code"
}
_test_apply_baseline
cat > "$PROFILES_DIR/default/vscode/settings.json" << 'EOF'
{"editor.fontSize": 20}
EOF
local safe_output=$(profile status 2>/dev/null)
assert_contains "$safe_output" "Safe sync actions: 1"
assert_contains "$safe_output" "VSCode settings (MockCode): profile changes can be applied automatically"
assert_contains "$safe_output" "Run 'profile sync' to apply the safe changes above."

_TEST_NAME="profile checkpoint blocks unresolved managed drift"
local checkpoint_drift_output
checkpoint_drift_output=$(profile checkpoint 2>/dev/null)
local checkpoint_drift_rc=$?
assert_eq "1" "$checkpoint_drift_rc"
assert_contains "$checkpoint_drift_output" "Checkpoint would bless unresolved managed drift."
assert_contains "$checkpoint_drift_output" "Run 'profile sync' to apply or record the changes above before checkpointing."

cat > "$PROFILES_DIR/default/codex/config.toml" << 'EOF'
model = "gpt-5.4"

[features]
codex_hooks = true
EOF

_TEST_NAME="profile status detects drift on union-managed and derived symlink targets"
echo "# Claude instructions" > "$PROFILES_DIR/default/claude/CLAUDE.md"
_profile_vscode_instances() {
    return 0
}
_test_apply_baseline
profile checkpoint >/dev/null 2>&1
rm -f "$TEST_HOME/.codex/hooks/permission_bridge.py" "$TEST_HOME/.codex/AGENTS.md"
echo "tampered hook" > "$TEST_HOME/.codex/hooks/permission_bridge.py"
echo "tampered agents" > "$TEST_HOME/.codex/AGENTS.md"
local link_drift_output=$(profile status 2>/dev/null)
assert_contains "$link_drift_output" "Checkpoint: stale"
assert_contains "$link_drift_output" "Codex hooks (permission_bridge.py)"
assert_contains "$link_drift_output" "AGENTS.md bridge"
assert_not_contains "$link_drift_output" "Everything is in sync."

_TEST_NAME="profile status reports blocked link repair for conflicting managed directories"
echo "# Claude instructions" > "$PROFILES_DIR/default/claude/CLAUDE.md"
_test_apply_baseline
profile checkpoint >/dev/null 2>&1
rm -f "$TEST_HOME/.codex/AGENTS.md"
mkdir -p "$TEST_HOME/.codex/AGENTS.md"
echo "blocked" > "$TEST_HOME/.codex/AGENTS.md/file.txt"
local blocked_output=$(profile status 2>/dev/null)
assert_contains "$blocked_output" "AGENTS.md bridge: conflicting directory blocks automatic link repair"
assert_not_contains "$blocked_output" "Run 'profile sync' to apply the safe changes above."

_TEST_NAME="profile status detects current-checkpoint extension drift"
cat > "$TEST_HOME/mock-code" << 'EOF'
#!/bin/zsh
case "$1" in
    --list-extensions)
        printf '%s\n' ext.default
        ;;
esac
EOF
chmod +x "$TEST_HOME/mock-code"
_profile_vscode_instances() {
    echo "MockCode|$TEST_HOME/.config/Code/User|$TEST_HOME/mock-code"
}
cat > "$PROFILES_DIR/default/vscode/settings.json" << 'EOF'
{"editor.fontSize": 14}
EOF
rm -rf "$TEST_HOME/.codex/AGENTS.md"
rm -f "$TEST_HOME/.codex/hooks/permission_bridge.py"
_test_apply_baseline
profile checkpoint >/dev/null 2>&1
cat > "$TEST_HOME/mock-code" << 'EOF'
#!/bin/zsh
case "$1" in
    --list-extensions)
        printf '%s\n' ext.default ext.extra
        ;;
esac
EOF
chmod +x "$TEST_HOME/mock-code"
local review_output=$(profile status 2>/dev/null)
assert_contains "$review_output" "Checkpoint: current"
assert_contains "$review_output" "Tool inventory has informational differences"
assert_contains "$review_output" "VSCode extensions (MockCode)"
assert_not_contains "$review_output" "Everything is in sync."

_TEST_NAME="profile status reports stale managed links after profile source removal"
_profile_vscode_instances() {
    return 0
}
_test_apply_baseline
profile checkpoint >/dev/null 2>&1
rm -f "$PROFILES_DIR/default/codex/hooks/permission_bridge.py"
local stale_managed_output=$(profile status 2>/dev/null)
assert_contains "$stale_managed_output" "Stale managed target (~/.codex/hooks/permission_bridge.py)"
assert_not_contains "$stale_managed_output" "Everything is in sync."

_test_summary
