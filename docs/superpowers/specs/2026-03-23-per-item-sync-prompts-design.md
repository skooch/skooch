# Per-Item Sync Prompts for List-Based Syncs

**Date:** 2026-03-23
**Status:** Review

## Problem

`profile sync` only adds — it installs missing packages and adds new local packages to the profile. There is no way to remove items through sync. If you uninstall a brew package or remove a line from a Brewfile on another machine, sync will undo your change by reinstalling or re-adding it.

## Scope

List-based syncs only:
- **Brew** — formulae and casks (not taps)
- **VSCode extensions**
- **Mise tools**

Config-file syncs (settings.json, keybindings, git config, iTerm) already handle bidirectional changes via three-way merge and are unchanged.

## Design

Replace the current bulk "Apply? [Y/n]" prompt with per-item interactive prompts. Each out-of-sync item gets its own prompt with the option to sync in either direction or skip.

### In profile but not installed

```
  brew:ripgrep — not installed
    [I]nstall / [R]emove from profile / [S]kip? [I]
```

- **I (default):** Install the package (current behavior)
- **R:** Delete the entry from the Brewfile/extensions.txt/mise config
- **S:** Do nothing, leave the mismatch

### Installed but not in profile

```
  brew:wget — not in profile
    [A]dd to profile / [U]ninstall / [S]kip? [A]
```

- **A (default):** Add to the appropriate profile file (current behavior, including the profile picker for multi-profile setups)
- **U:** Uninstall the package
- **S:** Do nothing, leave the mismatch

### "In sync" message

When all items match, still print `Brew: in sync` / `VSCode extensions: in sync` / `Mise: in sync`.

## Per-Sync Details

### Brew (`_profile_sync_brew`)

**Source tracking:** When reading packages from profile Brewfiles, track which source file each entry came from (e.g. `brew:ripgrep` → `profiles/default/Brewfile`). This is needed so the Remove action targets the correct file. Add a new function `_profile_read_brew_packages_sourced` that emits `type:name\tfile` pairs (no `sort -u` dedup). If a package appears in multiple Brewfiles, the Remove action removes it from all files that contain it. The same source-tracking pattern applies to VSCode extensions and mise tools.

**Inactive profile filtering:** The existing `_profile_read_all_brew_packages` check is retained — packages belonging to inactive profiles are excluded from the "installed but not in profile" list, so the user isn't prompted about packages managed by profiles they aren't using.

**Remove from profile (R):**
- Use the tracked source file to target the correct Brewfile
- Match using pattern `^[[:space:]]*(brew|cask)[[:space:]]+"name"` (aligned with the existing parsing regex in `_profile_read_brew_packages`). The name must be escaped for regex metacharacters before interpolation (use `sed` with fixed-string quoting or escape dots/plus signs).
- Delete the matched line. If the line has a trailing comment, delete the whole line.
- Handle lines with options like `brew "ollama", restart_service: :changed` — match on the name portion
- If the line is inside an `if OS.mac?` / `if OS.linux?` block, delete only the line (not the block). If the block becomes empty after removal (no remaining non-blank, non-comment lines between `if` and `end`), delete the entire `if`/`end` block. Use a small helper function for this rather than a single sed command.
- Removal only targets lines visible to the current OS (consistent with the read logic in `_profile_read_brew_packages`)

**Uninstall (U):**
- Use the `brew:`/`cask:` prefix (already present in the internal representation, used throughout the sync logic) to dispatch the correct command
- `brew:` items → `brew uninstall <name>`
- `cask:` items → `brew uninstall --cask <name>`

**Taps:** Excluded from per-item prompts. Taps are managed implicitly by brew when installing formulae that need them.

**Post-brew hook:** `_profile_post_brew` runs once after all per-item brew actions are complete, only if at least one install or uninstall action was taken.

**Profile picker:** When adding to profile and multiple profiles are active, reuse the existing `_profile_pick_target` prompt (asked once for the batch of adds, not per-item). All adds in one sync run go to the same target profile — fine-grained per-item profile selection requires manual editing.

### VSCode Extensions (`_profile_sync_vscode`)

**Remove from profile (R):**
- Find and delete the extension ID line from the correct extensions.txt file

**Uninstall (U):**
- Run `<cli> --uninstall-extension <ext-id>` for each VS Code instance. Failures are logged but non-fatal (consistent with the install path which uses `2>/dev/null`).

