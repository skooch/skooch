#!/usr/bin/env zsh
# Credential helper for the git cache proxy.
# When git asks for credentials for http://127.0.0.1:<port>, this rewrites
# the request to github.com and delegates to gh auth git-credential.

set -euo pipefail

port="${GIT_CACHE_PORT:-1234}"

action="${1:-}"
[[ "$action" == "get" ]] || exit 0

input=""
while IFS= read -r line; do
    [[ -n "$line" ]] || break
    input+="$line"$'\n'
done

if ! printf '%s' "$input" | grep -q "^host=127\.0\.0\.1:${port}$"; then
    exit 0
fi

printf 'protocol=https\nhost=github.com\n\n' | gh auth git-credential get
