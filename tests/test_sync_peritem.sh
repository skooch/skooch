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

_test_summary
