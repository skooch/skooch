#!/usr/bin/env zsh
# Test helper functions: collect_dirs, snapshot_files, read_brew, dedup, etc.

source "${0:A:h}/harness.sh"

# --- _profile_collect_dirs ---

_TEST_NAME="collect_dirs includes default first"
local result=$(_profile_collect_dirs "testprofile")
local first_line=$(echo "$result" | head -1)
assert_contains "$first_line" "/default"

_TEST_NAME="collect_dirs includes named profile"
assert_contains "$result" "/testprofile"

_TEST_NAME="collect_dirs does not duplicate default when active_set=default"
local result_default=$(_profile_collect_dirs "default")
local count=$(echo "$result_default" | grep -c "default")
assert_eq "1" "$count" "default should appear exactly once"

_TEST_NAME="collect_dirs with multiple profiles"
mkdir -p "$PROFILES_DIR/extra"
local result_multi=$(_profile_collect_dirs "testprofile extra")
assert_contains "$result_multi" "/testprofile"
assert_contains "$result_multi" "/extra"
rm -rf "$PROFILES_DIR/extra"

# --- _profile_snapshot_files ---

_TEST_NAME="snapshot_files includes claude/settings.json"
local snap_files=$(_profile_snapshot_files "$PROFILES_DIR/default")
assert_contains "$snap_files" "claude/settings.json"

_TEST_NAME="snapshot_files includes git/config"
assert_contains "$snap_files" "git/config"

_TEST_NAME="snapshot_files includes mise/config.toml"
assert_contains "$snap_files" "mise/config.toml"

_TEST_NAME="snapshot_files includes vscode/settings.json"
assert_contains "$snap_files" "vscode/settings.json"

_TEST_NAME="snapshot_files includes iterm/profile.json"
assert_contains "$snap_files" "iterm/profile.json"

_TEST_NAME="snapshot_files includes Brewfile"
assert_contains "$snap_files" "Brewfile"

# --- _profile_read_brew_packages ---

_TEST_NAME="read_brew_packages parses brew lines"
local brewfile=$(mktemp)
cat > "$brewfile" << 'EOF'
brew "git"
brew "jq"
cask "firefox"
tap "homebrew/cask"
# comment line
EOF
local pkgs=$(_profile_read_brew_packages "$brewfile")
assert_contains "$pkgs" "brew:git"
assert_contains "$pkgs" "brew:jq"
assert_contains "$pkgs" "cask:firefox"
assert_contains "$pkgs" "tap:homebrew/cask"
rm -f "$brewfile"

_TEST_NAME="read_brew_packages ignores comments"
local brewfile2=$(mktemp)
echo '# brew "commented"' > "$brewfile2"
echo 'brew "real"' >> "$brewfile2"
local pkgs2=$(_profile_read_brew_packages "$brewfile2")
assert_not_contains "$pkgs2" "commented"
assert_contains "$pkgs2" "brew:real"
rm -f "$brewfile2"

# --- _profile_read_extensions ---

_TEST_NAME="read_extensions parses extension list"
local extfile=$(mktemp)
printf 'ext.one\next.two\n# comment\n  \next.three\n' > "$extfile"
local exts=$(_profile_read_extensions "$extfile")
assert_contains "$exts" "ext.one"
assert_contains "$exts" "ext.two"
assert_contains "$exts" "ext.three"
assert_not_contains "$exts" "comment"
rm -f "$extfile"

# --- _profile_dedup_dotfiles ---

_TEST_NAME="dedup removes duplicate lines"
cat > "$TEST_DOTFILES/.zshenv" << 'EOF'
# comment
export FOO=bar
export BAZ=qux
export FOO=bar
EOF
_profile_dedup_dotfiles > /dev/null 2>&1
local content=$(cat "$TEST_DOTFILES/.zshenv")
local foo_count=$(echo "$content" | grep -c "export FOO=bar")
assert_eq "1" "$foo_count"

_TEST_NAME="dedup preserves comments"
assert_contains "$content" "# comment"

_TEST_NAME="dedup preserves blank lines and structure keywords"
cat > "$TEST_DOTFILES/.zshrc" << 'EOF'
# top comment
if true; then
    echo hello
fi

done
esac
EOF
_profile_dedup_dotfiles > /dev/null 2>&1
local rc_content=$(cat "$TEST_DOTFILES/.zshrc")
assert_contains "$rc_content" "fi"
assert_contains "$rc_content" "done"
assert_contains "$rc_content" "esac"

# --- _profile_active ---

_TEST_NAME="active returns empty when no file"
rm -f "$PROFILE_ACTIVE_FILE"
local active=$(_profile_active)
assert_eq "" "$active"

_TEST_NAME="active returns content of active file"
echo "testprofile" > "$PROFILE_ACTIVE_FILE"
local active2=$(_profile_active)
assert_eq "testprofile" "$active2"

# --- _profile_target_paths ---

_TEST_NAME="target_paths includes gitconfig when git/config exists"
local targets=$(_profile_target_paths "testprofile")
assert_contains "$targets" ".gitconfig"

_TEST_NAME="target_paths includes claude settings when claude/settings.json exists"
assert_contains "$targets" ".claude/settings.json"

_test_summary
