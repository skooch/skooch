#!/usr/bin/env zsh

source "${0:A:h}/harness.sh"

_CONTROL_SCRIPT_SRC="${0:A:h}/../lib/git-cache/control.sh"
_SETUP_SCRIPT_SRC="${0:A:h}/../lib/git-cache/setup.sh"
_PLIST_SRC="${0:A:h}/../lib/git-cache/com.skooch.git-cache-http-server.plist"
export TEST_HOME

_TEST_NAME="profile cache dispatches to the control script"
mkdir -p "$TEST_DOTFILES/lib/git-cache"
cat > "$TEST_DOTFILES/lib/git-cache/control.sh" <<'EOF'
#!/usr/bin/env zsh
printf '%s\n' "$*" > "$TEST_HOME/profile-cache-call.txt"
EOF
chmod +x "$TEST_DOTFILES/lib/git-cache/control.sh"
profile cache clear skooch/skooch >/dev/null 2>&1
assert_eq "clear skooch/skooch" "$(cat "$TEST_HOME/profile-cache-call.txt")"

_TEST_NAME="profile cache on removes the disabled marker and provisions a missing install"
cp "$_CONTROL_SCRIPT_SRC" "$TEST_DOTFILES/lib/git-cache/control.sh"
chmod +x "$TEST_DOTFILES/lib/git-cache/control.sh"
cat > "$TEST_HOME/fake-setup.sh" <<'EOF'
#!/usr/bin/env zsh
printf '%s\n' "$*" > "$TEST_HOME/setup-call.txt"
EOF
chmod +x "$TEST_HOME/fake-setup.sh"
mkdir -p "$TEST_HOME/.config/git-cache"
: > "$TEST_HOME/.config/git-cache/disabled"
rm -rf "$TEST_HOME/install-prefix"
HOME="$TEST_HOME" DOTFILES_DIR="$TEST_DOTFILES" GIT_CACHE_SETUP_BIN="$TEST_HOME/fake-setup.sh" GIT_CACHE_INSTALL_PREFIX="$TEST_HOME/install-prefix" "$TEST_DOTFILES/lib/git-cache/control.sh" on >/dev/null 2>&1
assert_eq "setup" "$(cat "$TEST_HOME/setup-call.txt")"
if [[ ! -f "$TEST_HOME/.config/git-cache/disabled" ]]; then
    pass
else
    fail "disabled marker should be removed by profile cache on"
fi

_TEST_NAME="profile cache on repairs legacy persistent git cache rewrites"
cp "$_SETUP_SCRIPT_SRC" "$TEST_DOTFILES/lib/git-cache/setup.sh"
chmod +x "$TEST_DOTFILES/lib/git-cache/setup.sh"
cp "$_PLIST_SRC" "$TEST_DOTFILES/lib/git-cache/com.skooch.git-cache-http-server.plist"
fake_bin="$TEST_HOME/bin"
mkdir -p "$fake_bin" "$TEST_HOME/install-prefix/node_modules/.bin" "$TEST_HOME/.config/git"
cat > "$fake_bin/launchctl" <<'EOF'
#!/usr/bin/env zsh
exit 0
EOF
chmod +x "$fake_bin/launchctl"
cat > "$TEST_HOME/install-prefix/node_modules/.bin/git-cache-http-server" <<'EOF'
#!/usr/bin/env zsh
exit 0
EOF
chmod +x "$TEST_HOME/install-prefix/node_modules/.bin/git-cache-http-server"
echo "[url \"http://127.0.0.1:1234/github.com/\"]" > "$TEST_HOME/.config/git/cache.inc"
HOME="$TEST_HOME" git config --global --add include.path "$TEST_HOME/.config/git/cache.inc"
HOME="$TEST_HOME" git config --global --add url.http://127.0.0.1:1234/github.com/.insteadOf https://github.com/
HOME="$TEST_HOME" PATH="$fake_bin:$PATH" DOTFILES_DIR="$TEST_DOTFILES" GIT_CACHE_INSTALL_PREFIX="$TEST_HOME/install-prefix" "$TEST_DOTFILES/lib/git-cache/control.sh" on >/dev/null 2>&1
if [[ ! -e "$TEST_HOME/.config/git/cache.inc" ]]; then
    pass
else
    fail "legacy cache include file should be removed by profile cache on"
