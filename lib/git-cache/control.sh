#!/usr/bin/env zsh

set -euo pipefail

dotfiles_dir="${DOTFILES_DIR:-$HOME/projects/skooch}"
setup_bin="${GIT_CACHE_SETUP_BIN:-$dotfiles_dir/lib/git-cache/setup.sh}"
install_prefix="${GIT_CACHE_INSTALL_PREFIX:-$HOME/.local/opt/git-cache-http-server}"
cache_dir="${GIT_CACHE_CACHE_DIR:-$HOME/.cache/git-cache-http-server}"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/git-cache"
disabled_file="${GIT_CACHE_DISABLED_FILE:-$config_dir/disabled}"

usage() {
    cat <<'EOF'
Usage:
  profile cache on
  profile cache off
  profile cache status
  profile cache clear [repo]

Examples:
  profile cache on
  profile cache off
  profile cache clear
  profile cache clear skooch/skooch
  profile cache clear github.com/skooch/skooch.git
  profile cache clear https://github.com/skooch/skooch
EOF
}

cache_enabled() {
    [[ ! -f "$disabled_file" ]]
}

set_cache_enabled() {
    rm -f "$disabled_file"
}

set_cache_disabled() {
    mkdir -p "${disabled_file:h}"
    : > "$disabled_file"
}

cached_repo_paths() {
    if [[ ! -d "$cache_dir" ]]; then
        return 0
    fi

    find "$cache_dir" -mindepth 3 -maxdepth 3 -type d 2>/dev/null | sort
}

print_status() {
    local enabled="yes"
    if ! cache_enabled; then
        enabled="no"
    fi

    local repo_count=0
    if [[ -d "$cache_dir" ]]; then
        repo_count=$(cached_repo_paths | wc -l | awk '{print $1}')
    fi

    local cache_size="0B"
    if [[ -d "$cache_dir" ]]; then
        cache_size=$(du -sh "$cache_dir" 2>/dev/null | awk '{print $1}')
    fi

    echo "Enabled: $enabled"
    echo "Cache dir: $cache_dir"
    echo "Cached repos: $repo_count"
    echo "Cache size: $cache_size"

    local preview
    preview=$(cached_repo_paths | sed "s|^$cache_dir/||" | sed -n '1,5p')
    if [[ -n "$preview" ]]; then
        echo "Cached entries:"
        while IFS= read -r line; do
            [[ -n "$line" ]] && echo "  $line"
        done <<< "$preview"
    fi

    "$setup_bin" status
}

ensure_cache_on() {
    set_cache_enabled
    if [[ -x "$install_prefix/node_modules/.bin/git-cache-http-server" ]]; then
        "$setup_bin" start
    else
        "$setup_bin" setup
    fi
}

ensure_cache_off() {
    set_cache_disabled
    "$setup_bin" stop
}

normalize_repo_spec() {
    local spec="$1"

    spec="${spec%%\?*}"
    spec="${spec%%#*}"
    spec="${spec%/}"

    if [[ "$spec" == http://* || "$spec" == https://* ]]; then
        spec="${spec#*://}"
    elif [[ "$spec" == */* ]]; then
        local first_segment="${spec%%/*}"
        if [[ "$first_segment" != *.* && "$first_segment" != localhost && "$first_segment" != *:* ]]; then
            spec="github.com/$spec"
        fi
    else
        echo "Repo must be owner/repo, host/owner/repo, or an http(s) URL." >&2
        return 1
    fi

    if [[ "$spec" != */* ]]; then
        echo "Repo must include both host and path." >&2
        return 1
    fi

    echo "${spec#/}"
}

clear_all() {
    rm -rf "$cache_dir"
    mkdir -p "$cache_dir"
    echo "Cleared all cached repositories."
}

clear_repo() {
    local normalized
    normalized=$(normalize_repo_spec "$1")

    local base_no_git="${normalized%.git}"
    local -a candidates=("$normalized" "$base_no_git" "$base_no_git.git")
    local -A seen=()
    local -a removed=()

    for candidate in "${candidates[@]}"; do
        [[ -z "$candidate" ]] && continue
        [[ -n "${seen[$candidate]:-}" ]] && continue
        seen[$candidate]=1

        local target="$cache_dir/$candidate"
        if [[ -e "$target" ]]; then
            rm -rf "$target"
            removed+=("${candidate}")
        fi
    done

    if (( ${#removed[@]} == 0 )); then
        echo "No cached repository matched: $1" >&2
        return 1
    fi

    echo "Cleared cached repository entries:"
    for removed_entry in "${removed[@]}"; do
        echo "  $removed_entry"
    done
}

command_name="${1:-status}"
case "$command_name" in
    on)
        ensure_cache_on
        ;;
    off)
        ensure_cache_off
        ;;
    status)
        print_status
        ;;
    clear)
        shift
        if [[ $# -eq 0 ]]; then
            clear_all
        elif [[ $# -eq 1 ]]; then
            clear_repo "$1"
        else
            echo "profile cache clear accepts at most one repo argument." >&2
            exit 1
        fi
        ;;
    help|-h|--help)
        usage
        ;;
    *)
        echo "Unknown cache command: $command_name" >&2
        usage >&2
        exit 1
        ;;
esac