**Profile picker:** Same as brew — ask once for the batch of adds.

### Mise Tools (`_profile_sync_mise`)

**Current state:** Mise sync uses custom section-based TOML merging (parsing sections, deduplicating keys) and then delegates the merged result to `_profile_sync_config` for three-way sync. To support per-item prompts, the `[tools]` section needs list-based handling while the rest keeps three-way merge.

**Two-pass approach:**

1. **Tools section (list-based):** Extract tool names from `[tools]` in each profile's config.toml. Compare against installed tools. Present per-item prompts. Apply changes directly to the source profile files.
2. **Non-tools sections (three-way merge):** The existing merge logic in `_profile_sync_mise` (section parsing, key deduplication) is reused but filters out the `[tools]` section. The merged non-tools output is synced via `_profile_sync_config`.

**Splitting the file:** A helper `_profile_mise_split_tools` extracts lines belonging to `[tools]` vs everything else, using simple line-based parsing — lines between `[tools]` and the next `[section]` header (or EOF) belong to tools. Comments within `[tools]` are kept with that section.

**Reassembly:** After both passes, the target `config.toml` is reconstructed preserving the original section order. Track an ordered list of section headers as they're encountered during parsing (zsh associative arrays don't preserve order). The tools section in the target is always regenerated from the profile sources to stay consistent.

**Snapshot:** The snapshot continues to hash the entire merged config.toml. The two-pass split is internal to the sync logic only — from the snapshot's perspective, it's still one file.

**Read installed tools:** `mise ls --installed --json` returns tool+version pairs. Extract just the tool names (e.g., `node`, `ruby`).

**Read expected tools:** Parse `[tools]` section lines as `<tool> = "<spec>"` from each profile's config.toml. Collect as a name→spec map. Track source file for each tool (same as brew source tracking).

**Version comparison:** Compare by tool name only, not version. If `node` is in the profile and `node` is installed, it's "in sync" regardless of whether the profile says `"lts"` and the installed version is `22.1.0`. Mise's version resolution (aliases like `lts`, `latest`, `stable`) makes exact comparison impractical — mise itself handles version pinning.

**Remove from profile (R):**
- Use the tracked source file to target the correct profile's config.toml
- Delete the `<tool>[[:space:]]*=` line from the `[tools]` section

**Uninstall (U):**
- Run `mise uninstall <tool>` (uninstalls all versions of that tool)

**Non-tools sections:** Continue using the existing section-merge logic + `_profile_sync_config` for three-way sync.

## Implementation Notes

### Helper: `_profile_prompt_item`

Extract a shared helper for the interactive prompt to avoid duplicating the prompt logic across brew/vscode/mise:

```
_profile_prompt_item <label> <direction>
# direction: "not_installed" | "not_in_profile"
# Returns: "install" | "remove" | "add" | "uninstall" | "skip"
```

Invalid input re-prompts. Empty input selects the default shown in brackets.

### Removing lines from profile files

Extract a helper to delete a line from a profile file by pattern:

```
_profile_remove_line <file> <pattern>
# Uses sed to delete the first matching line
```

For Brewfile, pattern: `^[[:space:]]*(brew|cask)[[:space:]]+"name"`. For extensions.txt, exact line match. For mise config.toml, `^tool_name[[:space:]]*=`.

### Batching profile-target selection

Prompt all per-item choices first, collecting the set of items to add. Then, if any items were marked [A]dd, invoke `_profile_pick_target` once for the batch. This avoids asking the profile question when the user ends up skipping all adds.

### Ordering

Show items grouped by direction:
1. First: all "in profile but not installed" items
2. Then: all "installed but not in profile" items

Within each group, alphabetical by name.

### Skip-all summary

If all items are skipped (no installs, no removes, no adds, no uninstalls), print "No changes applied." instead of silently returning.

## What stays the same

- `profile use` — continues to call the install-only apply path, not affected by per-item prompts
- Config-file three-way sync
- Snapshot and commit/push flow
- Tap handling
- `_profile_pick_target` for multi-profile adds

## Files to modify

- `lib/profile/sync.sh` — main changes to `_profile_sync_brew`, `_profile_sync_vscode`, `_profile_sync_mise`
- `lib/profile/helpers.sh` — add `_profile_prompt_item` and `_profile_remove_line` helpers
