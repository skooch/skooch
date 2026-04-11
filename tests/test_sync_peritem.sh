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

_TEST_NAME="sync_brew per-item: skip-all leaves review pending"
printf 'brew "git"\nbrew "jq"\nbrew "wget"\n' > "$brewfile"
local output=$(printf 's\ns\n' | _profile_sync_brew "default" 2>&1)
assert_contains "$output" "Review still required"

_TEST_NAME="sync_brew per-item: remembered local skip suppresses later add prompt"
printf 'brew "git"\nbrew "jq"\n' > "$brewfile"
local output=$(printf 's\n' | _profile_sync_brew "default" 2>&1)
local output=$(_profile_sync_brew "default" </dev/null 2>&1)
local content=$(cat "$brewfile")
assert_not_contains "$content" "iterm2"
assert_contains "$output" "No changes"
_profile_sync_skip_forget "brew" "cask:iterm2"

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

_TEST_NAME="sync_vscode per-item: skip leaves extensions review pending"
printf 'ext.one\next.two\next.three\n' > "$extfile"
printf 'ext.one\next.three\n' > "$MOCK_EXTENSIONS_FILE"
local output=$(printf 's\n' | _profile_sync_vscode "default" 2>&1)
local content=$(cat "$extfile")
assert_contains "$content" "ext.two"
assert_contains "$output" "Review still required"

_TEST_NAME="sync_vscode per-item: remembered local skip suppresses later add prompt"
printf 'ext.one\n' > "$extfile"
printf 'ext.one\next.extra\n' > "$MOCK_EXTENSIONS_FILE"
local output=$(printf 's\n' | _profile_sync_vscode "default" 2>&1)
local output=$(_profile_sync_vscode "default" </dev/null 2>&1)
local content=$(cat "$extfile")
assert_not_contains "$content" "ext.extra"
assert_contains "$output" "No changes"
_profile_sync_skip_forget "vscode:MockCode" "ext.extra"
_profile_sync_skip_forget "vscode" "ext.extra"

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

_TEST_NAME="sync_vscode multi-install installs only on missing instance"
local multi_dir_a="$TEST_HOME/.config/Code A/User"
local multi_dir_b="$TEST_HOME/.config/Code B/User"
mkdir -p "$multi_dir_a" "$multi_dir_b"
local multi_ext_a="$TEST_HOME/mock_extensions_a.txt"
local multi_ext_b="$TEST_HOME/mock_extensions_b.txt"
local multi_install_a="$TEST_HOME/mock_install_a.log"
local multi_install_b="$TEST_HOME/mock_install_b.log"
printf 'ext.shared\n' > "$multi_ext_a"
: > "$multi_ext_b"
: > "$multi_install_a"
: > "$multi_install_b"
local multi_cli_a="$TEST_HOME/mock-code-a"
local multi_cli_b="$TEST_HOME/mock-code-b"
cat > "$multi_cli_a" << EOF
#!/bin/zsh
case "\$1" in
    --list-extensions) cat "$multi_ext_a" 2>/dev/null ;;
    --install-extension) echo "\$2" >> "$multi_install_a"; echo "MOCK_INSTALL_A: \$2" ;;
    --uninstall-extension) echo "MOCK_UNINSTALL_A: \$2" ;;
esac
EOF
cat > "$multi_cli_b" << EOF
#!/bin/zsh
case "\$1" in
    --list-extensions) cat "$multi_ext_b" 2>/dev/null ;;
    --install-extension) echo "\$2" >> "$multi_install_b"; echo "MOCK_INSTALL_B: \$2" ;;
    --uninstall-extension) echo "MOCK_UNINSTALL_B: \$2" ;;
esac
EOF
chmod +x "$multi_cli_a" "$multi_cli_b"
_profile_vscode_instances() {
    echo "MockCodeA|$multi_dir_a|$multi_cli_a"
    echo "MockCodeB|$multi_dir_b|$multi_cli_b"
}
printf 'ext.shared\n' > "$extfile"
local multi_input=$(mktemp)
printf 'i\n' > "$multi_input"
_PROFILE_INPUT="$multi_input"
local output=$(_profile_sync_vscode "default" 2>&1)
rm -f "$multi_input"
_PROFILE_INPUT=/dev/stdin
local install_a_log=$(cat "$multi_install_a")
local install_b_log=$(cat "$multi_install_b")
assert_not_contains "$install_a_log" "ext.shared"
assert_contains "$install_b_log" "ext.shared"

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

_TEST_NAME="sync_mise per-item: remembered local skip suppresses later add prompt"
printf '[tools]\nnode = "lts"\n\n[settings]\nnot_found_auto_install = true\n' > "$misefile"
local output=$(printf 's\n' | _profile_sync_mise "default" 2>&1)
local output=$(_profile_sync_mise "default" </dev/null 2>&1)
local content=$(cat "$misefile")
assert_not_contains "$content" "ruby"
assert_contains "$content" "node"
_profile_sync_skip_forget "mise" "ruby"

_test_summary
