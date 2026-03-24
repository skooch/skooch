# Per-Item Sync Prompts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace bulk "Apply? [Y/n]" prompts in `profile sync` with per-item interactive prompts that support install, remove-from-profile, add-to-profile, uninstall, and skip actions for brew packages, VSCode extensions, and mise tools.

**Architecture:** Add shared prompt/removal helpers to `helpers.sh`, then rewrite each list-based sync function in `sync.sh` to iterate per-item. Source tracking (which profile file each entry came from) enables targeted removal. Mise gets a two-pass split: list-based for `[tools]`, three-way merge for everything else.

**Tech Stack:** zsh, sed, brew CLI, VS Code CLI, mise CLI

**Spec:** `docs/superpowers/specs/2026-03-23-per-item-sync-prompts-design.md`

---

## File Structure

| File | Role |
|------|------|
| `lib/profile/helpers.sh` | Add `_profile_prompt_item`, `_profile_remove_line`, `_profile_remove_brew_line`, `_profile_read_brew_packages_sourced`, `_profile_read_extensions_sourced`, `_profile_read_mise_tools_sourced`, `_profile_mise_split_tools` |
| `lib/profile/sync.sh` | Rewrite `_profile_sync_brew`, `_profile_sync_vscode`, `_profile_sync_mise` |
| `tests/test_helpers_prompt.sh` | Tests for new helper functions |
| `tests/test_sync_peritem.sh` | Tests for per-item sync flows |

---

### Task 1: Add `_profile_prompt_item` helper

**Files:**
- Modify: `lib/profile/helpers.sh`
- Create: `tests/test_helpers_prompt.sh`

This helper prints the per-item prompt and reads user input, returning the chosen action.

- [ ] **Step 1: Write failing tests**

In `tests/test_helpers_prompt.sh`:

```zsh
#!/usr/bin/env zsh
# Test per-item prompt and removal helpers

source "${0:A:h}/harness.sh"

# --- _profile_prompt_item ---

_TEST_NAME="prompt_item not_installed default is install"
local result=$(echo "" | _profile_prompt_item "brew:ripgrep" "not_installed")
assert_eq "install" "$result"

_TEST_NAME="prompt_item not_installed I is install"
local result=$(echo "I" | _profile_prompt_item "brew:ripgrep" "not_installed")
assert_eq "install" "$result"

_TEST_NAME="prompt_item not_installed i is install (case insensitive)"
local result=$(echo "i" | _profile_prompt_item "brew:ripgrep" "not_installed")
assert_eq "install" "$result"

_TEST_NAME="prompt_item not_installed R is remove"
local result=$(echo "R" | _profile_prompt_item "brew:ripgrep" "not_installed")
assert_eq "remove" "$result"

_TEST_NAME="prompt_item not_installed S is skip"
local result=$(echo "S" | _profile_prompt_item "brew:ripgrep" "not_installed")
assert_eq "skip" "$result"

_TEST_NAME="prompt_item not_in_profile default is add"
local result=$(echo "" | _profile_prompt_item "brew:wget" "not_in_profile")
assert_eq "add" "$result"

_TEST_NAME="prompt_item not_in_profile A is add"
local result=$(echo "A" | _profile_prompt_item "brew:wget" "not_in_profile")
assert_eq "add" "$result"

_TEST_NAME="prompt_item not_in_profile U is uninstall"
local result=$(echo "U" | _profile_prompt_item "brew:wget" "not_in_profile")
assert_eq "uninstall" "$result"

_TEST_NAME="prompt_item not_in_profile S is skip"
local result=$(echo "S" | _profile_prompt_item "brew:wget" "not_in_profile")
assert_eq "skip" "$result"

_test_summary
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zsh tests/test_helpers_prompt.sh`
Expected: FAIL — `_profile_prompt_item` not defined

- [ ] **Step 3: Implement `_profile_prompt_item`**

Add to `lib/profile/helpers.sh` at the end:

```zsh
# --- Per-item sync prompt ---

_profile_prompt_item() {
    local label="$1" direction="$2"

    if [[ "$direction" == "not_installed" ]]; then
        echo "  $label — not installed" >&2
        while true; do
            printf "    [I]nstall / [R]emove from profile / [S]kip? [I] " >&2
            local answer
            read -r answer
            case "${answer:-I}" in
                [iI]) echo "install"; return ;;
                [rR]) echo "remove"; return ;;
                [sS]) echo "skip"; return ;;
                *)    echo "    Invalid input, try again." >&2 ;;
            esac
        done
    elif [[ "$direction" == "not_in_profile" ]]; then
        echo "  $label — not in profile" >&2
        while true; do
            printf "    [A]dd to profile / [U]ninstall / [S]kip? [A] " >&2
            local answer
            read -r answer
            case "${answer:-A}" in
                [aA]) echo "add"; return ;;
                [uU]) echo "uninstall"; return ;;
                [sS]) echo "skip"; return ;;
                *)    echo "    Invalid input, try again." >&2 ;;
            esac
        done
    fi
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zsh tests/test_helpers_prompt.sh`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add lib/profile/helpers.sh tests/test_helpers_prompt.sh
git commit -m "Add _profile_prompt_item helper for per-item sync prompts"
```

---

### Task 2: Add `_profile_remove_line` and `_profile_remove_brew_line` helpers

**Files:**
- Modify: `lib/profile/helpers.sh`
- Modify: `tests/test_helpers_prompt.sh`

- [ ] **Step 1: Write failing tests**

Append to `tests/test_helpers_prompt.sh` (before `_test_summary`):

```zsh
# --- _profile_remove_line ---

_TEST_NAME="remove_line deletes matching line from file"
local tmpfile=$(mktemp)
printf 'line one\nline two\nline three\n' > "$tmpfile"
_profile_remove_line "$tmpfile" "^line two$"
local content=$(cat "$tmpfile")
assert_not_contains "$content" "line two"
assert_contains "$content" "line one"
assert_contains "$content" "line three"
rm -f "$tmpfile"

_TEST_NAME="remove_line only deletes first match"
local tmpfile=$(mktemp)
printf 'aaa\nbbb\naaa\n' > "$tmpfile"
_profile_remove_line "$tmpfile" "^aaa$"
local lines=$(wc -l < "$tmpfile" | tr -d ' ')
assert_eq "2" "$lines"
rm -f "$tmpfile"

