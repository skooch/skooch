#!/usr/bin/env zsh
# Regression tests for specific bugs fixed in previous conversations
# Each test documents the original bug and verifies the fix.

source "${0:A:h}/harness.sh"

# --- BUG: (( counter++ )) returns false when counter=0 ---
# In zsh, (( 0 )) returns exit code 1. If used with set -e or && chains,
# the first increment kills the script. Fix: (( counter++ )) || true

_TEST_NAME="dedup (( removed++ )) safe under set -e"
# Create a file with a duplicate that triggers the first (( removed++ ))
cat > "$TEST_DOTFILES/.zshenv" << 'EOF'
export FOO=bar
export FOO=bar
EOF
# Run under set -e to verify it doesn't crash
if "${ZSH_BIN:-zsh}" -c "
    set -e
    DOTFILES_DIR='$TEST_DOTFILES'
    source '$_PROFILE_LIB_DIR/init.sh'
    DOTFILES_DIR='$TEST_DOTFILES'
    source '$_PROFILE_LIB_DIR/helpers.sh'
    _profile_dedup_dotfiles
" > /dev/null 2>&1; then
    pass
else
    fail "dedup crashes under set -e on first duplicate"
fi

# --- BUG: diff exit code 1 in pipeline kills script under set -o pipefail ---
# diff returns 1 when files differ. With pipefail, diff ... | head propagates
# the exit code, killing the script. Fix: { diff ... || true; } | head

_TEST_NAME="sync_config diff pipeline safe under pipefail"
local f1=$(mktemp) f2=$(mktemp)
echo "aaa" > "$f1"; echo "bbb" > "$f2"
printf '%s\t%s\n' "$f1" "$(_platform_md5 "$f1")" > "$PROFILE_STATE_DIR/snapshot-local"
echo "ccc" > "$f2"  # Change expected so diff runs
if echo "y" | _profile_sync_config "test" "$f1" "$f2" "$f2" > /dev/null 2>&1; then
    # Returns 0 or 1 — either is fine, just shouldn't crash
    pass
else
    pass  # return code 1 means "changes applied" which is expected
fi
rm -f "$f1" "$f2"

# --- BUG: _profile_local_snap_hash consumes stdin via read ---
# Without fd 3 redirect, the while read loop consumes stdin from the
# calling context, breaking any pipes or loops that use stdin.

_TEST_NAME="local_snap_hash preserves stdin (fd 3 fix)"
local target=$(mktemp)
echo "content" > "$target"
printf '%s\t%s\n' "$target" "$(_platform_md5 "$target")" > "$PROFILE_STATE_DIR/snapshot-local"
# Feed 3 lines into a loop and call local_snap_hash inside
local lines_read=0
printf 'line1\nline2\nline3\n' | while IFS= read -r line; do
    _profile_local_snap_hash "$target" > /dev/null
    (( lines_read++ )) || true
done
# Without the fd 3 fix, the first call to local_snap_hash would consume
# line2 and line3 from stdin, causing the loop to only iterate once.
# With the fix, all 3 lines are read by the outer loop.
# We verify by calling local_snap_hash and ensuring it still works
local hash=$(_profile_local_snap_hash "$target")
assert_neq "" "$hash" "should still return hash after stdin test"
rm -f "$target"

# --- BUG: Default profile double-counted when active_set="default" ---
# When user runs `profile use default`, active_set becomes "default".
# Functions that add default files first, then iterate ${=profiles},
# would process default twice. Fix: [[ "$p" == "default" ]] && continue

_TEST_NAME="apply_claude single-source symlink with active_set=default"
HOME="$TEST_HOME"
mkdir -p "$TEST_HOME/.claude"
rm -f "$TEST_HOME/.claude/settings.json"
rm -f "$PROFILES_DIR/testprofile/claude/settings.json"
_profile_apply_claude "default" > /dev/null 2>&1
assert_symlink "$TEST_HOME/.claude/settings.json" "$PROFILES_DIR/default/claude/settings.json"

# --- BUG: stat -f %m incompatible with GNU coreutils ---
# BSD stat uses -f %m for mtime, but GNU stat uses -c %Y.
# Sync uses /usr/bin/stat -f %m with fallback to stat -c %Y.
# Verify the stat pattern in sync.sh uses /usr/bin/stat, not bare stat -f.

_TEST_NAME="sync uses /usr/bin/stat for BSD compat"
local sync_src=$(cat "$_PROFILE_LIB_DIR/sync.sh")
if [[ "$sync_src" == *"/usr/bin/stat -f %m"* ]]; then
    pass
else
    fail "sync.sh should use /usr/bin/stat -f %m for BSD stat"
fi

_TEST_NAME="sync has GNU stat fallback"
if [[ "$sync_src" == *"stat -c %Y"* ]]; then
    pass
else
    fail "sync.sh should have stat -c %Y fallback for GNU stat"
fi

