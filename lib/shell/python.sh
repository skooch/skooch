# Shared Python resolver for interactive shells, hooks, and shell tooling.
#
# Keep this file quiet: it may be sourced from `.zshenv` and direct hook
# launchers, so any output here will leak into callers.

if [[ -n "${_SKOOCH_PYTHON_HELPERS_LOADED:-}" ]]; then
    return 0
fi
typeset -g _SKOOCH_PYTHON_HELPERS_LOADED=1

_skooch_in_codex_shell() {
    case ":$PATH:" in
        *:/Applications/Codex.app/Contents/Resources:*|*:/Users/skooch/.codex/tmp/arg0/codex-arg0:*)
            return 0
            ;;
    esac
    return 1
}

_skooch_activate_mise() {
    local path_changed=false

    local mise_shims="$HOME/.local/share/mise/shims"
    if [[ -d "$mise_shims" ]]; then
        typeset -gU path PATH
        path=("$mise_shims" $path)
        path_changed=true
    fi

    if ! command -v mise >/dev/null 2>&1; then
        [[ "$path_changed" == true ]] && rehash
        return 0
    fi
    if ! _skooch_in_codex_shell; then
        [[ "$path_changed" == true ]] && rehash
        return 0
    fi

    local mise_env=""
    mise_env="$(mise env activate zsh 2>/dev/null)" || return 0
    [[ -n "$mise_env" ]] && eval "$mise_env"

    local uv_root=""
    uv_root="$(mise where uv 2>/dev/null)"
    [[ -n "$uv_root" ]] || return 0

    local uv_dir
    for uv_dir in "$uv_root"/uv-*(N); do
        if [[ -x "$uv_dir/uv" ]]; then
            typeset -gU path PATH
            path=("$uv_dir" $path)
            path_changed=true
            break
        fi
    done

    [[ "$path_changed" == true ]] && rehash
}

_skooch_find_python3() {
    local real_python=""

    if command -v uv >/dev/null 2>&1; then
        real_python="$(uv python find 2>/dev/null)" || return 1
        [[ -x "$real_python" ]] && {
            printf "%s" "$real_python"
            return 0
        }
    fi

    local python_cmd=""
    python_cmd="$(command -v python3 2>/dev/null)" || return 1

    real_python="$("$python_cmd" -c 'import sys; print(sys.executable)' 2>/dev/null)" || return 1
    [[ -x "$real_python" ]] || return 1

    printf "%s" "$real_python"
}

_skooch_python3_bin() {
    if [[ -n "${SKOOCH_PYTHON3_BIN:-}" && -x "${SKOOCH_PYTHON3_BIN}" ]]; then
        printf "%s" "${SKOOCH_PYTHON3_BIN}"
        return 0
    fi

    _skooch_activate_mise

    local real_python=""
    real_python="$(_skooch_find_python3)" || return 1
    [[ -x "$real_python" ]] || return 1

    printf "%s" "$real_python"
}

_skooch_capture_python3() {
    [[ -n "${SKOOCH_PYTHON3_BIN:-}" && -x "${SKOOCH_PYTHON3_BIN}" ]] && return 0

    local real_python=""
    real_python="$(_skooch_python3_bin)" || return 0

    export SKOOCH_PYTHON3_BIN="$real_python"
}
