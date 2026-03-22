# Tmux Config Sync

## Summary

Add `~/.tmux.conf` synchronization to the dotfiles profile system. Follows the same copy-based, last-profile-wins pattern used by VSCode keybindings. Supports bidirectional sync via the existing three-way `_profile_sync_config` helper.

## Profile structure

Each profile may optionally contain a tmux config:

```
profiles/
  default/
    tmux/
      tmux.conf
  b/
    tmux/
      tmux.conf    # overrides default
```

Last profile wins: when multiple active profiles have `tmux/tmux.conf`, the last one in profile order is used as the sole source. No merging or concatenation.

## Target

`~/.tmux.conf`

## Apply (`profile use`)

New function `_profile_apply_tmux` in `lib/profile/apply.sh`:

- Walk profiles in order (default first, then named profiles)
- Last profile with `tmux/tmux.conf` wins
- Copy winning file to `~/.tmux.conf`
- Skip silently if no profile has `tmux/tmux.conf`
- Print: `Applying tmux config: <profile_name>`

## Sync (`profile sync`)

New function `_profile_sync_tmux` in `lib/profile/sync.sh`:

- Determine winning profile source (same last-wins logic)
- Call `_profile_sync_config "Tmux" "$HOME/.tmux.conf" "$source" "$source"` for three-way reconciliation
- Handles: profile changed, local changed, both changed (conflict)

## Diff (`profile diff`)

New section in `_profile_diff` in `lib/profile/diff.sh`:

- Determine winning profile source
- Diff against `~/.tmux.conf`
- Display under `=== tmux (~/.tmux.conf) ===`

## Snapshot and tracking

In `lib/profile/helpers.sh`:

- `_profile_snapshot_files`: add `$dir/tmux/tmux.conf`
- `_profile_target_paths`: add `$HOME/.tmux.conf` when any profile has `tmux/tmux.conf`

## Wiring in `main.sh`

- `profile use`: call `_profile_apply_tmux "$active_set"` alongside other apply functions
- `profile sync`: call `_profile_sync_tmux "$active"` alongside other sync functions
- Help text: add "tmux" to the list in the `use` command description

## Out of scope

- TPM plugin management
- Multi-profile merging / concatenation
- Automatic `tmux source-file` reload after apply/sync

## Files modified

1. `lib/profile/apply.sh` -- add `_profile_apply_tmux`
2. `lib/profile/sync.sh` -- add `_profile_sync_tmux`
3. `lib/profile/diff.sh` -- add tmux section to `_profile_diff`
4. `lib/profile/helpers.sh` -- update `_profile_snapshot_files` and `_profile_target_paths`
5. `lib/profile/main.sh` -- wire apply/sync calls, update help text
