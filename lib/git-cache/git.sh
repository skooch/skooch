#!/usr/bin/env zsh

set -euo pipefail

port="${GIT_CACHE_PORT:-1234}"
cache_base="http://127.0.0.1:${port}/github.com/"
source_base="https://github.com/"
git_bin="${GITCACHE_GIT_BIN:-git}"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/git-cache"
disabled_file="${GIT_CACHE_DISABLED_FILE:-$config_dir/disabled}"

usage() {
    cat <<'EOF'
Usage:
  gitcache setup|install|start|stop|restart|status|logs|disable
  gitcache clone <url> [path]
  gitcache fetch [git args...]
  gitcache pull [git args...]
  gitcache ls-remote [git args...]
  gitcache submodule-update [git submodule update args...]
  gitcache remote-update [git remote update args...]

Notes:
  - Read-only commands route GitHub HTTPS traffic through the local cache.
  - When disabled via profile cache off, these commands fall back to plain git.
  - Pushes are intentionally unsupported through gitcache. Use plain git push.
EOF
}

run_cached_git() {
    if [[ -f "$disabled_file" ]]; then
        "$git_bin" "$@"
    else
        "$git_bin" -c "url.${cache_base}.insteadOf=${source_base}" "$@"
    fi
}

command_name="${1:-help}"
case "$command_name" in
    clone|fetch|pull|ls-remote)
        shift
        run_cached_git "$command_name" "$@"
        ;;
    submodule-update)
        shift
        run_cached_git submodule update "$@"
        ;;
    remote-update)
        shift
        run_cached_git remote update "$@"
        ;;
    help|-h|--help|"")
        usage
        ;;
    push)
        echo "gitcache push is intentionally unsupported. Push directly with git push." >&2
        exit 2
        ;;
    *)
        echo "Unknown gitcache command: $command_name" >&2
        usage >&2
        exit 1
        ;;
esac
