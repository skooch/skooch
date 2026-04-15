#!/usr/bin/env zsh

source "${0:A:h}/harness.sh"

_GIT_CACHE_LIB_DIR="${0:A:h}/../lib/git-cache"
_GIT_CACHE_FUNCTIONS="${0:A:h}/../functions/git-cache.sh"
chmod +x "$_GIT_CACHE_LIB_DIR/git.sh"

_TEST_NAME="gitcache clone injects cache rewrite only for this command"
fake_bin="$TEST_HOME/bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/git" <<'EOF'
#!/usr/bin/env zsh
printf '%s\n' "$@"
EOF
chmod +x "$fake_bin/git"
PATH="$fake_bin:$PATH"
export TEST_HOME
args=$(GITCACHE_GIT_BIN="$fake_bin/git" zsh "$_GIT_CACHE_LIB_DIR/git.sh" clone https://github.com/example/project repo)
assert_contains "$args" "-c"
assert_contains "$args" "url.http://127.0.0.1:1234/github.com/.insteadOf=https://github.com/"
assert_contains "$args" "clone"
assert_contains "$args" "https://github.com/example/project"

_TEST_NAME="gitcache fetch injects cache rewrite only for this command"
args=$(GITCACHE_GIT_BIN="$fake_bin/git" zsh "$_GIT_CACHE_LIB_DIR/git.sh" fetch origin main)
assert_contains "$args" "fetch"
assert_contains "$args" "origin"
assert_contains "$args" "main"
assert_contains "$args" "url.http://127.0.0.1:1234/github.com/.insteadOf=https://github.com/"

_TEST_NAME="gitcache submodule-update uses git submodule update under cache rewrite"
args=$(GITCACHE_GIT_BIN="$fake_bin/git" zsh "$_GIT_CACHE_LIB_DIR/git.sh" submodule-update --init deps/cache)
assert_contains "$args" "submodule"
assert_contains "$args" "update"
assert_contains "$args" "--init"
assert_contains "$args" "deps/cache"
assert_contains "$args" "url.http://127.0.0.1:1234/github.com/.insteadOf=https://github.com/"

_TEST_NAME="gitcache falls back to plain git when disabled"
mkdir -p "$TEST_HOME/.config/git-cache"
: > "$TEST_HOME/.config/git-cache/disabled"
args=$(HOME="$TEST_HOME" GITCACHE_GIT_BIN="$fake_bin/git" zsh "$_GIT_CACHE_LIB_DIR/git.sh" clone https://github.com/example/project repo)
assert_contains "$args" "clone"
assert_not_contains "$args" "url.http://127.0.0.1:1234/github.com/.insteadOf=https://github.com/"

_TEST_NAME="gitcache push is rejected"
push_output=$(GITCACHE_GIT_BIN="$fake_bin/git" zsh "$_GIT_CACHE_LIB_DIR/git.sh" push origin main 2>&1 || true)
assert_contains "$push_output" "intentionally unsupported"

_TEST_NAME="gitcache function routes service commands to setup script"
fake_dotfiles="$TEST_HOME/projects/skooch"
mkdir -p "$fake_dotfiles/lib/git-cache" "$fake_dotfiles/functions"
cp "$_GIT_CACHE_FUNCTIONS" "$fake_dotfiles/functions/git-cache.sh"
cat > "$fake_dotfiles/lib/git-cache/setup.sh" <<'EOF'
#!/usr/bin/env zsh
printf 'setup:%s\n' "$*" > "$TEST_HOME/setup-call.txt"
EOF
chmod +x "$fake_dotfiles/lib/git-cache/setup.sh"
cat > "$fake_dotfiles/lib/git-cache/git.sh" <<'EOF'
#!/usr/bin/env zsh
printf 'git:%s\n' "$*" > "$TEST_HOME/git-call.txt"
EOF
chmod +x "$fake_dotfiles/lib/git-cache/git.sh"
HOME="$TEST_HOME" zsh -c 'source "$HOME/projects/skooch/functions/git-cache.sh"; gitcache status' >/dev/null 2>&1
assert_eq "setup:status" "$(cat "$TEST_HOME/setup-call.txt")"

_TEST_NAME="gitcache function routes read commands to git wrapper"
HOME="$TEST_HOME" zsh -c 'source "$HOME/projects/skooch/functions/git-cache.sh"; gitcache fetch origin' >/dev/null 2>&1
assert_eq "git:fetch origin" "$(cat "$TEST_HOME/git-call.txt")"

_TEST_NAME="interactive git wrapper routes clone through gitcache"
cp "${0:A:h}/../functions/git.sh" "$fake_dotfiles/functions/git.sh"
HOME="$TEST_HOME" zsh -c 'source "$HOME/projects/skooch/functions/git-cache.sh"; source "$HOME/projects/skooch/functions/git.sh"; git clone https://github.com/example/project repo' >/dev/null 2>&1
assert_eq "git:clone https://github.com/example/project repo" "$(cat "$TEST_HOME/git-call.txt")"

_TEST_NAME="interactive git wrapper routes submodule update through gitcache"
HOME="$TEST_HOME" zsh -c 'source "$HOME/projects/skooch/functions/git-cache.sh"; source "$HOME/projects/skooch/functions/git.sh"; git submodule update --init deps/cache' >/dev/null 2>&1
assert_eq "git:submodule-update --init deps/cache" "$(cat "$TEST_HOME/git-call.txt")"

_TEST_NAME="interactive git wrapper routes remote update through gitcache"
HOME="$TEST_HOME" zsh -c 'source "$HOME/projects/skooch/functions/git-cache.sh"; source "$HOME/projects/skooch/functions/git.sh"; git remote update origin' >/dev/null 2>&1
assert_eq "git:remote-update origin" "$(cat "$TEST_HOME/git-call.txt")"

_TEST_NAME="interactive git wrapper leaves push untouched"
cat > "$fake_bin/git" <<'EOF'
#!/usr/bin/env zsh
printf '%s\n' "$@" > "$TEST_HOME/wrapped-git-call.txt"
EOF
chmod +x "$fake_bin/git"
HOME="$TEST_HOME" PATH="$fake_bin:$PATH" SKOOCH_GIT_BIN="$fake_bin/git" zsh -c 'source "$HOME/projects/skooch/functions/git-cache.sh"; source "$HOME/projects/skooch/functions/git.sh"; git push origin main' >/dev/null 2>&1
assert_eq $'push\norigin\nmain' "$(cat "$TEST_HOME/wrapped-git-call.txt")"

_TEST_NAME="git wrapper prefers Homebrew git when PATH would resolve Apple git"
mkdir -p "$TEST_HOME/homebrew/bin" "$TEST_HOME/system/bin"
cat > "$TEST_HOME/homebrew/bin/git" <<'EOF'
#!/usr/bin/env zsh
printf 'homebrew\n'
EOF
cat > "$TEST_HOME/system/bin/git" <<'EOF'
#!/usr/bin/env zsh
printf 'system\n'
EOF
chmod +x "$TEST_HOME/homebrew/bin/git" "$TEST_HOME/system/bin/git"
git_bin=$(HOME="$TEST_HOME" HOMEBREW_PREFIX="$TEST_HOME/homebrew" PATH="$TEST_HOME/system/bin:/bin" zsh -c 'source "$HOME/projects/skooch/functions/git.sh"; _git_real_bin')
assert_eq "$TEST_HOME/homebrew/bin/git" "$git_bin"

_TEST_NAME="git wrapper falls back to PATH git when no preferred git exists"
git_bin=$(HOME="$TEST_HOME" HOMEBREW_PREFIX="$TEST_HOME/missing-homebrew" PATH="$TEST_HOME/system/bin:/bin" zsh -c 'source "$HOME/projects/skooch/functions/git.sh"; _git_real_bin')
assert_eq "$TEST_HOME/system/bin/git" "$git_bin"

_TEST_NAME="worktree remove -f prunes node_modules before invoking git"
mkdir -p "$TEST_HOME/wt/packages/app/node_modules/pkg"
print "gitdir: fake" > "$TEST_HOME/wt/.git"
print "x" > "$TEST_HOME/wt/packages/app/node_modules/pkg/file.js"
cat > "$fake_bin/git" <<'EOF'
#!/usr/bin/env zsh
if [[ "$1" == "-C" ]]; then
    shift 2
fi
case "$1" in
    rev-parse)
        printf 'worktree-branch\n'
        ;;
    worktree)
        if [[ "$2" == "remove" ]]; then
            if [[ -d "$TEST_HOME/wt/packages/app/node_modules" ]]; then
                printf 'present\n' > "$TEST_HOME/worktree-remove-node-modules.txt"
            else
                printf 'gone\n' > "$TEST_HOME/worktree-remove-node-modules.txt"
            fi
            rm -rf "$TEST_HOME/wt"
        fi
        ;;
