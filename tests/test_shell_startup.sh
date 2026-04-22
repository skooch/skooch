#!/usr/bin/env zsh

source "${0:A:h}/harness.sh"

_REPO_ROOT="${0:A:h}/.."
_RUNTIME_SRC="$_REPO_ROOT/lib/shell/runtime.sh"
_PYTHON_HELPERS_SRC="$_REPO_ROOT/lib/shell/python.sh"
_PYTHON_WRAPPER_SRC="$_REPO_ROOT/profiles/default/codex/hooks/run-with-python3"
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

_TEST_NAME="shared shell runtime prefers uv python find for an executable python3 path"
python_output=$(
    HOME="$TEST_HOME/runtime-python" PATH="/bin" zsh -c '
        mkdir -p "$HOME/python/bin"
        print "#!/usr/bin/env zsh\nexit 0" > "$HOME/python/bin/python3.14"
        chmod +x "$HOME/python/bin/python3.14"
        PATH="/bin"
        unset _SKOOCH_SHELL_RUNTIME_LOADED SKOOCH_PYTHON3_BIN
        function uv() {
            if [[ "$1" == "python" && "$2" == "find" ]]; then
                print "$HOME/python/bin/python3.14"
                return 0
            fi
            return 1
        }
        source "'"$_RUNTIME_SRC"'"
        if [[ -n "${SKOOCH_PYTHON3_BIN:-}" && -x "${SKOOCH_PYTHON3_BIN}" ]]; then
            printf "%s" "${SKOOCH_PYTHON3_BIN}"
        fi
    '
)
assert_eq "$TEST_HOME/runtime-python/python/bin/python3.14" "$python_output"

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

_TEST_NAME="Claude Code shell runtime enables mise env via CLAUDECODE=1"
claude_output=$(
    HOME="$TEST_HOME/runtime-claude" PATH="/usr/bin:/bin" CLAUDECODE=1 zsh -c '
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
assert_contains "$claude_output" "1"
_TEST_NAME="Claude Code shell runtime calls mise env activate"
assert_contains "$(cat "$TEST_HOME/runtime-claude/mise-calls.txt")" "env activate zsh"
_TEST_NAME="Claude Code shell runtime prepends uv binary from mise install"
assert_contains "$claude_output" "$TEST_HOME/runtime-claude/mise-root/uv-1.2.3/uv"

_TEST_NAME="Codex Python launcher resolves interpreter via uv instead of PATH"
launcher_output=$(
    HOME="$TEST_HOME/runtime-launcher" PATH="/bin" zsh -c '
        unset SKOOCH_PYTHON3_BIN
        fake_dotfiles="$HOME/projects/skooch"
        mkdir -p "$fake_dotfiles/lib/shell" "$fake_dotfiles/profiles/default/codex/hooks" "$HOME/.local/share/mise/shims" "$HOME/.codex/hooks" "$HOME/python/bin"
        cp "'"$_PYTHON_HELPERS_SRC"'" "$fake_dotfiles/lib/shell/python.sh"
        cp "'"$_PYTHON_WRAPPER_SRC"'" "$fake_dotfiles/profiles/default/codex/hooks/run-with-python3"
        chmod +x "$fake_dotfiles/profiles/default/codex/hooks/run-with-python3"
        ln -sf "$fake_dotfiles/profiles/default/codex/hooks/run-with-python3" "$HOME/.codex/hooks/run-with-python3"
        print "#!/usr/bin/env zsh\nif [[ \"\$1\" == \"python\" && \"\$2\" == \"find\" ]]; then\n    print \"$HOME/python/bin/python3.14\"\n    exit 0\nfi\nexit 1" > "$HOME/.local/share/mise/shims/uv"
        chmod +x "$HOME/.local/share/mise/shims/uv"
        print "#!/usr/bin/env zsh\nprint \"$HOME/python/bin/python3.14\"" > "$HOME/python/bin/python3.14"
        chmod +x "$HOME/python/bin/python3.14"
        "$HOME/.codex/hooks/run-with-python3" "$HOME/.codex/hooks/permission_bridge.py" notify
    '
)
assert_eq "$TEST_HOME/runtime-launcher/python/bin/python3.14" "$launcher_output"

_TEST_NAME="login shells load git wrapper from .zshenv"
fake_dotfiles="$TEST_HOME/projects/skooch"
mkdir -p "$fake_dotfiles/lib/git-cache" "$fake_dotfiles/lib/shell" "$fake_dotfiles/functions"
cp "$_ZSHENV_SRC" "$TEST_HOME/.zshenv"
cp "$_ZPROFILE_SRC" "$TEST_HOME/.zprofile"
ln -s "$fake_dotfiles/functions" "$TEST_HOME/.zsh_functions"
cp "$_REPO_ROOT/functions/git-cache.sh" "$fake_dotfiles/functions/git-cache.sh"
cp "$_REPO_ROOT/functions/git.sh" "$fake_dotfiles/functions/git.sh"
cp "$_PYTHON_HELPERS_SRC" "$fake_dotfiles/lib/shell/python.sh"
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
