# Shared shell runtime for login and non-interactive shells.
#
# Keep this file quiet: it is sourced from `.zshenv`, so any output here will
# leak into command results for tools like Codex that use `zsh -lc`.

if [[ -n "${_SKOOCH_SHELL_RUNTIME_LOADED:-}" ]]; then
    return 0
fi
typeset -g _SKOOCH_SHELL_RUNTIME_LOADED=1

_SKOOCH_SHELL_RUNTIME_DIR="${${(%):-%N}:A:h}"
if [[ -f "$_SKOOCH_SHELL_RUNTIME_DIR/python.sh" ]]; then
    source "$_SKOOCH_SHELL_RUNTIME_DIR/python.sh"
fi
unset _SKOOCH_SHELL_RUNTIME_DIR

_skooch_source_command_wrappers() {
    local wrapper
    for wrapper in \
        "$HOME/.zsh_functions"/git-cache.sh(N) \
        "$HOME/.zsh_functions"/git.sh(N)
    do
        source "$wrapper"
    done
}

_skooch_init_shell_runtime() {
    _skooch_source_command_wrappers
    if typeset -f _skooch_activate_mise >/dev/null 2>&1; then
        _skooch_activate_mise
    fi
    if typeset -f _skooch_capture_python3 >/dev/null 2>&1; then
        _skooch_capture_python3
    fi
}

_skooch_init_shell_runtime