esac
EOF
chmod +x "$fake_bin/git"
HOME="$TEST_HOME" SKOOCH_GIT_BIN="$fake_bin/git" zsh -c 'source "$HOME/projects/skooch/functions/git.sh"; _git_worktree_remove -f "$HOME/wt"' >/dev/null 2>&1
assert_eq "gone" "$(cat "$TEST_HOME/worktree-remove-node-modules.txt")"

_TEST_NAME="worktree remove without force leaves node_modules for git"
mkdir -p "$TEST_HOME/wt/packages/app/node_modules/pkg"
print "gitdir: fake" > "$TEST_HOME/wt/.git"
print "x" > "$TEST_HOME/wt/packages/app/node_modules/pkg/file.js"
HOME="$TEST_HOME" SKOOCH_GIT_BIN="$fake_bin/git" zsh -c 'source "$HOME/projects/skooch/functions/git.sh"; _git_worktree_remove "$HOME/wt"' >/dev/null 2>&1
assert_eq "present" "$(cat "$TEST_HOME/worktree-remove-node-modules.txt")"

_TEST_NAME="worktree cargo isolation resolves Python via shared helper when PATH is missing"
mkdir -p "$fake_dotfiles/lib/shell"
cat > "$fake_dotfiles/lib/shell/python.sh" <<'EOF'
_skooch_python3_bin() {
    printf '%s' "$HOME/bin/fake-python3"
}
EOF
cat > "$TEST_HOME/bin/fake-python3" <<'EOF'
#!/usr/bin/env zsh
print "$HOME/.cache/cargo-target/shared"
EOF
chmod +x "$TEST_HOME/bin/fake-python3"
mkdir -p "$TEST_HOME/wt/.cargo"
echo '[package]
name = "demo"
version = "0.1.0"' > "$TEST_HOME/wt/Cargo.toml"
echo '[build]
target-dir = "~/.cache/cargo-target/shared"' > "$TEST_HOME/wt/.cargo/config.toml"
worktree_target=$(HOME="$TEST_HOME" PATH="/bin" zsh -c 'source "$HOME/projects/skooch/functions/git.sh"; _git_worktree_cargo_isolate "$HOME/wt" >/dev/null; cat "$HOME/wt/.cargo/.worktree-target"')
assert_eq "$TEST_HOME/.cache/cargo-target/shared/worktrees/wt" "$worktree_target"

