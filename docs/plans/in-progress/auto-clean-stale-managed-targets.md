# Auto-clean stale managed targets and separate informational drift

## Problem

When switching from a profile that manages more targets (e.g. `default` with VSCode/iTerm) to one that manages fewer (e.g. `b`), files written by the previous profile remain on disk. The drift check then permanently nags "Profile(s) 'X' need review" on every new shell with no resolution path — `profile sync`, `profile checkpoint`, and `profile use` all refuse to clear the state.

Two independent issues combine:

1. **Stale managed regular files permanently blocked**: `_profile_prune_stale_managed_targets` (sync.sh:21-55) only auto-removes symlinks and empty directories. Regular files always return status 2 ("requires review"). `_profile_managed_paths_for_record` then re-adds these stale paths to the managed file as long as they exist, ensuring the cycle repeats forever.

2. **Tool inventory mismatches classified as conflicts**: `_profile_record_reconcile_review` (snapshot.sh:106-109) increments `_PROFILE_RECONCILE_CONFLICT_COUNT` for brew/vscode-extension/mise-tool mismatches. These are expected to drift between machines and have no automatic resolution during drift check — they require interactive `profile sync`. But the drift check treats them identically to file conflicts.

Both hit the same gate in `_profile_check_drift` (snapshot.sh:542):
```bash
if (( _PROFILE_RECONCILE_CONFLICT_COUNT > 0 || _PROFILE_RECONCILE_BLOCKED_COUNT > 0 )); then
    echo "Profile(s) '$display' need review..."
```

## Root cause (confirmed)

The profile system has a lifecycle gap: profile switch creates artifacts it cannot clean up. The reconciliation framework doesn't distinguish blocking file conflicts from informational tool inventory drift.

## Classification

**Architectural remediation** — design gap in the profile lifecycle, not a local bug.

## Fix

Two surgical changes to the correct architectural layers:

### Part 1: Auto-clean stale managed files (sync.sh)

In `_profile_prune_stale_managed_targets`, change the regular-file handling (currently lines 48-51):

**Current**: Regular files → "requires review" → status 2 (blocked forever)

**New**: Regular files → compare current md5 against snapshot-local hash:
- **Hash matches** (unmodified since profile wrote it): remove the file, log "Removed stale managed file". Status 1 (changed).
- **Hash doesn't match or no snapshot hash** (user modified it): back up to `$PROFILE_STATE_DIR/backups/<basename>.<timestamp>`, remove original, log "Backed up and removed modified stale target (backup at ...)". Status 1 (changed).
- **Non-empty directories**: same treatment — back up to `$PROFILE_STATE_DIR/backups/<dirname>.<timestamp>/` and remove. Status 1 (changed).

This eliminates the blocked state for stale targets entirely. The profile system created these files; it should clean them up when they become stale.

**Safety**: Modified files are backed up before removal. The backup location is logged. This is strictly better than the current behavior (permanently blocked, no resolution).

### Part 2: Separate informational drift from blocking drift (snapshot.sh, main.sh)

Add a new reconcile category for tool inventory mismatches:

1. **Add** `_PROFILE_RECONCILE_INFO_COUNT` and `_profile_record_reconcile_info` (snapshot.sh)
2. **Change** `_profile_scan_brew_state`, `_profile_scan_vscode_extensions_state`, `_profile_scan_mise_tools_state` to use `_profile_record_reconcile_info` instead of `_profile_record_reconcile_review`
3. **Drift check** (`_profile_check_drift`, snapshot.sh:525-557): no change needed — it already only gates on CONFLICT+BLOCKED, and info items won't increment those counters
4. **Profile status** (`_profile_status`, main.sh): display info items in a separate section ("Informational: N") that doesn't trigger "Run 'profile sync' only after reviewing..."
5. **Sync gating** (`_profile_sync`, main.sh:333-388): info items don't prevent checkpoint update

### Part 3: Fix current state

After deploying the fix, run `profile sync` (or `profile use b`) to auto-clean the 5 stale files and regenerate the drift cache.

## Files changed

| File | Change |
|------|--------|
| `lib/profile/sync.sh` | `_profile_prune_stale_managed_targets`: auto-remove regular files and non-empty dirs with backup |
| `lib/profile/snapshot.sh` | Add `_PROFILE_RECONCILE_INFO_COUNT` + `_profile_record_reconcile_info`; change brew/vscode/mise scan functions to use info |
| `lib/profile/main.sh` | Update `_profile_status` display to show info items separately; update sync gating to not block on info |
| `tests/test_sync.sh` | Update "profile use surfaces blocked stale managed cleanup" test — non-empty dir should be backed up and removed (status 1), not blocked (status 2). Add test for unmodified file auto-removal. Add test for modified file backup+removal. |
| `tests/test_snapshot.sh` | Add test that brew/vscode/mise mismatches don't trigger "needs review" in drift check output |

## Verification

1. Run existing test suite: `./tests/run_tests.sh` (or equivalent)
2. New tests pass for the three stale-file scenarios (unmodified, modified, non-empty dir)
3. New test confirms tool inventory mismatches produce info, not conflict
4. Manual: open new terminal, confirm no drift warning
5. Manual: `profile status` shows clean state (or info-only items)
