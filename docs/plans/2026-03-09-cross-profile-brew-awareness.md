# Cross-Profile Brew Awareness Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Prevent `profile sync` and `profile diff` from suggesting packages owned by other profiles as new additions.

**Architecture:** Add a helper `_profile_read_all_brew_packages` that reads every `profiles/*/Brewfile` regardless of active profile. Use it in `_profile_sync_brew` and `_profile_diff` to filter out known-to-other-profiles packages from the "add to profile" / "extra" lists.

**Tech Stack:** zsh, existing profile system test harness

---

### Task 1: Add `_profile_read_all_brew_packages` helper

**Files:**
- Modify: `lib/profile/helpers.sh:49` (add new function after `_profile_read_brew_packages`)
- Test: `tests/test_helpers.sh`

**Step 1: Write the failing test**

Add to the end of `tests/test_helpers.sh` (before `_test_summary`):

```zsh
# --- _profile_read_all_brew_packages ---

_TEST_NAME="read_all_brew_packages reads from all profile directories"
# Create an extra profile not in the active set
mkdir -p "$PROFILES_DIR/otherprofile"
echo 'brew "biome"' > "$PROFILES_DIR/otherprofile/Brewfile"
echo 'cask "1password-cli"' >> "$PROFILES_DIR/otherprofile/Brewfile"
# default/Brewfile already has brew "git"
local all_pkgs=$(_profile_read_all_brew_packages)
assert_contains "$all_pkgs" "brew:git"
assert_contains "$all_pkgs" "brew:biome"
assert_contains "$all_pkgs" "cask:1password-cli"

_TEST_NAME="read_all_brew_packages skips directories without Brewfile"
mkdir -p "$PROFILES_DIR/noBrew"
local all_pkgs2=$(_profile_read_all_brew_packages)
assert_not_contains "$all_pkgs2" "noBrew"
rm -rf "$PROFILES_DIR/noBrew" "$PROFILES_DIR/otherprofile"
```

**Step 2: Run test to verify it fails**

Run: `zsh tests/test_helpers.sh`
Expected: FAIL — `_profile_read_all_brew_packages` not defined

**Step 3: Write minimal implementation**

Add to `lib/profile/helpers.sh` after `_profile_read_brew_packages` (after line 64):

```zsh
_profile_read_all_brew_packages() {
    local -a all_brewfiles=()
    for dir in "$PROFILES_DIR"/*/; do
        [[ -f "$dir/Brewfile" ]] && all_brewfiles+=("$dir/Brewfile")
    done
    _profile_read_brew_packages "${all_brewfiles[@]}"
}
```

**Step 4: Run test to verify it passes**

Run: `zsh tests/test_helpers.sh`
Expected: All PASS

**Step 5: Commit**

```bash
git add lib/profile/helpers.sh tests/test_helpers.sh
git commit -m "feat: add _profile_read_all_brew_packages helper"
```

---

### Task 2: Filter `to_add` in `_profile_sync_brew` using cross-profile awareness

**Files:**
- Modify: `lib/profile/sync.sh:152-211` (`_profile_sync_brew` function)

**Step 1: Write the failing test**

Add to `tests/test_helpers.sh` (before `_test_summary`):