# --- _profile_remove_brew_line ---

_TEST_NAME="remove_brew_line removes brew formula"
local tmpfile=$(mktemp)
printf 'brew "git"\nbrew "jq"\nbrew "wget"\n' > "$tmpfile"
_profile_remove_brew_line "$tmpfile" "brew" "jq"
local content=$(cat "$tmpfile")
assert_not_contains "$content" "jq"
assert_contains "$content" "git"
assert_contains "$content" "wget"
rm -f "$tmpfile"

_TEST_NAME="remove_brew_line removes cask"
local tmpfile=$(mktemp)
printf 'cask "iterm2"\ncask "slack"\n' > "$tmpfile"
_profile_remove_brew_line "$tmpfile" "cask" "slack"
local content=$(cat "$tmpfile")
assert_not_contains "$content" "slack"
assert_contains "$content" "iterm2"
rm -f "$tmpfile"

_TEST_NAME="remove_brew_line handles options on line"
local tmpfile=$(mktemp)
printf 'brew "ollama", restart_service: :changed\nbrew "git"\n' > "$tmpfile"
_profile_remove_brew_line "$tmpfile" "brew" "ollama"
local content=$(cat "$tmpfile")
assert_not_contains "$content" "ollama"
assert_contains "$content" "git"
rm -f "$tmpfile"

_TEST_NAME="remove_brew_line handles trailing comment"
local tmpfile=$(mktemp)
printf 'brew "fzf"              # Fuzzy finder\nbrew "git"\n' > "$tmpfile"
_profile_remove_brew_line "$tmpfile" "brew" "fzf"
local content=$(cat "$tmpfile")
assert_not_contains "$content" "fzf"
assert_contains "$content" "git"
rm -f "$tmpfile"

_TEST_NAME="remove_brew_line handles indented line in if block"
local tmpfile=$(mktemp)
printf 'if OS.mac?\n    brew "coreutils"\n    brew "grep"\nend\nbrew "git"\n' > "$tmpfile"
_profile_remove_brew_line "$tmpfile" "brew" "coreutils"
local content=$(cat "$tmpfile")
assert_not_contains "$content" "coreutils"
assert_contains "$content" "grep"
assert_contains "$content" "if OS.mac?"
rm -f "$tmpfile"

_TEST_NAME="remove_brew_line cleans empty if block"
local tmpfile=$(mktemp)
printf 'if OS.mac?\n    brew "coreutils"\nend\nbrew "git"\n' > "$tmpfile"
_profile_remove_brew_line "$tmpfile" "brew" "coreutils"
local content=$(cat "$tmpfile")
assert_not_contains "$content" "coreutils"
assert_not_contains "$content" "if OS.mac?"
assert_not_contains "$content" "end"
assert_contains "$content" "git"
rm -f "$tmpfile"

_TEST_NAME="remove_brew_line escapes regex metacharacters in name"
local tmpfile=$(mktemp)
printf 'brew "python@3.13"\nbrew "git"\n' > "$tmpfile"
_profile_remove_brew_line "$tmpfile" "brew" "python@3.13"
local content=$(cat "$tmpfile")
assert_not_contains "$content" "python"
assert_contains "$content" "git"
rm -f "$tmpfile"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zsh tests/test_helpers_prompt.sh`
Expected: FAIL — `_profile_remove_line` and `_profile_remove_brew_line` not defined

- [ ] **Step 3: Implement the helpers**

Add to `lib/profile/helpers.sh`:

```zsh
# --- Line removal helpers ---

_profile_remove_line() {
    local file="$1" pattern="$2"
    local tmpfile=$(mktemp)
    local removed=false
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$removed" == false ]] && [[ "$line" =~ $pattern ]]; then
            removed=true
            continue
        fi
        echo "$line"
    done < "$file" > "$tmpfile"
    mv "$tmpfile" "$file"
}

_profile_escape_regex() {
    local str="$1"
    # Escape POSIX ERE metacharacters for use in zsh =~ patterns
    str="${str//\\/\\\\}"
    str="${str//./\\.}"
    str="${str//\*/\\*}"
    str="${str//+/\\+}"
    str="${str//\?/\\?}"
    str="${str//\^/\\^}"
    str="${str//\$/\\$}"
    str="${str//\(/\\(}"
    str="${str//\)/\\)}"
    str="${str//\[/\\[}"
    str="${str//\]/\\]}"
    str="${str//\{/\\{}"
    str="${str//\}/\\}}"
    str="${str//|/\\|}"
    echo "$str"
}

_profile_remove_brew_line() {
    local file="$1" type="$2" name="$3"
    local escaped_name=$(_profile_escape_regex "$name")
    local pattern="^[[:space:]]*${type}[[:space:]]+\"${escaped_name}\""

    # Remove the matching line
    _profile_remove_line "$file" "$pattern"

    # Clean up empty if/end blocks
    _profile_clean_empty_blocks "$file"
}

