# Test harness - shared setup/teardown and assertion helpers
# Source this at the top of each test file.

set -uo pipefail

_TEST_PASS=0
_TEST_FAIL=0
_TEST_NAME=""

# Create isolated temp environment
TEST_HOME=$(mktemp -d)
TEST_DOTFILES=$(mktemp -d)
TEST_STATE=$(mktemp -d)

# Set up minimal profile directory structure
mkdir -p "$TEST_DOTFILES/profiles/default/claude"
mkdir -p "$TEST_DOTFILES/profiles/default/codex/hooks"
mkdir -p "$TEST_DOTFILES/profiles/default/codex/agents"
mkdir -p "$TEST_DOTFILES/profiles/default/codex/rules"
mkdir -p "$TEST_DOTFILES/profiles/default/git"
mkdir -p "$TEST_DOTFILES/profiles/default/mise"
mkdir -p "$TEST_DOTFILES/profiles/default/vscode"
mkdir -p "$TEST_DOTFILES/profiles/default/iterm"
mkdir -p "$TEST_DOTFILES/profiles/testprofile/claude"
mkdir -p "$TEST_DOTFILES/profiles/testprofile/codex"
mkdir -p "$TEST_DOTFILES/profiles/testprofile/vscode"
mkdir -p "$TEST_DOTFILES/profiles/testprofile/mise"
mkdir -p "$TEST_HOME/.claude"
mkdir -p "$TEST_HOME/.codex"

# Create dummy profile files
echo '{"test": true}' > "$TEST_DOTFILES/profiles/default/claude/settings.json"
cat > "$TEST_DOTFILES/profiles/default/codex/config.toml" << 'EOF'
model = "gpt-5.4"

[features]
codex_hooks = true
EOF
cat > "$TEST_DOTFILES/profiles/default/codex/hooks.json" << 'EOF'
{"hooks":{"SessionStart":[{"hooks":[{"command":"default"}]}]}}
EOF
echo '#!/usr/bin/env python3' > "$TEST_DOTFILES/profiles/default/codex/hooks/permission_bridge.py"
echo '#!/usr/bin/env zsh' > "$TEST_DOTFILES/profiles/default/codex/hooks/run-with-python3"
echo 'name = "explorer"' > "$TEST_DOTFILES/profiles/default/codex/agents/explorer.toml"
echo 'prefix_rule(pattern = ["rg"], decision = "allow")' > "$TEST_DOTFILES/profiles/default/codex/rules/default.rules"
printf '[include]\n\tpath = default\n' > "$TEST_DOTFILES/profiles/default/git/config"
printf '[tools]\nnode = "lts"\n' > "$TEST_DOTFILES/profiles/default/mise/config.toml"
echo '{"editor.fontSize": 14}' > "$TEST_DOTFILES/profiles/default/vscode/settings.json"
echo '[]' > "$TEST_DOTFILES/profiles/default/vscode/keybindings.json"
echo 'ext.default' > "$TEST_DOTFILES/profiles/default/vscode/extensions.txt"
echo '{"Profiles":[{"Name":"Default"}]}' > "$TEST_DOTFILES/profiles/default/iterm/profile.json"
echo 'brew "git"' > "$TEST_DOTFILES/profiles/default/Brewfile"

echo '{"extra": true}' > "$TEST_DOTFILES/profiles/testprofile/claude/settings.json"
cat > "$TEST_DOTFILES/profiles/testprofile/codex/config.toml" << 'EOF'
approval_policy = "on-request"

[features]
shell_snapshot = true
EOF
cat > "$TEST_DOTFILES/profiles/testprofile/codex/hooks.json" << 'EOF'
{"hooks":{"Stop":[{"hooks":[{"command":"testprofile"}]}]}}
EOF
echo '{"editor.tabSize": 2}' > "$TEST_DOTFILES/profiles/testprofile/vscode/settings.json"
printf '[tools]\npython = "3.12"\n' > "$TEST_DOTFILES/profiles/testprofile/mise/config.toml"

# Create stub shell files for dedup tests
echo '# zshenv' > "$TEST_DOTFILES/.zshenv"
echo '# zshrc' > "$TEST_DOTFILES/.zshrc"
echo '# zprofile' > "$TEST_DOTFILES/.zprofile"

