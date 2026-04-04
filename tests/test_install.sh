#!/usr/bin/env zsh
# Test install.sh end-to-end with mocked system tools.

set -uo pipefail

_TEST_PASS=0
_TEST_FAIL=0
_TEST_NAME=""

REPO_ROOT="${0:A:h:h}"
TEST_TMP_ROOT=$(mktemp -d)
REAL_GREP=$(command -v grep)
REAL_JQ=$(command -v jq)
REAL_ZSH=$(command -v zsh)

pass() {
    (( _TEST_PASS++ )) || true
    echo "  PASS: $_TEST_NAME"
}

fail() {
    local msg="${1:-}"
    (( _TEST_FAIL++ )) || true
    echo "  FAIL: $_TEST_NAME${msg:+ ($msg)}"
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

assert_file_exists() {
    local filepath="$1" msg="${2:-}"
    if [[ -f "$filepath" ]]; then
        pass
    else
        fail "${msg:+$msg: }file '$filepath' does not exist"
    fi
}

make_install_fixture() {
    local name="$1"
    local home_dir="$TEST_TMP_ROOT/$name-home"
    local repo_dir="$home_dir/projects/skooch"

    mkdir -p "$home_dir/projects" "$repo_dir/.git/hooks"
    cp "$REPO_ROOT/install.sh" "$repo_dir/install.sh"
    cp "$REPO_ROOT/.zshenv" "$repo_dir/.zshenv"
    cp "$REPO_ROOT/.zshrc" "$repo_dir/.zshrc"
    cp "$REPO_ROOT/.zprofile" "$repo_dir/.zprofile"
    cp "$REPO_ROOT/.zsh_plugins.txt" "$repo_dir/.zsh_plugins.txt"
    cp -R "$REPO_ROOT/functions" "$repo_dir/functions"
    cp -R "$REPO_ROOT/hooks" "$repo_dir/hooks"
    mkdir -p "$repo_dir/lib"
    cp -R "$REPO_ROOT/lib/profile" "$repo_dir/lib/profile"

    echo "$home_dir"
}

setup_mock_bin() {
    local home_dir="$1" os_name="${2:-Darwin}"
    local mock_bin="$home_dir/mock-bin"
    local brew_prefix="$home_dir/homebrew"
    local mock_log="$home_dir/mock.log"

    mkdir -p "$mock_bin" "$brew_prefix/bin"
    ln -sf "$REAL_ZSH" "$brew_prefix/bin/zsh"
    : > "$mock_log"

    cat > "$mock_bin/uname" << EOF
#!/bin/sh
printf '%s\n' '$os_name'
EOF

    cat > "$mock_bin/ioreg" << 'EOF'
#!/bin/sh
printf '%s\n' '"IOPlatformUUID" = "TEST-UUID-1234"'
EOF

    cat > "$mock_bin/brew" << EOF
#!/bin/sh
case "\$1" in
  --prefix)
    printf '%s\n' '$brew_prefix'
    ;;
  install)
    exit 0
    ;;
  shellenv)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF

    cat > "$mock_bin/git" << EOF
#!/bin/sh
if [ "\$1" = "clone" ]; then
  for last_arg in "\$@"; do :; done
  mkdir -p "\$last_arg"
  exit 0
fi
if [ "\$1" = "lfs" ]; then
  exit 0
fi
exit 0
EOF

    cat > "$mock_bin/mise" << 'EOF'
#!/bin/sh
exit 0
EOF

    ln -sf "$REAL_JQ" "$mock_bin/jq"

    cat > "$mock_bin/grep" << EOF
#!/bin/sh
for last_arg in "\$@"; do :; done
if [ "\$last_arg" = "/etc/shells" ]; then
  exit 0
fi
exec "$REAL_GREP" "\$@"
EOF

    cat > "$mock_bin/dscl" << EOF
#!/bin/sh
printf 'UserShell %s\n' '$brew_prefix/bin/zsh'
EOF

    cat > "$mock_bin/chsh" << EOF
#!/bin/sh
echo chsh >> '$mock_log'
exit 0
EOF

    cat > "$mock_bin/sudo" << EOF
#!/bin/sh
echo sudo >> '$mock_log'
exit 0
EOF

    chmod +x "$mock_bin/"*
    echo "$mock_bin"
}

run_install() {
    local home_dir="$1"
    local mock_bin="$2"
    local repo_dir="$home_dir/projects/skooch"
    HOME="$home_dir" PATH="$mock_bin:$PATH" sh "$repo_dir/install.sh" 2>&1
}

_TEST_NAME="install.sh rejects unsupported OS"
local unsupported_home="$TEST_TMP_ROOT/unsupported-home"
mkdir -p "$unsupported_home"
local unsupported_bin=$(setup_mock_bin "$unsupported_home" "FreeBSD")
unsupported_output=$(HOME="$unsupported_home" PATH="$unsupported_bin:$PATH" sh "$REPO_ROOT/install.sh" 2>&1)
unsupported_status=$?
if [[ "$unsupported_status" -eq 1 ]]; then
    pass
