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

_TEST_NAME="profile status detects current-checkpoint extension drift"
cat > "$TEST_HOME/mock-code" << 'EOF'
#!/bin/zsh
case "$1" in
    --list-extensions)
        printf '%s\n' ext.default ext.extra
        ;;
esac
EOF
chmod +x "$TEST_HOME/mock-code"
_profile_vscode_instances() {
    echo "MockCode|$TEST_HOME/.config/Code/User|$TEST_HOME/mock-code"
}
_test_apply_baseline
profile checkpoint >/dev/null 2>&1
local review_output=$(profile status 2>/dev/null)
assert_contains "$review_output" "Checkpoint: current"
assert_contains "$review_output" "Conflicts requiring review: 1"
assert_contains "$review_output" "VSCode extensions (MockCode)"
assert_not_contains "$review_output" "Everything is in sync."

_test_summary
