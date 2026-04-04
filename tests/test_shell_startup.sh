#!/usr/bin/env zsh

source "${0:A:h}/harness.sh"

_REPO_ROOT="${0:A:h}/.."
_RUNTIME_SRC="$_REPO_ROOT/lib/shell/runtime.sh"
_ZSHENV_SRC="$_REPO_ROOT/.zshenv"
_ZPROFILE_SRC="$_REPO_ROOT/.zprofile"

_TEST_NAME="shared shell runtime prepends mise shims in non-interactive shells"
runtime_output=$(
    HOME="$TEST_HOME/runtime-home" PATH="/usr/bin:/bin" zsh -c '
        mkdir -p "$HOME/.local/share/mise/shims"
        print "#!/usr/bin/env zsh\nexit 0" > "$HOME/.local/share/mise/shims/demo-tool"
        chmod +x "$HOME/.local/share/mise/shims/demo-tool"
        source "'"$_RUNTIME_SRC"'"
        command -v demo-tool
    '
)
assert_eq "$TEST_HOME/runtime-home/.local/share/mise/shims/demo-tool" "$runtime_output"

_TEST_NAME="shared shell runtime captures an executable python3 interpreter path"
python_output=$(
    zsh -c '
        source "'"$_RUNTIME_SRC"'"
        if [[ -n "${SKOOCH_PYTHON3_BIN:-}" && -x "${SKOOCH_PYTHON3_BIN}" ]]; then
            printf "%s" "${SKOOCH_PYTHON3_BIN}"
        fi
    '
)
assert_contains "$python_output" "python"

_TEST_NAME="shared shell runtime enables Codex-specific mise env and uv shim"
codex_output=$(
    HOME="$TEST_HOME/runtime-codex" PATH="/Applications/Codex.app/Contents/Resources:/usr/bin:/bin" zsh -c '
        mkdir -p "$HOME/mise-root/uv-1.2.3"
        print "#!/usr/bin/env zsh\nexit 0" > "$HOME/mise-root/uv-1.2.3/uv"
        chmod +x "$HOME/mise-root/uv-1.2.3/uv"
        function mise() {
            print -r -- "$*" >> "$HOME/mise-calls.txt"
            case "$*" in
                "env activate zsh")
                    print "export TEST_MISE_ENV_ACTIVATE=1"
                    ;;
                "where uv")
                    print "$HOME/mise-root"
                    ;;
            esac
        }
        source "'"$_RUNTIME_SRC"'"
        printf "%s\n%s" "${TEST_MISE_ENV_ACTIVATE:-0}" "$(command -v uv)"
    '
)
assert_contains "$codex_output" "1"
_TEST_NAME="Codex shell runtime calls mise env activate"
assert_contains "$(cat "$TEST_HOME/runtime-codex/mise-calls.txt")" "env activate zsh"
_TEST_NAME="Codex shell runtime prepends uv binary from mise install"
assert_contains "$codex_output" "$TEST_HOME/runtime-codex/mise-root/uv-1.2.3/uv"

_TEST_NAME="login shells load git wrapper from .zshenv"
fake_dotfiles="$TEST_HOME/projects/skooch"
mkdir -p "$fake_dotfiles/lib/git-cache" "$fake_dotfiles/lib/shell" "$fake_dotfiles/functions"
cp "$_ZSHENV_SRC" "$TEST_HOME/.zshenv"
cp "$_ZPROFILE_SRC" "$TEST_HOME/.zprofile"
ln -s "$fake_dotfiles/functions" "$TEST_HOME/.zsh_functions"
cp "$_REPO_ROOT/functions/git-cache.sh" "$fake_dotfiles/functions/git-cache.sh"
cp "$_REPO_ROOT/functions/git.sh" "$fake_dotfiles/functions/git.sh"
cp "$_RUNTIME_SRC" "$fake_dotfiles/lib/shell/runtime.sh"
cat > "$fake_dotfiles/lib/git-cache/git.sh" <<'EOF'
#!/usr/bin/env zsh
printf 'git:%s\n' "$*" > "$HOME/git-call.txt"
EOF
chmod +x "$fake_dotfiles/lib/git-cache/git.sh"
HOME="$TEST_HOME" zsh -lc 'git clone https://github.com/example/project repo' >/dev/null 2>&1
assert_eq "git:clone https://github.com/example/project repo" "$(cat "$TEST_HOME/git-call.txt")"

_TEST_NAME="login shell startup stays quiet"
quiet_output=$(HOME="$TEST_HOME" zsh -lc 'true' 2>&1)
assert_eq "" "$quiet_output"

_test_summary