```zsh
# --- cross-profile brew filtering ---

_TEST_NAME="cross-profile packages excluded from to_add calculation"
# Simulate: "otherprofile" has biome, current profile is "testprofile"
mkdir -p "$PROFILES_DIR/otherprofile"
echo 'brew "biome"' > "$PROFILES_DIR/otherprofile/Brewfile"
echo 'brew "opentofu"' >> "$PROFILES_DIR/otherprofile/Brewfile"
# Read all profile packages (union of all Brewfiles)
local all_known=$(_profile_read_all_brew_packages)
# Read only active profile packages
local active_known=$(_profile_read_brew_packages "$PROFILES_DIR/default/Brewfile")
# Simulated "installed" set
local installed=$(printf 'brew:git\nbrew:biome\nbrew:opentofu\nbrew:newpkg\n')
# to_add without cross-profile filter (old behavior)
local to_add_old=$(comm -23 <(echo "$installed" | sort) <(echo "$active_known" | grep -v "^tap:" | sort) | grep -v '^$')
# to_add with cross-profile filter (new behavior)
local to_add_new=$(comm -23 <(echo "$installed" | sort) <(echo "$all_known" | grep -v "^tap:" | sort) | grep -v '^$')
# Old behavior would include biome and opentofu
assert_contains "$to_add_old" "brew:biome"
assert_contains "$to_add_old" "brew:opentofu"
# New behavior should NOT include biome/opentofu (they're in otherprofile)
assert_not_contains "$to_add_new" "brew:biome"
assert_not_contains "$to_add_new" "brew:opentofu"
# But newpkg (not in any profile) should still be flagged
assert_contains "$to_add_new" "brew:newpkg"
rm -rf "$PROFILES_DIR/otherprofile"
```

**Step 2: Run test to verify it passes**

Run: `zsh tests/test_helpers.sh`
Expected: All PASS (this test validates the filtering logic, not the sync function itself)

**Step 3: Modify `_profile_sync_brew` in `lib/profile/sync.sh`**

In `_profile_sync_brew`, after line 164 (`local expected_no_tap=...`), add:

```zsh
    # Read packages from ALL profiles to avoid suggesting other profiles' packages
    local all_profile_packages=$(_profile_read_all_brew_packages)
    local all_profile_no_tap=$(echo "$all_profile_packages" | grep -v "^tap:")
```

Then change line 173 from:

```zsh
    local to_add=$(comm -23 <(echo "$installed") <(echo "$expected_no_tap") | grep -v '^$')
```

To:

```zsh
    local to_add=$(comm -23 <(echo "$installed") <(echo "$all_profile_no_tap") | grep -v '^$')
```

**Step 4: Run full test suite**

Run: `zsh tests/run.sh`
Expected: All tests pass

**Step 5: Commit**

```bash
git add lib/profile/sync.sh tests/test_helpers.sh
git commit -m "fix: exclude other profiles' packages from sync to_add"
```

---

### Task 3: Add cross-profile awareness to `_profile_diff`

**Files:**
- Modify: `lib/profile/diff.sh:210-230` (brew section of `_profile_diff`)

**Step 1: Modify the diff brew section**

In `_profile_diff`, after line 222 (`local current_set=...`), add a line to compute extras with cross-profile filtering. Change the brew section to also show extras (installed but not in current profile, excluding other profiles' packages):

After the existing `brew_missing` block (line 228), add:

```zsh
        local all_known=$(_profile_read_all_brew_packages)
        local all_known_no_tap=$(echo "$all_known" | grep -v "^tap:")
        local brew_extra=$(comm -23 <(echo "$current_set") <(echo "$all_known_no_tap") | grep -v '^$')
```

And update the display block to also show extras:

```zsh
        if [[ -n "$brew_missing" || -n "$brew_extra" ]]; then
            echo "=== brew ==="
            [[ -n "$brew_missing" ]] && echo "$brew_missing" | sed 's/^/  + /'
            [[ -n "$brew_extra" ]] && echo "$brew_extra" | sed 's/^/  - /'
            echo ""
            has_diff=true
        fi
```

**Step 2: Run full test suite**

Run: `zsh tests/run.sh`
Expected: All tests pass

**Step 3: Commit**

```bash
git add lib/profile/diff.sh
git commit -m "feat: show truly unknown brew packages in profile diff"
```

---

### Task 4: Final verification

**Step 1: Run the full test suite**

Run: `zsh tests/run.sh`
Expected: All tests pass, 0 failures

**Step 2: Manual smoke test**

Run: `profile sync` on current machine to confirm other profiles' packages no longer appear as "add to profile" suggestions.

**Step 3: Commit any remaining changes and push**

```bash
git push
```
