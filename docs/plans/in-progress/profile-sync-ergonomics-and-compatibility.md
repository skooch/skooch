# Plan: Profile Sync Ergonomics And Compatibility

## Goal
Make profile sync trustworthy by separating checkpoint status from reconcile work, adding remote-aware and ownership-aware sync decisions, and making every managed config path explicitly multi-profile compatible.

## Current Phase
Phase 4

## File Map
- Modify: `lib/profile/helpers.sh` (add managed-path policy registry, compatibility metadata, and classification helpers)
- Modify: `lib/profile/snapshot.sh` (split checkpoint state from drift detection and add remote freshness reporting)
- Modify: `lib/profile/main.sh` (surface clearer status output and wire sync through a preflight flow)
- Modify: `lib/profile/sync.sh` (auto-apply safe sync paths, block unsafe sync-back paths, and respect compatibility policies)
- Modify: `lib/profile/apply.sh` (keep apply behavior aligned with the new compatibility and ownership rules)
- Modify: `tests/test_snapshot.sh` (cover checkpoint drift, stale snapshot messaging, and remote freshness decisions)
- Modify: `tests/test_sync.sh` (cover ownership-aware sync behavior and conflict gating)
- Modify: `tests/test_sync_peritem.sh` (cover automatic safe actions and prompts only for ambiguous per-item changes)
- Create: `tests/test_profile_status.sh` (cover user-facing status and sync-preflight messaging)
- Modify: `INSTALL.md` (document the new status/checkpoint model and when sync is automatic versus interactive)
- Modify: `docs/git-cache-http-server.md` (document the remote fetch preflight assumptions and cache interaction)
- Create: `docs/plans/new/profile-sync-ergonomics-and-compatibility.md` (tracked execution plan)

## Phases

### Phase 1: Define Managed Path Policies And Compatibility Rules
- [x] Inventory every managed path class in `lib/profile/helpers.sh` and assign an explicit policy: `canonical_symlink`, `single_owner_sync_back`, `merged_output_no_sync_back`, `union_collection`, or `apply_only`.
- [x] Add helper functions in `lib/profile/helpers.sh` that return the policy, sync-back eligibility, and multi-profile compatibility requirements for a managed path before any sync logic makes decisions.
- [x] Rework path declarations in `lib/profile/helpers.sh` and `lib/profile/sync.sh` so each current config type is represented through the new policy helpers instead of ad hoc branching.
- [x] Identify every currently managed config that is not truly multi-profile compatible, and define a concrete compatible form for each in `lib/profile/helpers.sh` and `lib/profile/sync.sh`:
- [x] `git/config` remains `apply_only` and is never sync-backed from `~/.gitconfig`.
- [x] `mise/config.toml`, `codex/config.toml`, `codex/hooks.json`, `claude/settings.json`, `vscode/settings.json`, and `iterm/profile.json` now use explicit structured policy handling, with merged multi-profile outputs blocked from blind sync-back.
- [x] `vscode/keybindings.json`, `tmux/tmux.conf`, `claude/CLAUDE.md`, `claude/system-prompt.md`, `claude/statusline.sh`, `claude/sync-plugins.sh`, `claude/read-once/hook.sh`, and `codex/rules/default.rules` now flow through explicit single-owner policy handling.
- [x] `Brewfile`, `vscode/extensions.txt`, `codex/hooks/*`, `codex/agents/*.toml`, `claude/hooks/*.sh`, `claude/commands/*.md`, and routed skills remain unioned collections with explicit non-auto-sync behavior.
- **Status:** complete

### Phase 2: Split Checkpoint State From Reconcile Warnings
- [x] Add a checkpoint concept in `lib/profile/snapshot.sh` that records the last acknowledged managed state separately from the current reconcile snapshot used by sync direction detection.
- [x] Update `lib/profile/main.sh` and `lib/profile/snapshot.sh` to report distinct states instead of one generic warning: in sync, checkpoint stale but no reconcile needed, local changes safe to auto-sync, remote freshness unknown, upstream updates available, and conflict requiring user input.
- [x] Teach status reporting to treat canonical symlinked files as already canonical when the live target resolves to the profile source, so editing the live path does not automatically imply a risky reconcile.
- [x] Add coverage in `tests/test_snapshot.sh` and `tests/test_profile_status.sh` for the new state categories and for the current false-positive case where only canonical profile sources changed through symlinked targets.
- **Status:** complete

### Phase 3: Add Remote-Aware Sync Preflight And Safe Automation
- [x] Add a sync preflight in `lib/profile/main.sh` and `lib/profile/snapshot.sh` that fetches remote metadata before status or sync decisions when freshness is unknown, using the existing git-cache wrapper behavior when available.
- [x] Classify preflight outcomes in `lib/profile/main.sh`: clean and current, local-only changes, upstream-only changes, non-conflicting fast-forward plus safe local sync, and divergence requiring explicit user choice.
- [x] Update `lib/profile/sync.sh` so non-conflicting changes in `canonical_symlink`, `single_owner_sync_back`, and approved file-config cases are applied automatically, while `merged_output_no_sync_back` and unresolved multi-profile ownership cases stop with a targeted prompt instead of a generic sync request.
- [x] Prevent sync-back to profile sources when the active config type lacks a defined multi-profile-compatible representation, and surface the exact path class and reason in status output.
- [x] Add tests in `tests/test_sync.sh`, `tests/test_sync_peritem.sh`, `tests/test_profile_status.sh`, and `tests/test_remote_preflight.sh` for automatic safe sync, stale checkpoint handling, and upstream-behind preflight behavior.
- **Status:** complete

### Phase 4: Verify, Document, And Roll Out
- [x] Run `./tests/test_snapshot.sh`, `./tests/test_sync.sh`, `./tests/test_sync_peritem.sh`, `./tests/test_profile_status.sh`, `./tests/test_remote_preflight.sh`, and `./tests/test_module_loading.sh` after the implementation changes land.
- [x] Update `INSTALL.md` and `docs/git-cache-http-server.md` so the user model matches the new behavior: checkpoint warnings are informational, safe sync is automatic, and prompts only appear for real ownership or merge conflicts.
- [ ] Validate the live `default` profile flow manually with `profile status` and `profile sync` in a dirty-but-non-conflicting scenario before marking the work complete.
- **Status:** in_progress

## Decisions
| Decision | Rationale |
|----------|-----------|
| Treat managed path classification as the foundation for the rest of the work | The current warning and sync UX are confusing because different config classes share one generic drift signal. |
| Keep remote fetch as preflight instead of a background shell-startup side effect | Status and sync decisions need fresh remote facts, but shell startup should stay cheap and predictable. |
| Block sync-back for config types without a defined multi-profile representation | Preventing wrong-profile writes is more important than maximizing automation on ambiguous config types. |
| Leave the plan in `in-progress` until a live `profile sync` smoke test is explicitly safe to run | The code and tests are complete, but running `profile sync` in the user’s real environment could make unreviewed changes to active profile-managed files. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