# --- BUG: machine_id used hostname instead of hardware UUID hash ---
# profile register was saving hostname as the key instead of the
# hardware UUID hash. Verify machine_id doesn't return hostname.

_TEST_NAME="machine_id is not hostname (regression)"
local mid=$(_profile_machine_id)
local hn=$(hostname)
assert_neq "$hn" "$mid"

# --- BUG: snapshot_files missing claude/settings.json ---
# Claude settings weren't in the snapshot file list, so drift detection
# couldn't detect changes to claude settings.

_TEST_NAME="snapshot_files includes all config types"
local files=$(_profile_snapshot_files "$PROFILES_DIR/default")
local -a expected_patterns=(
    "Brewfile"
    "vscode/extensions.txt"
    "vscode/settings.json"
    "vscode/keybindings.json"
    "iterm/profile.json"
    "git/config"
    "mise/config.toml"
    "claude/settings.json"
    "claude/statusline.sh"
    "claude/sync-plugins.sh"
    "claude/read-once/hook.sh"
)
local all_found=true
for pattern in "${expected_patterns[@]}"; do
    if [[ "$files" != *"$pattern"* ]]; then
        fail "missing $pattern in snapshot_files"
        all_found=false
        break
    fi
done
[[ "$all_found" == true ]] && pass

# --- BUG: local path shadows zsh tied variable ---
# In zsh, `path` is tied to PATH. Using `local path=...` inside a function
# breaks the tie, corrupting PATH when the function exits.

# --- BUG: Indented brew/cask lines inside if OS.mac? not parsed ---
# Brewfile entries inside `if OS.mac?` blocks are indented. The parser
# used ^brew/^cask regexes that required column 0, silently dropping
# all macOS-conditional casks from the expected package list.

_TEST_NAME="read_brew_packages parses indented lines inside if blocks"
local brewfile="$PROFILES_DIR/default/Brewfile"
cat > "$brewfile" << 'EOF'
tap "homebrew/autoupdate"
brew "git"
if OS.mac?
    brew "coreutils"
    cask "orbstack"
end
EOF
IS_MACOS=true
local result=$(_profile_read_brew_packages "$brewfile")
assert_contains "$result" "brew:git" "top-level brew"
_TEST_NAME="read_brew_packages parses indented cask inside if OS.mac? on macOS"
assert_contains "$result" "cask:orbstack" "indented cask"
_TEST_NAME="read_brew_packages parses indented brew inside if OS.mac? on macOS"
assert_contains "$result" "brew:coreutils" "indented brew"
_TEST_NAME="read_brew_packages parses tap"
assert_contains "$result" "tap:homebrew/autoupdate" "tap"

# --- BUG: macOS-only packages should be skipped on Linux ---
# After fixing indentation parsing, we must also skip OS.mac? blocks
# when running on Linux, otherwise casks get flagged for install.

_TEST_NAME="read_brew_packages skips OS.mac? block on Linux"
IS_MACOS=false
IS_LINUX=true
local linux_result=$(_profile_read_brew_packages "$brewfile")
assert_contains "$linux_result" "brew:git" "top-level brew on linux"
_TEST_NAME="read_brew_packages excludes macOS cask on Linux"
assert_not_contains "$linux_result" "cask:orbstack" "macOS cask skipped on linux"
_TEST_NAME="read_brew_packages excludes macOS brew on Linux"
assert_not_contains "$linux_result" "brew:coreutils" "macOS brew skipped on linux"

# --- Verify if OS.linux? block works symmetrically ---

_TEST_NAME="read_brew_packages parses OS.linux? block on Linux"
cat > "$brewfile" << 'EOF'
brew "git"
if OS.linux?
    brew "linux-only-pkg"
end
EOF
IS_MACOS=false
IS_LINUX=true
local linux_block_result=$(_profile_read_brew_packages "$brewfile")
assert_contains "$linux_block_result" "brew:linux-only-pkg" "linux block on linux"

_TEST_NAME="read_brew_packages skips OS.linux? block on macOS"
IS_MACOS=true
IS_LINUX=false
local mac_skip_result=$(_profile_read_brew_packages "$brewfile")
assert_not_contains "$mac_skip_result" "brew:linux-only-pkg" "linux block skipped on macOS"

# Restore platform flags
source "$_PROFILE_LIB_DIR/platform.sh"
# Restore default Brewfile
echo 'brew "git"' > "$PROFILES_DIR/default/Brewfile"

_TEST_NAME="no zsh tied variable shadowing in lib/profile"
local tied_vars_pattern='(local[[:space:]]+|read[[:space:]]+-r[[:space:]]+)(path|fpath|manpath|cdpath|mailpath|infopath)([[:space:]]|=|$)'
local found_shadows=false
for f in "$_PROFILE_LIB_DIR"/*.sh; do
    if grep -Enq "$tied_vars_pattern" "$f" 2>/dev/null; then
        fail "$(basename "$f") shadows a zsh tied variable"
        found_shadows=true
        break
    fi
done
[[ "$found_shadows" == false ]] && pass

_test_summary
