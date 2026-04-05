git() {
    local subcmd="${1:-}"
    case "$subcmd" in
        clone|fetch|pull|ls-remote)
            gitcache "$@"
            ;;
        submodule)
            case "${2:-}" in
                update)
                    shift 2
                    gitcache submodule-update "$@"
                    ;;
                *)
                    command git "$@"
                    ;;
            esac
            ;;
        remote)
            case "${2:-}" in
                update)
                    shift 2
                    gitcache remote-update "$@"
                    ;;
                *)
                    command git "$@"
                    ;;
            esac
            ;;
        worktree)
            case "${2:-}" in
                add)
                    _git_worktree_add "${@:3}"
                    ;;
                remove|rm)
                    _git_worktree_remove "${@:3}"
                    ;;
                *)
                    command git "$@"
                    ;;
            esac
            ;;
        *)
            command git "$@"
            ;;
    esac
}

# --- Worktree lifecycle helpers ---

_git_worktree_add() {
    # Run the real git worktree add, then bootstrap submodules + cargo isolation
    command git worktree add "$@" || return $?

    # Parse the worktree path from args (first non-flag argument)
    local wt_path=""
    local arg
    for arg in "$@"; do
        case "$arg" in
            -*) ;;
            *)
                if [[ -z "$wt_path" ]]; then
                    wt_path="$arg"
                fi
                ;;
        esac
    done
    [[ -z "$wt_path" ]] && return 0
    wt_path="$(cd "$wt_path" 2>/dev/null && pwd -P)" || return 0

    # Bootstrap submodules via --reference from main checkout
    _git_worktree_bootstrap_submodules "$wt_path"

    # Create cargo target isolation marker
    _git_worktree_cargo_isolate "$wt_path"

    echo ""
    echo "Worktree ready: $wt_path"
    if [[ -f "$wt_path/.mise.toml" ]]; then
        echo "  mise: auto-trusted via trusted_config_paths"
    fi
}

_git_worktree_bootstrap_submodules() {
    local wt_path="$1"
    [[ -f "$wt_path/.gitmodules" ]] || return 0

    local common_git_dir
    common_git_dir="$(cd "$wt_path" && cd "$(command git rev-parse --git-common-dir)" && pwd -P)"

    # If the repo has a bootstrap-submodules script, defer to it
    if [[ -x "$wt_path/scripts/bootstrap-submodules" ]]; then
        echo "Bootstrapping submodules via scripts/bootstrap-submodules..."
        "$wt_path/scripts/bootstrap-submodules" --repo "$wt_path"
        return
    fi

    # Generic: init all submodules, using --reference from main checkout when available
    echo "Bootstrapping submodules..."
    local sub_path
    command git -C "$wt_path" config -f "$wt_path/.gitmodules" --get-regexp '^submodule\..*\.path$' | while IFS= read -r line; do
        sub_path="${line#* }"
        local canonical_gitdir="$common_git_dir/modules/$sub_path"
        if [[ -d "$canonical_gitdir" && ! -f "$canonical_gitdir/shallow" ]]; then
            command git -C "$wt_path" submodule update --init --reference "$canonical_gitdir" -- "$sub_path" 2>/dev/null || \
                command git -C "$wt_path" submodule update --init -- "$sub_path"
        else
            command git -C "$wt_path" submodule update --init -- "$sub_path"
        fi
    done
}

_git_worktree_cargo_isolate() {
    local wt_path="$1"
    [[ -f "$wt_path/Cargo.toml" ]] || return 0

    # Detect shared CARGO_TARGET_DIR from repo .cargo/config.toml
    local cargo_cfg="$wt_path/.cargo/config.toml"
    [[ -f "$cargo_cfg" ]] || return 0

    local python_bin="${SKOOCH_PYTHON3_BIN:-python3}"

    local shared_target=""
    if [[ -x "$python_bin" ]] || command -v "$python_bin" >/dev/null 2>&1; then
        shared_target="$("$python_bin" -c "
import tomllib, sys, os
with open('$cargo_cfg', 'rb') as f:
    d = tomllib.load(f)
td = d.get('build', {}).get('target-dir', '')
if td:
    print(os.path.expanduser(td))
" 2>/dev/null)"
    fi
    [[ -z "$shared_target" ]] && return 0

    local wt_name
    wt_name="$(basename "$wt_path")"
    local isolated_target="$shared_target/worktrees/$wt_name"

    # Write marker file (not a cargo config — won't shadow the tracked one)
    mkdir -p "$wt_path/.cargo"
    echo "$isolated_target" > "$wt_path/.cargo/.worktree-target"
    # Ensure git ignores the marker
    if ! grep -qF '.worktree-target' "$wt_path/.cargo/.gitignore" 2>/dev/null; then
        echo '.worktree-target' >> "$wt_path/.cargo/.gitignore"
    fi
    echo "  cargo target: $isolated_target"
}

_git_worktree_remove() {
    # Parse path from args (first non-flag argument)
    local wt_path="" delete_branch=false force=false
    local args=()
    local arg
    for arg in "$@"; do
        case "$arg" in
            --delete-branch) delete_branch=true ;;
            --force|-f) force=true; args+=("$arg") ;;
            -*) args+=("$arg") ;;
            *)
                if [[ -z "$wt_path" ]]; then
                    wt_path="$arg"
                fi
                args+=("$arg")
                ;;
        esac
    done
    [[ -z "$wt_path" ]] && { command git worktree remove "$@"; return $?; }

    # Resolve to absolute path
    local abs_wt_path
    abs_wt_path="$(cd "$wt_path" 2>/dev/null && pwd -P)" || abs_wt_path="$wt_path"

    # Detect branch before removal
    local branch=""
    if [[ -d "$abs_wt_path/.git" || -f "$abs_wt_path/.git" ]]; then
        branch="$(command git -C "$abs_wt_path" rev-parse --abbrev-ref HEAD 2>/dev/null)"
    fi

    # Read cargo target marker before removal
    local cargo_target=""
    if [[ -f "$abs_wt_path/.cargo/.worktree-target" ]]; then
        cargo_target="$(cat "$abs_wt_path/.cargo/.worktree-target")"
    fi

    # Deinit submodules so git worktree remove succeeds
    if [[ -f "$abs_wt_path/.gitmodules" ]]; then
        command git -C "$abs_wt_path" submodule deinit --all --force 2>/dev/null
    fi

    # Try proper removal first
    if ! command git worktree remove "${args[@]}" 2>/dev/null; then
        # Fallback: rm + prune
        echo "git worktree remove failed, falling back to rm + prune"
        rm -rf "$abs_wt_path"
        command git worktree prune
    fi

    # Clean up branch
    if [[ "$delete_branch" == true && -n "$branch" && "$branch" != "HEAD" ]]; then
        if $force; then
            command git branch -D "$branch" 2>/dev/null && echo "Deleted branch $branch"
        else
            command git branch -d "$branch" 2>/dev/null && echo "Deleted branch $branch"
        fi
    fi

    # Clean up isolated cargo target
    if [[ -n "$cargo_target" && -d "$cargo_target" ]]; then
        echo "Cleaning cargo target: $cargo_target"
        rm -rf "$cargo_target"
    fi
}

trifecta() {
    git add -u
    git commit --amend --no-edit
    git push --force
}