_TEST_NAME="real git helper forwards push arguments unchanged"
cat > "$fake_bin/git" <<'EOF'
#!/usr/bin/env zsh
printf '%s\n' "$@"
EOF
chmod +x "$fake_bin/git"
args=$(HOME="$TEST_HOME" SKOOCH_GIT_BIN="$fake_bin/git" zsh -c 'source "$HOME/projects/skooch/functions/git.sh"; _git_real push origin main')
assert_eq $'push\norigin\nmain' "$args"

# --- Credential helper tests ---

_CRED_HELPER="$_GIT_CACHE_LIB_DIR/credential-helper.sh"

_TEST_NAME="credential helper responds for 127.0.0.1:1234"
cred_out=$(printf 'protocol=http\nhost=127.0.0.1:1234\n\n' | GIT_CACHE_PORT=1234 zsh "$_CRED_HELPER" get 2>/dev/null)
assert_contains "$cred_out" "host=github.com"
assert_contains "$cred_out" "protocol=https"

_TEST_NAME="credential helper ignores other hosts"
cred_out=$(printf 'protocol=http\nhost=evil.com:1234\n\n' | GIT_CACHE_PORT=1234 zsh "$_CRED_HELPER" get 2>/dev/null)
assert_eq "" "$cred_out"

_TEST_NAME="credential helper ignores other ports"
cred_out=$(printf 'protocol=http\nhost=127.0.0.1:9999\n\n' | GIT_CACHE_PORT=1234 zsh "$_CRED_HELPER" get 2>/dev/null)
assert_eq "" "$cred_out"