else
    fail "expected exit code 1, got $unsupported_status"
fi
_TEST_NAME="install.sh unsupported OS reports requirement"
assert_contains "$unsupported_output" "macOS or Linux required"

_TEST_NAME="install.sh exits when repo path is missing"
local missing_home="$TEST_TMP_ROOT/missing-home"
mkdir -p "$missing_home"
local missing_bin=$(setup_mock_bin "$missing_home" "Darwin")
missing_output=$(HOME="$missing_home" PATH="$missing_bin:$PATH" sh "$REPO_ROOT/install.sh" 2>&1)
missing_status=$?
if [[ "$missing_status" -eq 1 ]]; then
    pass
else
    fail "expected exit code 1, got $missing_status"
fi
_TEST_NAME="install.sh missing repo reports expected path"
assert_contains "$missing_output" "Dotfiles repo not found"

local success_home=$(make_install_fixture "success")
local success_repo="$success_home/projects/skooch"
local success_bin=$(setup_mock_bin "$success_home" "Darwin")
mkdir -p "$success_home/projects/dotfiles-private"
echo '# secrets' > "$success_home/projects/dotfiles-private/.zshrc.private"
local machine_id=$(HOME="$success_home" PATH="$success_bin:$PATH" "$success_home/homebrew/bin/zsh" -c "source '$success_repo/lib/profile/index.sh' && _profile_machine_id")
printf '{ "%s": ["embedded"] }\n' "$machine_id" > "$success_repo/hosts.json"

success_output=$(run_install "$success_home" "$success_bin")
success_status=$?

_TEST_NAME="install.sh success path exits cleanly"
if [[ "$success_status" -eq 0 ]]; then
    pass
else
    fail "expected exit code 0, got $success_status"
fi

_TEST_NAME="install.sh creates .zshenv symlink"
assert_symlink "$success_home/.zshenv" "$success_repo/.zshenv"

_TEST_NAME="install.sh creates .zshrc symlink"
assert_symlink "$success_home/.zshrc" "$success_repo/.zshrc"

_TEST_NAME="install.sh creates .zprofile symlink"
assert_symlink "$success_home/.zprofile" "$success_repo/.zprofile"

_TEST_NAME="install.sh creates .zsh_plugins.txt symlink"
assert_symlink "$success_home/.zsh_plugins.txt" "$success_repo/.zsh_plugins.txt"

_TEST_NAME="install.sh creates .zsh_functions symlink"
assert_symlink "$success_home/.zsh_functions" "$success_repo/functions"

_TEST_NAME="install.sh clones antidote when missing"
if [[ -d "$success_home/.antidote" ]]; then
    pass
else
    fail "expected $success_home/.antidote to exist"
fi

_TEST_NAME="install.sh installs pre-commit hook into repo hooks dir"
assert_file_exists "$success_repo/.git/hooks/pre-commit"

_TEST_NAME="install.sh reports success summary"
assert_contains "$success_output" "=== All good! ==="

_TEST_NAME="install.sh recommends profiles using machine-id hosts lookup"
assert_contains "$success_output" "profile use embedded"

_TEST_NAME="install.sh machine-id recommendation includes resolved key"
assert_contains "$success_output" "$machine_id"

_TEST_NAME="install.sh next-step note includes codex coverage"
assert_contains "$success_output" "codex"

_TEST_NAME="install.sh next-step note includes tmux coverage"
assert_contains "$success_output" "tmux"

_TEST_NAME="install.sh does not fall back to generic profile hint when hosts match"
assert_not_contains "$success_output" "profile use <name> [name2 ...]"

_TEST_NAME="install.sh recognizes private repo when present"
assert_contains "$success_output" "Private repo found"

local warning_home=$(make_install_fixture "warning")
local warning_repo="$warning_home/projects/skooch"
local warning_bin=$(setup_mock_bin "$warning_home" "Darwin")
warning_output=$(run_install "$warning_home" "$warning_bin")
warning_status=$?

_TEST_NAME="install.sh warning path still succeeds without private repo"
if [[ "$warning_status" -eq 0 ]]; then
    pass
else
    fail "expected exit code 0, got $warning_status"
fi

_TEST_NAME="install.sh warns when private repo is missing"
assert_contains "$warning_output" "Private repo not found"

_TEST_NAME="install.sh shows clone hint for private repo"
assert_contains "$warning_output" "git clone https://github.com/skooch/dotfiles-private.git"

rm -rf "$TEST_TMP_ROOT"

echo ""
echo "  $_TEST_PASS passed, $_TEST_FAIL failed"
[[ $_TEST_FAIL -eq 0 ]]