_profile_clean_empty_blocks() {
    local file="$1"
    local tmpfile=$(mktemp)
    local -a lines=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        lines+=("$line")
    done < "$file"

    local -a output=()
    local i=1
    while [[ $i -le ${#lines[@]} ]]; do
        local line="${lines[$i]}"
        if [[ "$line" =~ ^[[:space:]]*'if '[Oo] ]]; then
            # Found an if block — scan for end
            local block_start=$i
            local has_content=false
            local j=$((i + 1))
            while [[ $j -le ${#lines[@]} ]]; do
                local inner="${lines[$j]}"
                if [[ "$inner" =~ ^[[:space:]]*end[[:space:]]*$ ]]; then
                    break
                fi
                # Check if line has non-blank, non-comment content
                local stripped="${inner%%#*}"
                stripped="${stripped// /}"
                stripped="${stripped//	/}"
                if [[ -n "$stripped" ]]; then
                    has_content=true
                fi
                (( j++ ))
            done
            if [[ "$has_content" == false && $j -le ${#lines[@]} ]]; then
                # Skip the entire empty block (if line through end line)
                i=$((j + 1))
                continue
            fi
        fi
        output+=("$line")
        (( i++ ))
    done

    printf '%s\n' "${output[@]}" > "$file"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zsh tests/test_helpers_prompt.sh`
Expected: All PASS

- [ ] **Step 5: Run full test suite to check for regressions**

Run: `zsh tests/run_all.sh` (or whatever the test runner is — check with `ls tests/`)
Expected: All existing tests still pass

- [ ] **Step 6: Commit**

```bash
git add lib/profile/helpers.sh tests/test_helpers_prompt.sh
git commit -m "Add _profile_remove_line and _profile_remove_brew_line helpers"
```

---

### Task 3: Add source-tracking reader functions

**Files:**
- Modify: `lib/profile/helpers.sh`
- Modify: `tests/test_helpers_prompt.sh`

These functions emit `type:name\tfile` pairs so the sync logic knows which file to target for removals.

- [ ] **Step 1: Write failing tests**

Append to `tests/test_helpers_prompt.sh` (before `_test_summary`):

```zsh
# --- _profile_read_brew_packages_sourced ---

_TEST_NAME="read_brew_packages_sourced emits type:name with source file"
local tmpbrew=$(mktemp)
printf 'brew "git"\ncask "iterm2"\n' > "$tmpbrew"
local output=$(_profile_read_brew_packages_sourced "$tmpbrew")
assert_contains "$output" "brew:git	$tmpbrew"
assert_contains "$output" "cask:iterm2	$tmpbrew"
rm -f "$tmpbrew"

_TEST_NAME="read_brew_packages_sourced skips taps"
local tmpbrew=$(mktemp)
printf 'tap "homebrew/core"\nbrew "git"\n' > "$tmpbrew"
local output=$(_profile_read_brew_packages_sourced "$tmpbrew")
assert_not_contains "$output" "tap:"
rm -f "$tmpbrew"

_TEST_NAME="read_brew_packages_sourced tracks multiple files"
local tmpbrew1=$(mktemp)
local tmpbrew2=$(mktemp)
printf 'brew "git"\n' > "$tmpbrew1"
printf 'brew "wget"\n' > "$tmpbrew2"
local output=$(_profile_read_brew_packages_sourced "$tmpbrew1" "$tmpbrew2")
assert_contains "$output" "brew:git	$tmpbrew1"
assert_contains "$output" "brew:wget	$tmpbrew2"
rm -f "$tmpbrew1" "$tmpbrew2"

# --- _profile_read_extensions_sourced ---

_TEST_NAME="read_extensions_sourced emits ext with source file"
local tmpext=$(mktemp)
printf 'ms-python.python\ndbaeumer.vscode-eslint\n' > "$tmpext"
local output=$(_profile_read_extensions_sourced "$tmpext")
assert_contains "$output" "ms-python.python	$tmpext"
assert_contains "$output" "dbaeumer.vscode-eslint	$tmpext"
rm -f "$tmpext"

# --- _profile_read_mise_tools_sourced ---

_TEST_NAME="read_mise_tools_sourced emits tool names with source file"
local tmptoml=$(mktemp)
printf '[tools]\nnode = "lts"\nruby = "3"\n\n[settings]\nnot_found_auto_install = true\n' > "$tmptoml"
local output=$(_profile_read_mise_tools_sourced "$tmptoml")
assert_contains "$output" "node	$tmptoml"
assert_contains "$output" "ruby	$tmptoml"
assert_not_contains "$output" "not_found_auto_install"
rm -f "$tmptoml"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zsh tests/test_helpers_prompt.sh`
Expected: FAIL — functions not defined

- [ ] **Step 3: Implement the source-tracking readers**

Add to `lib/profile/helpers.sh`:

```zsh
# --- Source-tracking readers (emit "item\tfile" pairs) ---

_profile_read_brew_packages_sourced() {
    local -a files=("$@")
    for f in "${files[@]}"; do
        [[ -f "$f" ]] || continue
        local skip=false
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%%#*}"
            if [[ "$line" =~ ^[[:space:]]*if\ +OS\.mac\? ]]; then
                [[ "$IS_MACOS" != true ]] && skip=true
                continue
            elif [[ "$line" =~ ^[[:space:]]*if\ +OS\.linux\? ]]; then
                [[ "$IS_LINUX" != true ]] && skip=true
                continue
            elif [[ "$line" =~ ^[[:space:]]*end[[:space:]]*$ ]]; then
                skip=false
                continue
            fi
            [[ "$skip" == true ]] && continue
            if [[ "$line" =~ ^[[:space:]]*brew\ +\"([^\"]+)\" ]]; then
                printf 'brew:%s\t%s\n' "${match[1]}" "$f"
            elif [[ "$line" =~ ^[[:space:]]*cask\ +\"([^\"]+)\" ]]; then
                printf 'cask:%s\t%s\n' "${match[1]}" "$f"
            fi
        done < "$f"
    done
}

_profile_read_extensions_sourced() {
    local -a files=("$@")
    for f in "${files[@]}"; do
        [[ -f "$f" ]] || continue
        while IFS= read -r ext || [[ -n "$ext" ]]; do
            ext="${ext%%#*}"
            ext="${ext// /}"
            [[ -n "$ext" ]] && printf '%s\t%s\n' "$ext" "$f"
        done < "$f"
    done
}

_profile_read_mise_tools_sourced() {
    local -a files=("$@")
    for f in "${files[@]}"; do
        [[ -f "$f" ]] || continue
        local in_tools=false
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" == "[tools]" ]]; then
                in_tools=true
                continue
            elif [[ "$line" == \[* ]]; then
                in_tools=false
                continue
            fi
            [[ "$in_tools" == false ]] && continue
            [[ -z "$line" ]] && continue
            # Extract tool name (everything before = sign), trim whitespace
            local tool_name="${line%%=*}"
            tool_name="${tool_name## }"
            tool_name="${tool_name%% }"
            [[ -n "$tool_name" ]] && printf '%s\t%s\n' "$tool_name" "$f"
        done < "$f"
    done
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zsh tests/test_helpers_prompt.sh`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add lib/profile/helpers.sh tests/test_helpers_prompt.sh
git commit -m "Add source-tracking reader functions for brew, vscode, and mise"
```

---

### Task 4: Rewrite `_profile_sync_brew` with per-item prompts

**Files:**
- Modify: `lib/profile/sync.sh`
- Create: `tests/test_sync_peritem.sh`

- [ ] **Step 1: Write failing tests**

Create `tests/test_sync_peritem.sh`:

```zsh
#!/usr/bin/env zsh
# Test per-item sync flows for brew, vscode, and mise

source "${0:A:h}/harness.sh"

# --- Brew per-item sync tests ---
# These test the prompt/action logic by mocking brew commands

# Mock brew commands for testing
brew() {
    case "$1" in
        leaves) echo "git\njq" ;;
        list)
            [[ "$2" == "--cask" ]] && echo "iterm2"
            ;;
        uninstall) echo "MOCK_UNINSTALL: $*" ;;
        bundle) echo "MOCK_BUNDLE: $*" ;;
    esac
    return 0
}

_TEST_NAME="sync_brew per-item: skip leaves file unchanged"
# Set up: profile has git+jq+wget, system has git+jq+iterm2
# wget is not installed, iterm2 is not in profile
# Skip all items
local brewfile="$PROFILES_DIR/default/Brewfile"
printf 'brew "git"\nbrew "jq"\nbrew "wget"\n' > "$brewfile"
echo "default" > "$PROFILE_ACTIVE_FILE"
# Feed: S for wget (not installed), S for iterm2 (not in profile)
local output=$(printf 's\ns\n' | _profile_sync_brew "default" 2>&1)
# wget should still be in brewfile
local content=$(cat "$brewfile")
assert_contains "$content" "wget"

_TEST_NAME="sync_brew per-item: remove deletes from brewfile"
printf 'brew "git"\nbrew "jq"\nbrew "wget"\n' > "$brewfile"
# Feed: R for wget (not installed), S for iterm2 (not in profile)
local output=$(printf 'r\ns\n' | _profile_sync_brew "default" 2>&1)
local content=$(cat "$brewfile")
assert_not_contains "$content" "wget"
assert_contains "$content" "git"

_TEST_NAME="sync_brew per-item: skip-all prints no changes"
printf 'brew "git"\nbrew "jq"\nbrew "wget"\n' > "$brewfile"
local output=$(printf 's\ns\n' | _profile_sync_brew "default" 2>&1)
assert_contains "$output" "No changes"

_test_summary
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zsh tests/test_sync_peritem.sh`
Expected: FAIL — current `_profile_sync_brew` doesn't use per-item prompts

- [ ] **Step 3: Rewrite `_profile_sync_brew`**

Replace the function in `lib/profile/sync.sh`. The new version:

```zsh
_profile_sync_brew() {
    local profiles="$1"
    local default_brewfile="$PROFILES_DIR/default/Brewfile"
    [[ -f "$default_brewfile" ]] || return 0

    # Collect active profile Brewfiles
    local -a brewfiles=("$default_brewfile")
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        local pf="$PROFILES_DIR/$p/Brewfile"
        [[ -f "$pf" ]] && brewfiles+=("$pf")
    done

    # Source-tracked expected packages (type:name\tfile)
    local sourced=$(_profile_read_brew_packages_sourced "${brewfiles[@]}")
    # Deduplicated expected names only (for comparison)
    local expected=$(echo "$sourced" | cut -f1 | grep -v "^$" | sort -u)
    local expected_no_tap=$(echo "$expected" | grep -v "^tap:")

    # All profiles' packages (to filter "not in profile" list)
    local all_profile_packages=$(_profile_read_all_brew_packages)
    local all_profile_no_tap=$(echo "$all_profile_packages" | grep -v "^tap:")

    # Currently installed
    local current_formulae=$(brew leaves 2>/dev/null | sort)
    local current_casks=$(brew list --cask 2>/dev/null | sort)
    local installed=$( (echo "$current_formulae" | sed '/^$/d' | sed 's/^/brew:/'; echo "$current_casks" | sed '/^$/d' | sed 's/^/cask:/') | sort -u)

    # Compute diffs
    local to_install=$(comm -23 <(echo "$expected_no_tap") <(echo "$installed") | grep -v '^$')
    local to_add=$(comm -23 <(echo "$installed") <(echo "$all_profile_no_tap") | grep -v '^$')

    if [[ -z "$to_install" && -z "$to_add" ]]; then
        echo "  Brew: in sync"
        return 0
    fi

    echo "  Brew changes:"

    # Track actions
    local -a items_to_install=()
    local -a items_to_remove=()
    local -a items_to_add=()
    local -a items_to_uninstall=()
    local had_action=false

    # Per-item prompts: not installed
    if [[ -n "$to_install" ]]; then
        for pkg in ${(f)to_install}; do
            [[ -z "$pkg" ]] && continue
            local action=$(_profile_prompt_item "$pkg" "not_installed")
            case "$action" in
                install)   items_to_install+=("$pkg"); had_action=true ;;
                remove)    items_to_remove+=("$pkg"); had_action=true ;;
                skip)      ;;
            esac
        done
    fi

    # Per-item prompts: not in profile
    if [[ -n "$to_add" ]]; then
        for pkg in ${(f)to_add}; do
            [[ -z "$pkg" ]] && continue
            local action=$(_profile_prompt_item "$pkg" "not_in_profile")
            case "$action" in
                add)       items_to_add+=("$pkg"); had_action=true ;;
                uninstall) items_to_uninstall+=("$pkg"); had_action=true ;;
                skip)      ;;
            esac
        done
    fi

    if [[ "$had_action" == false ]]; then
        echo "  No changes applied."
        return 0
    fi

    # Execute installs (via brew bundle with a temp Brewfile of just the items)
    if [[ ${#items_to_install[@]} -gt 0 ]]; then
        local tmpfile=$(mktemp)
        # Build a Brewfile containing taps + selected items
        # Include all taps from profile
        local taps=$(echo "$expected" | grep "^tap:" | sed 's/^tap://')
        for t in ${(f)taps}; do
            [[ -n "$t" ]] && echo "tap \"$t\"" >> "$tmpfile"
        done
        for pkg in "${items_to_install[@]}"; do
            local type="${pkg%%:*}" name="${pkg#*:}"
            echo "$type \"$name\"" >> "$tmpfile"
        done
        brew bundle --file="$tmpfile"
        rm -f "$tmpfile"
    fi

    # Execute removes from profile
    for pkg in "${items_to_remove[@]}"; do
        local type="${pkg%%:*}" name="${pkg#*:}"
        # Find all source files containing this package and remove from each
        echo "$sourced" | while IFS=$'\t' read -r entry file; do
            [[ "$entry" == "$pkg" && -n "$file" ]] && _profile_remove_brew_line "$file" "$type" "$name"
        done
        echo "  Removed $pkg from profile"
    done

    # Execute adds to profile
    if [[ ${#items_to_add[@]} -gt 0 ]]; then
        local target_profile=$(_profile_pick_target "$profiles" "Brewfile")
        local target_brewfile="$PROFILES_DIR/$target_profile/Brewfile"
        [[ "$target_profile" == "default" ]] && target_brewfile="$default_brewfile"
        for pkg in "${items_to_add[@]}"; do
            local type="${pkg%%:*}" name="${pkg#*:}"
            echo "$type \"$name\"" >> "$target_brewfile"
        done
        echo "  Added ${#items_to_add[@]} package(s) to $(basename "$(dirname "$target_brewfile")")/Brewfile"
    fi

    # Execute uninstalls
    for pkg in "${items_to_uninstall[@]}"; do
        local type="${pkg%%:*}" name="${pkg#*:}"
        if [[ "$type" == "cask" ]]; then
            brew uninstall --cask "$name"
        else
            brew uninstall "$name"
        fi
        echo "  Uninstalled $pkg"
    done

    # Post-brew hook (only if install or uninstall happened)
    if [[ ${#items_to_install[@]} -gt 0 || ${#items_to_uninstall[@]} -gt 0 ]]; then
        _profile_post_brew
    fi
}
```

- [ ] **Step 4: Run per-item tests**

Run: `zsh tests/test_sync_peritem.sh`
Expected: All PASS

- [ ] **Step 5: Run full test suite**

Run: `zsh tests/run_all.sh` or the test runner script
Expected: All pass (existing sync tests cover `_profile_sync_config` which is unchanged)

- [ ] **Step 6: Commit**

```bash
git add lib/profile/sync.sh tests/test_sync_peritem.sh
git commit -m "Rewrite _profile_sync_brew with per-item interactive prompts"
```

---

### Task 5: Rewrite `_profile_sync_vscode` with per-item prompts

**Files:**
- Modify: `lib/profile/sync.sh`
- Modify: `tests/test_sync_peritem.sh`

- [ ] **Step 1: Write failing tests**

Append to `tests/test_sync_peritem.sh` (before `_test_summary`):

```zsh
# --- VSCode per-item sync tests ---
# Mock vscode CLI and instances

# Override _profile_vscode_instances to return a mock
_profile_vscode_instances() {
    echo "MockCode|$TEST_HOME/.config/Code/User|$TEST_HOME/mock-code"
}

# Create mock code CLI
mkdir -p "$TEST_HOME/.config/Code/User"
cat > "$TEST_HOME/mock-code" << 'MOCKEOF'
#!/bin/zsh
case "$1" in
    --list-extensions) cat "$MOCK_EXTENSIONS_FILE" 2>/dev/null ;;
    --install-extension) echo "MOCK_INSTALL: $2" ;;
    --uninstall-extension) echo "MOCK_UNINSTALL: $2" ;;
esac
MOCKEOF
chmod +x "$TEST_HOME/mock-code"

MOCK_EXTENSIONS_FILE="$TEST_HOME/mock_extensions.txt"

_TEST_NAME="sync_vscode per-item: remove deletes from extensions.txt"
local extfile="$PROFILES_DIR/default/vscode/extensions.txt"
printf 'ext.one\next.two\next.three\n' > "$extfile"
printf 'ext.one\next.three\n' > "$MOCK_EXTENSIONS_FILE"
# ext.two is not installed — choose R to remove
local output=$(printf 'r\n' | _profile_sync_vscode "default" 2>&1)
local content=$(cat "$extfile")
assert_not_contains "$content" "ext.two"
assert_contains "$content" "ext.one"

_TEST_NAME="sync_vscode per-item: skip leaves extensions.txt unchanged"
printf 'ext.one\next.two\next.three\n' > "$extfile"
printf 'ext.one\next.three\n' > "$MOCK_EXTENSIONS_FILE"
# ext.two not installed — choose S to skip
local output=$(printf 's\n' | _profile_sync_vscode "default" 2>&1)
local content=$(cat "$extfile")
assert_contains "$content" "ext.two"
assert_contains "$output" "No changes"

_TEST_NAME="sync_vscode per-item: in sync prints message"
printf 'ext.one\next.three\n' > "$extfile"
printf 'ext.one\next.three\n' > "$MOCK_EXTENSIONS_FILE"
local output=$(_profile_sync_vscode "default" 2>&1)
assert_contains "$output" "in sync"

_TEST_NAME="sync_vscode per-item: uninstall calls CLI"
printf 'ext.one\n' > "$extfile"
printf 'ext.one\next.extra\n' > "$MOCK_EXTENSIONS_FILE"
# ext.extra is installed but not in profile — choose U to uninstall
local output=$(printf 'u\n' | _profile_sync_vscode "default" 2>&1)
assert_contains "$output" "Uninstalled ext.extra"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zsh tests/test_sync_peritem.sh`
Expected: FAIL — current `_profile_sync_vscode` uses bulk prompt

- [ ] **Step 3: Rewrite `_profile_sync_vscode` extensions section**

Replace the extensions section (the bidirectional merge block) in `_profile_sync_vscode` in `lib/profile/sync.sh`. Keep settings and keybindings sync unchanged. The new extensions logic:

```zsh
    # --- Extensions (per-item sync) ---
    if [[ -n "$instances" ]]; then
        local -a ext_files=()
        [[ -f "$default_ext" ]] && ext_files+=("$default_ext")
        for p in ${=profiles}; do
            [[ "$p" == "default" ]] && continue
            local ef="$PROFILES_DIR/$p/vscode/extensions.txt"
            [[ -f "$ef" ]] && ext_files+=("$ef")
        done

        if [[ ${#ext_files[@]} -gt 0 ]]; then
            # Source-tracked expected extensions
            local sourced=$(_profile_read_extensions_sourced "${ext_files[@]}")
            local expected=$(echo "$sourced" | cut -f1 | sort -u)

            # Collect installed from all instances
            local -a all_installed=()
            while IFS='|' read -r _label _dir cli; do
                [[ -z "$_label" ]] && continue
                while IFS= read -r ext; do
                    [[ -n "$ext" ]] && all_installed+=("$ext")
                done < <("$cli" --list-extensions 2>/dev/null)
            done <<< "$instances"
            local installed=$(printf '%s\n' "${all_installed[@]}" | sort -u)

            local to_install=$(comm -23 <(echo "$expected") <(echo "$installed") | grep -v '^$')
            local to_add=$(comm -23 <(echo "$installed") <(echo "$expected") | grep -v '^$')

            if [[ -n "$to_install" || -n "$to_add" ]]; then
                echo "  VSCode extension changes:"

                local -a exts_to_install=()
                local -a exts_to_remove=()
                local -a exts_to_add=()
                local -a exts_to_uninstall=()
                local had_action=false

                if [[ -n "$to_install" ]]; then
                    for ext in ${(f)to_install}; do
                        [[ -z "$ext" ]] && continue
                        local action=$(_profile_prompt_item "$ext" "not_installed")
                        case "$action" in
                            install)   exts_to_install+=("$ext"); had_action=true ;;
                            remove)    exts_to_remove+=("$ext"); had_action=true ;;
                            skip)      ;;
                        esac
                    done
                fi

                if [[ -n "$to_add" ]]; then
                    for ext in ${(f)to_add}; do
                        [[ -z "$ext" ]] && continue
                        local action=$(_profile_prompt_item "$ext" "not_in_profile")
                        case "$action" in
                            add)       exts_to_add+=("$ext"); had_action=true ;;
                            uninstall) exts_to_uninstall+=("$ext"); had_action=true ;;
                            skip)      ;;
                        esac
                    done
                fi

                if [[ "$had_action" == false ]]; then
                    echo "  No changes applied."
                else
                    # Install
                    if [[ ${#exts_to_install[@]} -gt 0 ]]; then
                        while IFS='|' read -r _label _dir cli; do
                            [[ -z "$_label" ]] && continue
                            for ext in "${exts_to_install[@]}"; do
                                "$cli" --install-extension "$ext" --force 2>/dev/null
                            done
                        done <<< "$instances"
                    fi

                    # Remove from profile
                    for ext in "${exts_to_remove[@]}"; do
                        echo "$sourced" | while IFS=$'\t' read -r entry file; do
                            [[ "$entry" == "$ext" && -n "$file" ]] && _profile_remove_line "$file" "^${ext}$"
                        done
                        echo "  Removed $ext from profile"
                    done

                    # Add to profile
                    if [[ ${#exts_to_add[@]} -gt 0 ]]; then
                        local target_profile=$(_profile_pick_target "$profiles" "extensions")
                        local target_ext="$PROFILES_DIR/$target_profile/vscode/extensions.txt"
                        [[ "$target_profile" == "default" || ! -d "$(dirname "$target_ext")" ]] && target_ext="$default_ext"
                        for ext in "${exts_to_add[@]}"; do
                            echo "$ext" >> "$target_ext"
                        done
                    fi

                    # Uninstall
                    for ext in "${exts_to_uninstall[@]}"; do
                        while IFS='|' read -r _label _dir cli; do
                            [[ -z "$_label" ]] && continue
                            "$cli" --uninstall-extension "$ext" 2>/dev/null || true
                        done <<< "$instances"
                        echo "  Uninstalled $ext"
                    done
                fi
            else
                echo "  VSCode extensions: in sync"
            fi
        fi
    fi
```

- [ ] **Step 4: Run tests**

Run: `zsh tests/test_sync_peritem.sh`
Expected: All PASS

- [ ] **Step 5: Run full test suite**

Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add lib/profile/sync.sh tests/test_sync_peritem.sh
git commit -m "Rewrite _profile_sync_vscode extensions with per-item prompts"
```

---

### Task 6: Rewrite `_profile_sync_mise` with two-pass approach

**Files:**
- Modify: `lib/profile/sync.sh`
- Modify: `lib/profile/helpers.sh` (add `_profile_mise_split_tools`)
- Modify: `tests/test_sync_peritem.sh`

- [ ] **Step 1: Write failing tests**

Add `_profile_mise_split_tools` tests to `tests/test_helpers_prompt.sh` (before `_test_summary`):

```zsh
# --- _profile_mise_split_tools ---

_TEST_NAME="mise_split_tools extracts tools section"
local tmptoml=$(mktemp)
printf '[tools]\nnode = "lts"\nruby = "3"\n\n[settings]\nnot_found_auto_install = true\n' > "$tmptoml"
local tools_out=$(mktemp)
local rest_out=$(mktemp)
_profile_mise_split_tools "$tmptoml" "$tools_out" "$rest_out"
local tools_content=$(cat "$tools_out")
local rest_content=$(cat "$rest_out")
assert_contains "$tools_content" 'node = "lts"'
assert_contains "$tools_content" 'ruby = "3"'
assert_not_contains "$tools_content" "not_found_auto_install"
assert_contains "$rest_content" "[settings]"
assert_contains "$rest_content" "not_found_auto_install"
assert_not_contains "$rest_content" '[tools]'
rm -f "$tmptoml" "$tools_out" "$rest_out"

_TEST_NAME="mise_split_tools handles tools-only file"
local tmptoml=$(mktemp)
printf '[tools]\nnode = "lts"\n' > "$tmptoml"
local tools_out=$(mktemp)
local rest_out=$(mktemp)
_profile_mise_split_tools "$tmptoml" "$tools_out" "$rest_out"
local tools_content=$(cat "$tools_out")
assert_contains "$tools_content" 'node = "lts"'
local rest_size=$(wc -c < "$rest_out" | tr -d ' ')
assert_eq "0" "$rest_size"
rm -f "$tmptoml" "$tools_out" "$rest_out"
```

Add mise sync tests to `tests/test_sync_peritem.sh` (before `_test_summary`):

```zsh
# --- Mise per-item sync tests ---

# Mock mise commands
mise() {
    case "$1" in
        ls)
            # Return JSON with installed tools
            echo '{"node":["22.0.0"],"ruby":["3.3.0"]}'
            ;;
        uninstall) echo "MOCK_MISE_UNINSTALL: $*" ;;
        install) echo "MOCK_MISE_INSTALL" ;;
    esac
    return 0
}

_TEST_NAME="sync_mise per-item: remove deletes tool from config.toml"
local misefile="$PROFILES_DIR/default/mise/config.toml"
printf '[tools]\nnode = "lts"\nruby = "3"\ngo = "latest"\n\n[settings]\nnot_found_auto_install = true\n' > "$misefile"
# go is not installed — choose R to remove; node and ruby are installed and in profile
local output=$(printf 'r\n' | _profile_sync_mise "default" 2>&1)
local content=$(cat "$misefile")
assert_not_contains "$content" "go"
assert_contains "$content" "node"
assert_contains "$content" "[settings]"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zsh tests/test_helpers_prompt.sh && zsh tests/test_sync_peritem.sh`
Expected: FAIL

- [ ] **Step 3: Implement `_profile_mise_split_tools`**

Add to `lib/profile/helpers.sh`:

```zsh
# --- Mise TOML splitting ---

_profile_mise_split_tools() {
    local input="$1" tools_out="$2" rest_out="$3"
    local in_tools=false

    > "$tools_out"
    > "$rest_out"

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ '^\[tools\]' ]]; then
            in_tools=true
            continue
        elif [[ "$line" =~ '^\[' ]]; then
            in_tools=false
        fi

        if [[ "$in_tools" == true ]]; then
            echo "$line" >> "$tools_out"
        else
            echo "$line" >> "$rest_out"
        fi
    done < "$input"
}
```

- [ ] **Step 4: Rewrite `_profile_sync_mise`**

Replace the function in `lib/profile/sync.sh`:

```zsh
_profile_sync_mise() {
    local profiles="$1"
    local target="$HOME/.config/mise/config.toml"

    local -a mise_files=()
    [[ -f "$PROFILES_DIR/default/mise/config.toml" ]] && mise_files+=("$PROFILES_DIR/default/mise/config.toml")
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        local pf="$PROFILES_DIR/$p/mise/config.toml"
        [[ -f "$pf" ]] && mise_files+=("$pf")
    done
    [[ ${#mise_files[@]} -eq 0 ]] && return 0

    # --- Pass 1: Tools section (list-based per-item sync) ---
    local sourced=$(_profile_read_mise_tools_sourced "${mise_files[@]}")
    local expected_tools=$(echo "$sourced" | cut -f1 | sort -u)

    # Read installed tools (name only)
    local installed_tools=""
    if command -v mise &>/dev/null; then
        installed_tools=$(mise ls --installed --json 2>/dev/null | jq -r 'keys[]' 2>/dev/null | sort -u)
    fi

    local to_install=$(comm -23 <(echo "$expected_tools") <(echo "$installed_tools") | grep -v '^$')
    local to_add=$(comm -23 <(echo "$installed_tools") <(echo "$expected_tools") | grep -v '^$')

    local tools_changed=false

    if [[ -n "$to_install" || -n "$to_add" ]]; then
        echo "  Mise tool changes:"

        local -a tools_to_install=()
        local -a tools_to_remove=()
        local -a tools_to_add=()
        local -a tools_to_uninstall=()
        local had_action=false

        if [[ -n "$to_install" ]]; then
            for tool in ${(f)to_install}; do
                [[ -z "$tool" ]] && continue
                local action=$(_profile_prompt_item "$tool" "not_installed")
                case "$action" in
                    install)   tools_to_install+=("$tool"); had_action=true ;;
                    remove)    tools_to_remove+=("$tool"); had_action=true ;;
                    skip)      ;;
                esac
            done
        fi

        if [[ -n "$to_add" ]]; then
            for tool in ${(f)to_add}; do
                [[ -z "$tool" ]] && continue
                local action=$(_profile_prompt_item "$tool" "not_in_profile")
                case "$action" in
                    add)       tools_to_add+=("$tool"); had_action=true ;;
                    uninstall) tools_to_uninstall+=("$tool"); had_action=true ;;
                    skip)      ;;
                esac
            done
        fi

        if [[ "$had_action" == false ]]; then
            echo "  No changes applied."
        else
            tools_changed=true

            # Remove from profile
            for tool in "${tools_to_remove[@]}"; do
                local escaped=$(_profile_escape_regex "$tool")
                echo "$sourced" | while IFS=$'\t' read -r entry file; do
                    [[ "$entry" == "$tool" && -n "$file" ]] && \
                        _profile_remove_line "$file" "^[[:space:]]*${escaped}[[:space:]]*="
                done
                echo "  Removed $tool from profile"
            done

            # Add to profile
            if [[ ${#tools_to_add[@]} -gt 0 ]]; then
                local target_profile=$(_profile_pick_target "$profiles" "mise tools")
                local target_mise="$PROFILES_DIR/$target_profile/mise/config.toml"
                [[ "$target_profile" == "default" ]] && target_mise="$PROFILES_DIR/default/mise/config.toml"
                # Ensure [tools] section exists
                if ! grep -q '^\[tools\]' "$target_mise" 2>/dev/null; then
                    echo "" >> "$target_mise"
                    echo "[tools]" >> "$target_mise"
                fi
                for tool in "${tools_to_add[@]}"; do
                    # Add after [tools] header
                    sed -i '' '/^\[tools\]/a\
'"$tool"' = "latest"' "$target_mise"
                done
            fi

            # Uninstall
            for tool in "${tools_to_uninstall[@]}"; do
                mise uninstall "$tool" 2>/dev/null || true
                echo "  Uninstalled $tool"
            done
        fi
    else
        echo "  Mise tools: in sync"
    fi

    # --- Pass 2: Non-tools sections (three-way merge) ---
    # Build merged non-tools config from all profile sources
    local expected_rest=$(mktemp)
    local -A sections
    local -a section_order=()
    local current_section="_top"
    for f in "${mise_files[@]}"; do
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" == \[* ]]; then
                current_section="$line"
                if [[ "$current_section" != "[tools]" ]]; then
                    # Track order (avoid duplicates)
                    local found=false
                    for s in "${section_order[@]}"; do
                        [[ "$s" == "$current_section" ]] && found=true && break
                    done
                    [[ "$found" == false ]] && section_order+=("$current_section")
                fi
            elif [[ -n "$line" && "$current_section" != "[tools]" ]]; then
                sections[$current_section]+="$line"$'\n'
            fi
        done < "$f"
    done

    # Only do three-way merge if there are non-tools sections
    if [[ ${#section_order[@]} -gt 0 || -n "${sections[_top]:-}" ]]; then
        {
            [[ -n "${sections[_top]:-}" ]] && printf '%s' "${sections[_top]}"
            for section in "${section_order[@]}"; do
                echo "$section"
                local -A seen_keys=()
                local -a ordered_lines=()
                while IFS= read -r line; do
                    [[ -z "$line" ]] && continue
                    local key="${line%%=*}"
                    key="${key%% }"
                    if [[ -n "${seen_keys[$key]+x}" ]]; then
                        ordered_lines[${seen_keys[$key]}]="$line"
                    else
                        ordered_lines+=("$line")
                        seen_keys[$key]="${#ordered_lines}"
                    fi
                done <<< "${sections[$section]}"
                printf '%s\n' "${ordered_lines[@]}"
                echo ""
            done
        } > "$expected_rest"

        # Three-way merge only covers non-tools sections.
        # We sync the non-tools expected against a non-tools extract of the local target,
        # then reassemble the full file afterward.
        # Extract the non-tools portion of the local target for comparison
        local target_rest=$(mktemp)
        if [[ -f "$target" ]]; then
            local dummy_tools=$(mktemp)
            _profile_mise_split_tools "$target" "$dummy_tools" "$target_rest"
            rm -f "$dummy_tools"
        else
            > "$target_rest"
        fi

        # Build non-tools extract of the single/first source to use as profile_source.
        # This prevents _profile_sync_config's "local -> profile" path from
        # overwriting full config.toml files with non-tools-only content.
        # After sync, if the rest-source was updated, reassemble the original file.
        local -a rest_sources=()
        for f in "${mise_files[@]}"; do
            local src_tools_tmp=$(mktemp)
            local src_rest_tmp=$(mktemp)
            _profile_mise_split_tools "$f" "$src_tools_tmp" "$src_rest_tmp"
            rest_sources+=("$src_rest_tmp")
            rm -f "$src_tools_tmp"
        done

        mkdir -p "$(dirname "$target")"
        _profile_sync_config "Mise settings" "$target_rest" "$expected_rest" "${rest_sources[@]}"
        local result=$?

        # Reassemble only if sync_config made changes (result != 0).
        # This avoids bumping mtimes on unchanged files, which would poison
        # the snapshot-based change detection for future syncs.
        if [[ $result -ne 0 ]]; then
            for (( idx=1; idx <= ${#mise_files[@]}; idx++ )); do
                local orig="${mise_files[$idx]}"
                local rest_src="${rest_sources[$idx]}"
                local orig_tools=$(mktemp)
                local orig_rest=$(mktemp)
                _profile_mise_split_tools "$orig" "$orig_tools" "$orig_rest"
                { [[ -s "$rest_src" ]] && cat "$rest_src"; echo "[tools]"; cat "$orig_tools"; } > "$orig"
                rm -f "$orig_tools" "$orig_rest" "$rest_src"
            done
        else
            rm -f "${rest_sources[@]}"
        fi

        # Reassemble full target: non-tools (possibly updated by sync_config) + tools from profile
        {
            cat "$target_rest"
            echo "[tools]"
            for f in "${mise_files[@]}"; do
                local tools_tmp=$(mktemp)
                local rest_tmp=$(mktemp)
                _profile_mise_split_tools "$f" "$tools_tmp" "$rest_tmp"
                cat "$tools_tmp"
                rm -f "$tools_tmp" "$rest_tmp"
            done
        } > "$target"

        rm -f "$expected_rest" "$target_rest"
    else
        # No non-tools sections — just write tools to target
        mkdir -p "$(dirname "$target")"
        {
            echo "[tools]"
            for f in "${mise_files[@]}"; do
                local tools_tmp=$(mktemp)
                local rest_tmp=$(mktemp)
                _profile_mise_split_tools "$f" "$tools_tmp" "$rest_tmp"
                cat "$tools_tmp"
                rm -f "$tools_tmp" "$rest_tmp"
            done
        } > "$target"
    fi

    # Run mise install if tools changed
    if [[ "$tools_changed" == true ]] && command -v mise &>/dev/null; then
        echo "  Running mise install..."
        mise install
    fi
}
```

- [ ] **Step 5: Run tests**

Run: `zsh tests/test_helpers_prompt.sh && zsh tests/test_sync_peritem.sh`
Expected: All PASS

- [ ] **Step 6: Run full test suite**

Expected: All pass

- [ ] **Step 7: Commit**

```bash
git add lib/profile/helpers.sh lib/profile/sync.sh tests/test_helpers_prompt.sh tests/test_sync_peritem.sh
git commit -m "Rewrite _profile_sync_mise with two-pass per-item tools + three-way settings"
```

---

### Task 7: Manual integration test and cleanup

**Files:**
- All modified files from previous tasks

- [ ] **Step 1: Run the full test suite**

```bash
zsh tests/run_all.sh || for f in tests/test_*.sh; do echo "--- $(basename $f .sh) ---"; zsh "$f"; done
```

Expected: All tests pass with 0 failures

- [ ] **Step 2: Manual smoke test (if brew/vscode/mise are available)**

Run `profile sync` and verify:
- Each out-of-sync brew package gets a per-item prompt
- Each out-of-sync VSCode extension gets a per-item prompt
- Choosing R removes from the correct Brewfile
- Choosing S skips with no side effects
- Choosing I/A preserves current behavior
- "In sync" message shows when nothing is out of sync
- "No changes applied" shows when all items are skipped

- [ ] **Step 3: Commit any fixes from smoke testing**

```bash
git add -A
git commit -m "Fix issues found during integration testing"
```

(Skip this step if no fixes needed)

- [ ] **Step 4: Final commit — update spec status**

Update `docs/superpowers/specs/2026-03-23-per-item-sync-prompts-design.md` status from "Review" to "Implemented".

```bash
git add docs/superpowers/specs/2026-03-23-per-item-sync-prompts-design.md
git commit -m "Mark per-item sync prompts spec as implemented"
```