fi
legacy_includes=$(HOME="$TEST_HOME" git config --global --get-all include.path 2>/dev/null || true)
assert_not_contains "$legacy_includes" "$TEST_HOME/.config/git/cache.inc"
legacy_rewrites=$(HOME="$TEST_HOME" git config --global --get-regexp '^url\.http://127\.0\.0\.1:[0-9]+/github\.com/\.insteadof$' 2>/dev/null || true)
assert_eq "" "$legacy_rewrites"

_TEST_NAME="profile cache off writes the disabled marker and stops the service"
HOME="$TEST_HOME" DOTFILES_DIR="$TEST_DOTFILES" GIT_CACHE_SETUP_BIN="$TEST_HOME/fake-setup.sh" "$TEST_DOTFILES/lib/git-cache/control.sh" off >/dev/null 2>&1
assert_eq "stop" "$(cat "$TEST_HOME/setup-call.txt")"
if [[ -f "$TEST_HOME/.config/git-cache/disabled" ]]; then
    pass
else
    fail "disabled marker should be written by profile cache off"
fi

_TEST_NAME="profile cache clear removes matching repo and repo.git entries only"
cache_dir="$TEST_HOME/cache"
mkdir -p "$cache_dir/github.com/skooch/skooch" "$cache_dir/github.com/skooch/skooch.git" "$cache_dir/github.com/openai/skills.git"
HOME="$TEST_HOME" DOTFILES_DIR="$TEST_DOTFILES" GIT_CACHE_SETUP_BIN="$TEST_HOME/fake-setup.sh" GIT_CACHE_CACHE_DIR="$cache_dir" "$TEST_DOTFILES/lib/git-cache/control.sh" clear skooch/skooch >/dev/null 2>&1
if [[ ! -e "$cache_dir/github.com/skooch/skooch" && ! -e "$cache_dir/github.com/skooch/skooch.git" && -e "$cache_dir/github.com/openai/skills.git" ]]; then
    pass
else
    fail "targeted clear should remove only the requested repo cache entries"
fi

_TEST_NAME="profile cache clear accepts a full URL"
mkdir -p "$cache_dir/github.com/openai/skills" "$cache_dir/github.com/openai/skills.git"
HOME="$TEST_HOME" DOTFILES_DIR="$TEST_DOTFILES" GIT_CACHE_SETUP_BIN="$TEST_HOME/fake-setup.sh" GIT_CACHE_CACHE_DIR="$cache_dir" "$TEST_DOTFILES/lib/git-cache/control.sh" clear https://github.com/openai/skills.git >/dev/null 2>&1
if [[ ! -e "$cache_dir/github.com/openai/skills" && ! -e "$cache_dir/github.com/openai/skills.git" ]]; then
    pass
else
    fail "URL-based clear should remove both plain and .git cache entries"
fi

_TEST_NAME="profile cache status reports mode and cache summary"
mkdir -p "$cache_dir/github.com/jonasmalacofilho/git-cache-http-server"
cat > "$TEST_HOME/fake-setup.sh" <<'EOF'
#!/usr/bin/env zsh
if [[ "${1:-}" == "status" ]]; then
    echo "Service: loaded"
else
    printf '%s\n' "$*" > "$TEST_HOME/setup-call.txt"
fi
EOF
chmod +x "$TEST_HOME/fake-setup.sh"
rm -f "$TEST_HOME/.config/git-cache/disabled"
status_output=$(HOME="$TEST_HOME" DOTFILES_DIR="$TEST_DOTFILES" GIT_CACHE_SETUP_BIN="$TEST_HOME/fake-setup.sh" GIT_CACHE_CACHE_DIR="$cache_dir" "$TEST_DOTFILES/lib/git-cache/control.sh" status)
assert_contains "$status_output" "Enabled: yes"
assert_contains "$status_output" "Cached repos: 1"
assert_contains "$status_output" "github.com/jonasmalacofilho/git-cache-http-server"
assert_contains "$status_output" "Service: loaded"

_TEST_NAME="profile cache status shows disabled mode"
: > "$TEST_HOME/.config/git-cache/disabled"
status_output=$(HOME="$TEST_HOME" DOTFILES_DIR="$TEST_DOTFILES" GIT_CACHE_SETUP_BIN="$TEST_HOME/fake-setup.sh" GIT_CACHE_CACHE_DIR="$cache_dir" "$TEST_DOTFILES/lib/git-cache/control.sh" status)
assert_contains "$status_output" "Enabled: no"

_test_summary
