#!/usr/bin/env zsh

set -euo pipefail

dotfiles_dir="${DOTFILES_DIR:-$HOME/projects/skooch}"
install_prefix="${GIT_CACHE_INSTALL_PREFIX:-$HOME/.local/opt/git-cache-http-server}"
cache_dir="${GIT_CACHE_CACHE_DIR:-$HOME/.cache/git-cache-http-server}"
port="${GIT_CACHE_PORT:-1234}"
label="com.skooch.git-cache-http-server"
local_git_include="$HOME/.config/git/cache.inc"
launch_agent_target="$HOME/Library/LaunchAgents/$label.plist"
systemd_target="$HOME/.config/systemd/user/git-cache-http-server.service"

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

write_local_git_include() {
    mkdir -p "$(dirname "$local_git_include")"
    cat > "$local_git_include" <<EOF
[url "http://127.0.0.1:${port}/github.com/"]
	insteadOf = https://github.com/
EOF
}

refresh_profile_git_config() {
    if [[ -f "$dotfiles_dir/lib/profile/index.sh" ]]; then
        source "$dotfiles_dir/lib/profile/index.sh"
        local active
        active=$(_profile_active)
        [[ -z "$active" ]] && active="default"
        _profile_apply_git "$active" >/dev/null
    fi
}

install_package() {
    require_npm
    mkdir -p "$install_prefix"
    npm install --prefix "$install_prefix" git-cache-http-server
    command -v node > "$install_prefix/node-path"
    : > "$install_prefix/upstream.gitconfig"
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
    write_local_git_include
    refresh_profile_git_config

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
    if [[ -x "$install_prefix/node_modules/.bin/git-cache-http-server" ]]; then
        echo "Binary: installed"
    else
        echo "Binary: missing"
    fi
    if [[ -f "$local_git_include" ]]; then
        echo "Git cache include: $local_git_include"
    else
        echo "Git cache include: missing"
    fi

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

    rm -f "$local_git_include"
    refresh_profile_git_config
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