_TEST_NAME="credential helper ignores store action"
cred_out=$(printf 'protocol=http\nhost=127.0.0.1:1234\n\n' | GIT_CACHE_PORT=1234 zsh "$_CRED_HELPER" store 2>/dev/null)
assert_eq "" "$cred_out"

_TEST_NAME="credential helper ignores erase action"
cred_out=$(printf 'protocol=http\nhost=127.0.0.1:1234\n\n' | GIT_CACHE_PORT=1234 zsh "$_CRED_HELPER" erase 2>/dev/null)
assert_eq "" "$cred_out"

_TEST_NAME="credential helper never echoes input host in output"
cred_out=$(printf 'protocol=http\nhost=127.0.0.1:1234\n\n' | GIT_CACHE_PORT=1234 zsh "$_CRED_HELPER" get 2>/dev/null)
assert_not_contains "$cred_out" "host=127.0.0.1"

_TEST_NAME="credential helper respects custom GIT_CACHE_PORT"
cred_out=$(printf 'protocol=http\nhost=127.0.0.1:5678\n\n' | GIT_CACHE_PORT=5678 zsh "$_CRED_HELPER" get 2>/dev/null)
assert_contains "$cred_out" "host=github.com"

_TEST_NAME="credential helper rejects custom port when env mismatches"
cred_out=$(printf 'protocol=http\nhost=127.0.0.1:5678\n\n' | GIT_CACHE_PORT=1234 zsh "$_CRED_HELPER" get 2>/dev/null)
assert_eq "" "$cred_out"

# --- setup.sh upstream.gitconfig tests ---

_TEST_NAME="setup writes credential helper into upstream.gitconfig"
fake_install="$TEST_HOME/opt/git-cache-test"
mkdir -p "$fake_install"
# Source just the function, dont run install_package
upstream_cfg="$fake_install/upstream.gitconfig"
GIT_CACHE_INSTALL_PREFIX="$fake_install" zsh -c '
    source "'"$_GIT_CACHE_LIB_DIR"'/setup.sh" <<< "" 2>/dev/null || true
' 2>/dev/null || true
# Test the function directly via inline eval
GIT_CACHE_INSTALL_PREFIX="$fake_install" zsh -c '
    install_prefix="'"$fake_install"'"
    source /dev/stdin <<FUNC
'"$(sed -n '/^write_upstream_gitconfig/,/^}/p' "$_GIT_CACHE_LIB_DIR/setup.sh")"'
FUNC
    write_upstream_gitconfig
'
assert_file_exists "$upstream_cfg"
assert_contains "$(cat "$upstream_cfg")" "credential"
assert_contains "$(cat "$upstream_cfg")" "gh auth git-credential"

_test_summary