# Override variables before sourcing the profile system
DOTFILES_DIR="$TEST_DOTFILES"
PROFILES_DIR="$TEST_DOTFILES/profiles"
HOSTS_FILE="$TEST_DOTFILES/hosts.json"
PROFILE_STATE_DIR="$TEST_STATE"
PROFILE_ACTIVE_FILE="$TEST_STATE/active"
PROFILE_SNAPSHOT_FILE="$TEST_STATE/snapshot"
PROFILE_MANAGED_FILE="$TEST_STATE/managed"

# Allow tests to pipe input to interactive prompts (bypasses /dev/tty)
_PROFILE_INPUT=/dev/stdin

# Source the profile system
_PROFILE_LIB_DIR="${0:A:h}/../lib/profile"
source "$_PROFILE_LIB_DIR/platform.sh"
source "$_PROFILE_LIB_DIR/init.sh"

# Re-override variables that init.sh set (since init.sh uses $HOME)
DOTFILES_DIR="$TEST_DOTFILES"
PROFILES_DIR="$TEST_DOTFILES/profiles"
HOSTS_FILE="$TEST_DOTFILES/hosts.json"
PROFILE_STATE_DIR="$TEST_STATE"
PROFILE_ACTIVE_FILE="$TEST_STATE/active"
PROFILE_SNAPSHOT_FILE="$TEST_STATE/snapshot"
PROFILE_MANAGED_FILE="$TEST_STATE/managed"

source "$_PROFILE_LIB_DIR/helpers.sh"
source "$_PROFILE_LIB_DIR/snapshot.sh"
source "$_PROFILE_LIB_DIR/apply.sh"
source "$_PROFILE_LIB_DIR/sync.sh"
source "$_PROFILE_LIB_DIR/diff.sh"
source "$_PROFILE_LIB_DIR/main.sh"

# --- Assertions ---

pass() {
    (( _TEST_PASS++ )) || true
    echo "  PASS: $_TEST_NAME"
}

fail() {
    local msg="${1:-}"
    (( _TEST_FAIL++ )) || true
    echo "  FAIL: $_TEST_NAME${msg:+ ($msg)}"
}

assert_eq() {
    local expected="$1" actual="$2" msg="${3:-}"
    if [[ "$expected" == "$actual" ]]; then
        pass
    else
        fail "${msg:+$msg: }expected '$expected', got '$actual'"
    fi
}

assert_neq() {
    local unexpected="$1" actual="$2" msg="${3:-}"
    if [[ "$unexpected" != "$actual" ]]; then
        pass
    else
        fail "${msg:+$msg: }expected not '$unexpected'"
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" msg="${3:-}"
    if [[ "$haystack" == *"$needle"* ]]; then
        pass
    else
        fail "${msg:+$msg: }'$needle' not found in output"
    fi
}

assert_not_contains() {
    local haystack="$1" needle="$2" msg="${3:-}"
    if [[ "$haystack" != *"$needle"* ]]; then
        pass
    else
        fail "${msg:+$msg: }'$needle' unexpectedly found in output"
    fi
}

assert_file_exists() {
    local filepath="$1" msg="${2:-}"
    if [[ -f "$filepath" ]]; then
        pass
    else
        fail "${msg:+$msg: }file '$filepath' does not exist"
    fi
}

assert_symlink() {
    local filepath="$1" expected_target="$2" msg="${3:-}"
    if [[ -L "$filepath" ]]; then
        local actual_target=$(readlink "$filepath")
        if [[ "$actual_target" == "$expected_target" ]]; then
            pass
        else
            fail "${msg:+$msg: }symlink target is '$actual_target', expected '$expected_target'"
        fi
    else
        fail "${msg:+$msg: }'$filepath' is not a symlink"
    fi
}

assert_not_symlink() {
    local filepath="$1" msg="${2:-}"
    if [[ ! -L "$filepath" ]]; then
        pass
    else
        fail "${msg:+$msg: }'$filepath' is unexpectedly a symlink"
    fi
}

assert_exit_code() {
    local expected="$1"
    shift
    "$@" 2>/dev/null
    local actual=$?
    if [[ "$actual" -eq "$expected" ]]; then
        pass
    else
        fail "expected exit code $expected, got $actual"
    fi
}

# --- Cleanup ---

_test_cleanup() {
    rm -rf "$TEST_HOME" "$TEST_DOTFILES" "$TEST_STATE"
}
trap _test_cleanup EXIT

# --- Summary ---

_test_summary() {
    echo ""
    echo "  $_TEST_PASS passed, $_TEST_FAIL failed"
    [[ $_TEST_FAIL -eq 0 ]]
}
