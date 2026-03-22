# Tmux Config Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `~/.tmux.conf` synchronization to the dotfiles profile system with apply, sync, and diff support.

**Architecture:** Follows the existing last-profile-wins copy pattern (like VSCode keybindings). Uses the existing `_profile_sync_config` three-way helper for bidirectional sync. Each profile may optionally contain `tmux/tmux.conf`.

**Tech Stack:** zsh, existing profile system in `lib/profile/`

**Spec:** `docs/superpowers/specs/2026-03-22-tmux-config-sync-design.md`

---

### Task 1: Update snapshot/tracking in helpers.sh

**Files:**
- Modify: `lib/profile/helpers.sh:119-129` (`_profile_snapshot_files`)
- Modify: `lib/profile/helpers.sh:146-201` (`_profile_target_paths`)
- Test: `tests/test_helpers.sh`

- [ ] **Step 1: Write failing test for snapshot_files**

Add to `tests/test_helpers.sh`, after the `snapshot_files includes Brewfile` test (line 47):

```bash
_TEST_NAME="snapshot_files includes tmux/tmux.conf"
assert_contains "$snap_files" "tmux/tmux.conf"
```

Note: `$snap_files` is already defined on line 31 as `$(_profile_snapshot_files "$PROFILES_DIR/default")`.

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run.sh test_helpers`
Expected: FAIL on "snapshot_files includes tmux/tmux.conf"

- [ ] **Step 3: Add tmux to _profile_snapshot_files**

In `lib/profile/helpers.sh`, in the `_profile_snapshot_files` function, add `"$dir/tmux/tmux.conf"` to the for loop after `"$dir/claude/settings.json"`:

```bash
_profile_snapshot_files() {
    local dir="$1"
    for f in "$dir/Brewfile" "$dir/vscode/extensions.txt" \
             "$dir/vscode/settings.json" "$dir/vscode/keybindings.json" \
             "$dir/iterm/profile.json" \
             "$dir/git/config" "$dir/mise/config.toml" \
             "$dir/claude/settings.json" \
             "$dir/tmux/tmux.conf"; do
        echo "$f"
    done
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/run.sh test_helpers`
Expected: all PASS

- [ ] **Step 5: Write failing test for target_paths**

Add to `tests/test_helpers.sh`, after the `target_paths includes claude settings` test (line 154):

```bash
_TEST_NAME="target_paths includes tmux.conf when tmux/tmux.conf exists"
mkdir -p "$PROFILES_DIR/default/tmux"
echo "set -g mouse on" > "$PROFILES_DIR/default/tmux/tmux.conf"
local tmux_targets=$(_profile_target_paths "default")
assert_contains "$tmux_targets" ".tmux.conf"
```

- [ ] **Step 6: Run test to verify it fails**

Run: `./tests/run.sh test_helpers`
Expected: FAIL on "target_paths includes tmux.conf when tmux/tmux.conf exists"

- [ ] **Step 7: Add tmux to _profile_target_paths**

In `lib/profile/helpers.sh`, in `_profile_target_paths`, add a tmux section after the Claude Code section and before the iTerm section:

```bash
    # Tmux
    local has_tmux=false
    [[ -f "$PROFILES_DIR/default/tmux/tmux.conf" ]] && has_tmux=true
    for p in ${=profiles}; do
        [[ -f "$PROFILES_DIR/$p/tmux/tmux.conf" ]] && has_tmux=true
    done
    [[ "$has_tmux" == "true" ]] && paths+=("$HOME/.tmux.conf")
```

- [ ] **Step 8: Run tests to verify all pass**

Run: `./tests/run.sh test_helpers`
Expected: all PASS

- [ ] **Step 9: Commit**

```bash
git add lib/profile/helpers.sh tests/test_helpers.sh
git commit -m "feat(tmux): add tmux to snapshot files and target paths"
```

---

### Task 2: Add _profile_apply_tmux in apply.sh

**Files:**
- Modify: `lib/profile/apply.sh` (add function at end)
- Test: `tests/test_apply.sh`

- [ ] **Step 1: Write failing tests**

Add to `tests/test_apply.sh`, before `_test_summary` (line 62):

```bash
# --- _profile_apply_tmux ---

_TEST_NAME="apply_tmux copies winning profile tmux.conf to home"
mkdir -p "$PROFILES_DIR/default/tmux"
echo "set -g mouse on" > "$PROFILES_DIR/default/tmux/tmux.conf"
_profile_apply_tmux "default" > /dev/null 2>&1
assert_eq "set -g mouse on" "$(cat "$TEST_HOME/.tmux.conf")"

_TEST_NAME="apply_tmux last profile wins"
mkdir -p "$PROFILES_DIR/testprofile/tmux"
echo "set -g mouse off" > "$PROFILES_DIR/testprofile/tmux/tmux.conf"
_profile_apply_tmux "testprofile" > /dev/null 2>&1
assert_eq "set -g mouse off" "$(cat "$TEST_HOME/.tmux.conf")"

_TEST_NAME="apply_tmux skips when no tmux config exists"
rm -rf "$PROFILES_DIR/default/tmux" "$PROFILES_DIR/testprofile/tmux"
rm -f "$TEST_HOME/.tmux.conf"
_profile_apply_tmux "default" > /dev/null 2>&1
assert_eq "1" "$([[ ! -f "$TEST_HOME/.tmux.conf" ]] && echo 1 || echo 0)"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/run.sh test_apply`
Expected: FAIL — `_profile_apply_tmux` not defined

- [ ] **Step 3: Implement _profile_apply_tmux**

Add to the end of `lib/profile/apply.sh`:

```bash
# --- Tmux ---

_profile_apply_tmux() {
    local profiles="$1"
    local target="$HOME/.tmux.conf"

    # Last profile wins
    local source=""
    local source_profile=""
    [[ -f "$PROFILES_DIR/default/tmux/tmux.conf" ]] && { source="$PROFILES_DIR/default/tmux/tmux.conf"; source_profile="default"; }
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        if [[ -f "$PROFILES_DIR/$p/tmux/tmux.conf" ]]; then
            source="$PROFILES_DIR/$p/tmux/tmux.conf"
            source_profile="$p"
        fi
    done

    [[ -z "$source" ]] && return 0

    cp "$source" "$target"
    echo "Applying tmux config: $source_profile"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/run.sh test_apply`
Expected: all PASS

- [ ] **Step 5: Commit**

```bash
git add lib/profile/apply.sh tests/test_apply.sh
git commit -m "feat(tmux): add _profile_apply_tmux"
```

---

### Task 3: Add _profile_sync_tmux in sync.sh

**Files:**
- Modify: `lib/profile/sync.sh` (add function at end)
- Test: `tests/test_sync.sh`

- [ ] **Step 1: Write failing test**

Add to `tests/test_sync.sh`, before `_test_summary` (line 137):

```bash
# --- _profile_sync_tmux ---

_TEST_NAME="sync_tmux delegates to sync_config with winning source"
mkdir -p "$PROFILES_DIR/default/tmux"
echo "set -g mouse on" > "$PROFILES_DIR/default/tmux/tmux.conf"
echo "set -g mouse on" > "$TEST_HOME/.tmux.conf"
printf '%s\t%s\n' "$TEST_HOME/.tmux.conf" "$(_platform_md5 "$TEST_HOME/.tmux.conf")" >> "$PROFILE_STATE_DIR/snapshot-local"
_profile_sync_tmux "default" > /dev/null 2>&1
assert_eq "0" "$?"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run.sh test_sync`
Expected: FAIL — `_profile_sync_tmux` not defined

- [ ] **Step 3: Implement _profile_sync_tmux**

Add to the end of `lib/profile/sync.sh`:

```bash
_profile_sync_tmux() {
    local profiles="$1"
    local target="$HOME/.tmux.conf"

    # Last profile wins
    local source=""
    [[ -f "$PROFILES_DIR/default/tmux/tmux.conf" ]] && source="$PROFILES_DIR/default/tmux/tmux.conf"
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        [[ -f "$PROFILES_DIR/$p/tmux/tmux.conf" ]] && source="$PROFILES_DIR/$p/tmux/tmux.conf"
    done
    [[ -z "$source" ]] && return 0

    _profile_sync_config "Tmux" "$target" "$source" "$source"
}
```

- [ ] **Step 4: Run tests to verify all pass**

Run: `./tests/run.sh test_sync`
Expected: all PASS

- [ ] **Step 5: Commit**

```bash
git add lib/profile/sync.sh tests/test_sync.sh
git commit -m "feat(tmux): add _profile_sync_tmux"
```

---

### Task 4: Add tmux section to _profile_diff in diff.sh

**Files:**
- Modify: `lib/profile/diff.sh:101-132` (add tmux section after Claude Code, before VSCode)

- [ ] **Step 1: Add tmux diff section**

In `lib/profile/diff.sh`, add a tmux section after the Claude Code section (after line 132) and before the VSCode settings section (line 134). Insert:

```bash
    # Tmux
    local tmux_source=""
    [[ -f "$PROFILES_DIR/default/tmux/tmux.conf" ]] && tmux_source="$PROFILES_DIR/default/tmux/tmux.conf"
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        [[ -f "$PROFILES_DIR/$p/tmux/tmux.conf" ]] && tmux_source="$PROFILES_DIR/$p/tmux/tmux.conf"
    done
    if [[ -n "$tmux_source" ]]; then
        local target="$HOME/.tmux.conf"
        if [[ -f "$target" ]]; then
            result=$($diff_cmd "$target" "$tmux_source" 2>/dev/null)
            if [[ -n "$result" ]]; then
                echo "=== tmux (~/.tmux.conf) ==="
                echo "$result"
                echo ""
                has_diff=true
            fi
        else
            echo "=== tmux (~/.tmux.conf) ==="
            echo "  (new file would be created)"
            echo ""
            has_diff=true
        fi
    fi
```

- [ ] **Step 2: Run full test suite to verify nothing broke**

Run: `./tests/run.sh`
Expected: all PASS

- [ ] **Step 3: Commit**

```bash
git add lib/profile/diff.sh
git commit -m "feat(tmux): add tmux section to profile diff"
```

---

### Task 5: Wire into main.sh and add module loading tests

**Files:**
- Modify: `lib/profile/main.sh:168-173` (use command — add apply call after iterm, before mise)
- Modify: `lib/profile/main.sh:227-232` (sync command — add sync call after iterm)
- Modify: `lib/profile/main.sh:255` (help text — add "tmux" to list)
- Test: `tests/test_module_loading.sh`

- [ ] **Step 1: Add _profile_apply_tmux to `profile use`**

In `lib/profile/main.sh`, in the `use|s)` case, add `_profile_apply_tmux "$active_set"` after `_profile_apply_iterm "$active_set"` (line 171) and before `_profile_apply_mise "$active_set"` (line 172):

```bash
            _profile_apply_git "$active_set"
            _profile_apply_claude "$active_set"
            _profile_apply_vscode "$active_set"
            _profile_apply_iterm "$active_set"
            _profile_apply_tmux "$active_set"
            _profile_apply_mise "$active_set"
            _profile_apply_brew "$active_set"
```

- [ ] **Step 2: Add _profile_sync_tmux to `profile sync`**

In `lib/profile/main.sh`, in the `sync|sy)` case, add `_profile_sync_tmux "$active"` after `_profile_sync_iterm "$active"` (line 232):

```bash
            _profile_sync_brew "$active"
            _profile_sync_vscode "$active"
            _profile_apply_git "$active"
            _profile_sync_mise "$active"
            _profile_sync_claude "$active"
            _profile_sync_iterm "$active"
            _profile_sync_tmux "$active"
```

- [ ] **Step 3: Update help text**

In `lib/profile/main.sh`, change the `use` help line (line 255) to include "tmux":

```bash
            echo "  use [name] [name2 ...]     (s)   Apply profiles (brew + vscode + iterm + git + mise + claude + tmux); default alone if no args"
```

- [ ] **Step 4: Add module loading tests**

In `tests/test_module_loading.sh`, add before `_test_summary` (line 54):

```bash
_TEST_NAME="_profile_apply_tmux exists"
assert_eq "function" "$(whence -w _profile_apply_tmux | awk '{print $2}')"

_TEST_NAME="_profile_sync_tmux exists"
assert_eq "function" "$(whence -w _profile_sync_tmux | awk '{print $2}')"
```

- [ ] **Step 5: Run full test suite**

Run: `./tests/run.sh`
Expected: all PASS

- [ ] **Step 6: Commit**

```bash
git add lib/profile/main.sh tests/test_module_loading.sh
git commit -m "feat(tmux): wire tmux apply/sync into profile commands"
```
