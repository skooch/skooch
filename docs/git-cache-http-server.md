# git-cache-http-server

This setup keeps GitHub HTTPS clones and fetches behind a local cache without requiring per-repo URL changes.

## What it manages

- `~/.local/opt/git-cache-http-server` for the npm-installed daemon
- `~/.cache/git-cache-http-server` for cached repository data
- `~/.config/git/cache.inc` for the GitHub URL rewrite
- a user service:
  - macOS: `~/Library/LaunchAgents/com.skooch.git-cache-http-server.plist`
  - Linux: `~/.config/systemd/user/git-cache-http-server.service`

## Commands

```sh
gitcache setup
gitcache status
gitcache logs
gitcache restart
gitcache disable
```

`gitcache setup` installs the daemon, writes the local Git include, refreshes `~/.gitconfig` through the profile system, and enables the user service.

## Current scope

- caches GitHub HTTPS traffic via `http://127.0.0.1:1234/github.com/`
- leaves other hosts unchanged until they are explicitly added
- complements repo-side submodule helpers, but does not deduplicate linked-worktree submodule object stores
