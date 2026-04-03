#!/usr/bin/env zsh

set -euo pipefail

install_prefix="${GIT_CACHE_INSTALL_PREFIX:-$HOME/.local/opt/git-cache-http-server}"
cache_dir="${GIT_CACHE_CACHE_DIR:-$HOME/.cache/git-cache-http-server}"
port="${GIT_CACHE_PORT:-1234}"
node_path_file="$install_prefix/node-path"
upstream_git_config="$install_prefix/upstream.gitconfig"
entrypoint="$install_prefix/node_modules/git-cache-http-server/bin/git-cache-http-server.js"

if [[ ! -f "$entrypoint" ]]; then
    echo "git-cache-http-server is not installed at $entrypoint" >&2
    exit 1
fi

node_binary=""
if [[ -f "$node_path_file" ]]; then
    node_binary=$(<"$node_path_file")
fi
if [[ -z "$node_binary" || ! -x "$node_binary" ]]; then
    node_binary=$(command -v node || true)
fi
if [[ -z "$node_binary" || ! -x "$node_binary" ]]; then
    echo "node is not available for git-cache-http-server" >&2
    exit 1
fi

mkdir -p "$cache_dir"
touch "$upstream_git_config"
export GIT_CONFIG_GLOBAL="$upstream_git_config"
export GIT_CONFIG_NOSYSTEM=1
exec "$node_binary" "$entrypoint" --port "$port" --cache-dir "$cache_dir"
