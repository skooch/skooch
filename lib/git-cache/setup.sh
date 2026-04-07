#!/usr/bin/env zsh

set -euo pipefail

dotfiles_dir="${DOTFILES_DIR:-$HOME/projects/skooch}"
install_prefix="${GIT_CACHE_INSTALL_PREFIX:-$HOME/.local/opt/git-cache-http-server}"
cache_dir="${GIT_CACHE_CACHE_DIR:-$HOME/.cache/git-cache-http-server}"
port="${GIT_CACHE_PORT:-1234}"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/git-cache"
disabled_file="${GIT_CACHE_DISABLED_FILE:-$config_dir/disabled}"
label="com.skooch.git-cache-http-server"
launch_agent_target="$HOME/Library/LaunchAgents/$label.plist"
systemd_target="$HOME/.config/systemd/user/git-cache-http-server.service"
stale_git_include="$HOME/.config/git/cache.inc"
legacy_github_base="https://github.com/"

usage() {
    cat <<'EOF'
Usage:
  gitcache setup
  gitcache install
  gitcache start
  gitcache stop
  gitcache restart
  gitcache status
  gitcache logs
  gitcache disable
EOF
}

require_npm() {
    if ! command -v npm >/dev/null 2>&1; then
        echo "npm is required. Run mise install first." >&2
        exit 1
    fi
}

write_upstream_gitconfig() {
    local cfg="$install_prefix/upstream.gitconfig"
    local gh_bin
    gh_bin=$(command -v gh 2>/dev/null || true)
    if [[ -n "$gh_bin" ]]; then
        cat > "$cfg" <<EOF
[credential]
	helper = !${gh_bin} auth git-credential
EOF
    else
        echo "warning: gh CLI not found; upstream.gitconfig will have no credential helper" >&2
        : > "$cfg"
    fi
}

install_package() {
    require_npm
    mkdir -p "$install_prefix"
    npm install --prefix "$install_prefix" git-cache-http-server
    command -v node > "$install_prefix/node-path"
    write_upstream_gitconfig
}

remove_legacy_git_include_refs() {
    command -v git >/dev/null 2>&1 || return 0

    local legacy_path
    for legacy_path in "$stale_git_include" "~/.config/git/cache.inc"; do
        git config --global --fixed-value --unset-all include.path "$legacy_path" >/dev/null 2>&1 || true
    done
}

remove_legacy_git_url_rewrites() {
    command -v git >/dev/null 2>&1 || return 0

    local key value
    while read -r key value; do
        [[ -n "$key" ]] || continue
        [[ "$value" == "$legacy_github_base" ]] || continue
        git config --global --fixed-value --unset-all "$key" "$value" >/dev/null 2>&1 || true
    done < <(git config --global --get-regexp '^url\.http://127\.0\.0\.1:[0-9]+/github\.com/\.insteadof$' 2>/dev/null || true)
}

repair_legacy_git_rewrite() {
    rm -f "$stale_git_include"
    remove_legacy_git_include_refs
    remove_legacy_git_url_rewrites
}

install_launch_agent() {
    mkdir -p "$HOME/Library/LaunchAgents"
    cp "$dotfiles_dir/lib/git-cache/com.skooch.git-cache-http-server.plist" "$launch_agent_target"
}

start_launch_agent() {
    launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$(id -u)" "$launch_agent_target"
    launchctl kickstart -k "gui/$(id -u)/$label"
}

stop_launch_agent() {
    launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || true
}

install_systemd_unit() {
    mkdir -p "$(dirname "$systemd_target")"
    cp "$dotfiles_dir/lib/git-cache/git-cache-http-server.service" "$systemd_target"
    systemctl --user daemon-reload
}

start_systemd_unit() {
    systemctl --user enable --now git-cache-http-server.service
}

stop_systemd_unit() {
    systemctl --user disable --now git-cache-http-server.service >/dev/null 2>&1 || true
}

setup_all() {
    install_package
    mkdir -p "$cache_dir"
    repair_legacy_git_rewrite

    if [[ "$OSTYPE" == darwin* ]]; then
        install_launch_agent
        start_launch_agent
    elif command -v systemctl >/dev/null 2>&1; then
        install_systemd_unit
        start_systemd_unit
    else
        echo "No supported service manager found. Start $dotfiles_dir/lib/git-cache/run.sh manually." >&2
        exit 1
    fi
}

show_status() {
    echo "Install prefix: $install_prefix"
    echo "Cache dir: $cache_dir"
    echo "Port: $port"
    if [[ -f "$disabled_file" ]]; then
        echo "Cache mode: disabled"
    else
        echo "Cache mode: enabled"
    fi
    if [[ -x "$install_prefix/node_modules/.bin/git-cache-http-server" ]]; then
        echo "Binary: installed"
    else
        echo "Binary: missing"
    fi
    echo "Git rewrite mode: wrapper-only"

    if [[ "$OSTYPE" == darwin* ]]; then
        launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1 && echo "Service: loaded" || echo "Service: not loaded"
    elif command -v systemctl >/dev/null 2>&1; then
        systemctl --user is-active --quiet git-cache-http-server.service && echo "Service: active" || echo "Service: inactive"
    fi

    lsof -iTCP:"$port" -sTCP:LISTEN -n -P 2>/dev/null || true
}

show_logs() {
    if [[ "$OSTYPE" == darwin* ]]; then
        tail -n 50 "$HOME/Library/Logs/git-cache-http-server.log"
    elif command -v journalctl >/dev/null 2>&1; then
        journalctl --user -u git-cache-http-server.service -n 50 --no-pager
    else
        echo "No log reader configured for this platform." >&2
        exit 1
    fi
}

disable_all() {
    if [[ "$OSTYPE" == darwin* ]]; then
        stop_launch_agent
        rm -f "$launch_agent_target"
    elif command -v systemctl >/dev/null 2>&1; then
        stop_systemd_unit
        rm -f "$systemd_target"
        systemctl --user daemon-reload
    fi

    repair_legacy_git_rewrite
    mkdir -p "$config_dir"
    : > "$disabled_file"
}

command_name="${1:-setup}"
case "$command_name" in
    setup)
        setup_all
        ;;
    install)
        install_package
        ;;
    start)
        repair_legacy_git_rewrite
        if [[ "$OSTYPE" == darwin* ]]; then
            install_launch_agent
            start_launch_agent
        else
            install_systemd_unit
            start_systemd_unit
        fi
        ;;
    stop)
        if [[ "$OSTYPE" == darwin* ]]; then
            stop_launch_agent
        else
            stop_systemd_unit
        fi
        ;;
    restart)
        "$0" stop
        "$0" start
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs
        ;;
    disable)
        disable_all
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        echo "Unknown command: $command_name" >&2
        usage >&2
        exit 1
        ;;
esac
