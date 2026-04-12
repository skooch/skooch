# git-cache-http-server

This setup keeps GitHub HTTPS reads behind a local cache without changing persistent Git remotes. In interactive shells, the `git` function automatically routes safe read commands through the cache wrapper.

## What it manages

- `~/.local/opt/git-cache-http-server` for the npm-installed daemon
- `~/.cache/git-cache-http-server` for cached repository data
- a user service:
  - macOS: `~/Library/LaunchAgents/com.skooch.git-cache-http-server.plist`
  - Linux: `~/.config/systemd/user/git-cache-http-server.service`

## Commands

```sh
profile cache on
profile cache off
profile cache status
profile cache clear
profile cache clear skooch/skooch

gitcache logs
gitcache restart
gitcache disable
```

`profile cache on` installs the daemon if needed, enables the user service, turns cache-aware Git wrappers on for this machine, and scrubs the legacy persistent GitHub rewrite from older cache setups. `profile cache off` disables the wrappers, removes that obsolete rewrite if it still exists, and stops the service cleanly. `profile cache clear` removes cached repo data without touching your working clones.

## Interactive shell behavior

- `git clone`, `git fetch`, `git pull`, `git ls-remote`, `git submodule update`, and `git remote update` automatically use the cache wrapper in interactive shells when the cache is enabled.
- `git push` and other write or non-read commands go straight to real Git.
- `command git ...` bypasses the shell wrapper explicitly.
- `profile status` and `profile sync` can refresh dotfiles remote metadata through the same wrapper when the local remote cache is stale.

## Current scope

- caches GitHub HTTPS reads via `http://127.0.0.1:1234/github.com/`
- leaves normal `git push` behavior untouched
- can be toggled with `profile cache on|off` without rewriting persistent remotes
- can clear all cached data or targeted repos with `profile cache clear [repo]`
- leaves other hosts unchanged until they are explicitly added
- complements repo-side submodule helpers, but does not deduplicate linked-worktree submodule object stores

## Profile sync interaction

- `profile status` uses the refreshed remote metadata to tell the difference between a stale checkpoint, safe auto-sync actions, and upstream states that need review.
- `profile sync` will fast-forward a clean repo when it is only behind upstream, but it refuses to guess through divergence or through a dirty-behind worktree.
