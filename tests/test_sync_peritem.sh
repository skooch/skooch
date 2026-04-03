#!/usr/bin/env zsh
# Test per-item sync flows for brew, vscode, and mise

source "${0:A:h}/harness.sh"

# --- Brew per-item sync tests ---
# Mock brew commands for testing

brew() {
    case "$1" in
        leaves) echo "git\njq" ;;
        list)
            [[ "$2" == "--cask" ]] && echo "iterm2"
            ;;
        uninstall) echo "MOCK_UNINSTALL: $*" ;;
        bundle) echo "MOCK_BUNDLE: $*" ;;
    esac
    return 0
}

_TEST_NAME="sync_brew per-item: skip leaves file unchanged"
local brewfile="$PROFILES_DIR/default/Brewfile"
printf 'brew "git"\nbrew "jq"\nbrew "wget"\n' > "$brewfile"
echo "default" > "$PROFILE_ACTIVE_FILE"
local output=$(printf 's\ns\n' | _profile_sync_brew "default" 2>&1)
local content=$(cat "$brewfile")
assert_contains "$content" "wget"

_TEST_NAME="sync_brew per-item: remove deletes from brewfile"
printf 'brew "git"\nbrew "jq"\nbrew "wget"\n' > "$brewfile"
local output=$(printf 'r\ns\n' | _profile_sync_brew "default" 2>&1)
local content=$(cat "$brewfile")
assert_not_contains "$content" "wget"
assert_contains "$content" "git"

_TEST_NAME="sync_brew per-item: skip-all prints no changes"
printf 'brew "git"\nbrew "jq"\nbrew "wget"\n' > "$brewfile"
local output=$(printf 's\ns\n' | _profile_sync_brew "default" 2>&1)
assert_contains "$output" "No changes"

_TEST_NAME="sync_brew per-item: in sync prints message"
local brewfile="$PROFILES_DIR/default/Brewfile"
printf 'brew "git"\nbrew "jq"\ncask "iterm2"\n' > "$brewfile"
local output=$(_profile_sync_brew "default" 2>&1)
assert_contains "$output" "in sync"

_TEST_NAME="sync_brew per-item: uninstall dispatches correct command"
printf 'brew "git"\nbrew "jq"\n' > "$brewfile"
# iterm2 (cask) is installed but not in profile — choose U
local output=$(printf 'u\n' | _profile_sync_brew "default" 2>&1)
assert_contains "$output" "Uninstalled cask:iterm2"

_TEST_NAME="sync_brew per-item: install via brew bundle"
printf 'brew "git"\nbrew "jq"\nbrew "wget"\ncask "iterm2"\n' > "$brewfile"
# wget not installed — choose I (default)
local output=$(printf 'i\n' | _profile_sync_brew "default" 2>&1)
assert_contains "$output" "MOCK_BUNDLE"

# --- VSCode per-item sync tests ---

_profile_vscode_instances() {
    echo "MockCode|$TEST_HOME/.config/Code/User|$TEST_HOME/mock-code"
}

mkdir -p "$TEST_HOME/.config/Code/User"
cat > "$TEST_HOME/mock-code" << 'MOCKEOF'
#!/bin/zsh
case "$1" in
    --list-extensions) cat "$MOCK_EXTENSIONS_FILE" 2>/dev/null ;;
    --install-extension) echo "MOCK_INSTALL: $2" ;;
    --uninstall-extension) echo "MOCK_UNINSTALL: $2" ;;
esac
MOCKEOF
chmod +x "$TEST_HOME/mock-code"

export MOCK_EXTENSIONS_FILE="$TEST_HOME/mock_extensions.txt"

_TEST_NAME="sync_vscode per-item: remove deletes from extensions.txt"
local extfile="$PROFILES_DIR/default/vscode/extensions.txt"
printf 'ext.one\next.two\next.three\n' > "$extfile"
printf 'ext.one\next.three\n' > "$MOCK_EXTENSIONS_FILE"
local output=$(printf 'r\n' | _profile_sync_vscode "default" 2>&1)
local content=$(cat "$extfile")
assert_not_contains "$content" "ext.two"
assert_contains "$content" "ext.one"

_TEST_NAME="sync_vscode per-item: skip leaves extensions.txt unchanged"
printf 'ext.one\next.two\next.three\n' > "$extfile"
printf 'ext.one\next.three\n' > "$MOCK_EXTENSIONS_FILE"
local output=$(printf 's\n' | _profile_sync_vscode "default" 2>&1)
local content=$(cat "$extfile")
assert_contains "$content" "ext.two"
assert_contains "$output" "No changes"

_TEST_NAME="sync_vscode per-item: in sync prints message"
printf 'ext.one\next.three\n' > "$extfile"
printf 'ext.one\next.three\n' > "$MOCK_EXTENSIONS_FILE"
local output=$(_profile_sync_vscode "default" 2>&1)
assert_contains "$output" "in sync"

_TEST_NAME="sync_vscode per-item: uninstall calls CLI"
printf 'ext.one\n' > "$extfile"
printf 'ext.one\next.extra\n' > "$MOCK_EXTENSIONS_FILE"
local output=$(printf 'u\n' | _profile_sync_vscode "default" 2>&1)
assert_contains "$output" "Uninstalled ext.extra"

# --- Mise per-item sync tests ---

mise() {
    case "$1" in
        ls)
            echo '{"node":["22.0.0"],"ruby":["3.3.0"]}'
            ;;
        uninstall) echo "MOCK_MISE_UNINSTALL: $*" ;;
        install) echo "MOCK_MISE_INSTALL" ;;
    esac
    return 0
}

_TEST_NAME="sync_mise per-item: remove deletes tool from config.toml"
local misefile="$PROFILES_DIR/default/mise/config.toml"
printf '[tools]\nnode = "lts"\nruby = "3"\ngo = "latest"\n\n[settings]\nnot_found_auto_install = true\n' > "$misefile"
local output=$(printf 'r\n' | _profile_sync_mise "default" 2>&1)
local content=$(cat "$misefile")
assert_not_contains "$content" "go"
assert_contains "$content" "node"
assert_contains "$content" "[settings]"

_test_summary
