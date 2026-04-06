#!/usr/bin/env zsh
# Test relative symlink helpers: _profile_relpath, _profile_ln_s, _profile_ln_sn, _profile_symlink_matches

source "${0:A:h}/harness.sh"

HOME="$TEST_HOME"

# Create all directories needed for relpath tests
mkdir -p "$TEST_HOME/a/b" "$TEST_HOME/a/c" "$TEST_HOME/x/y/z" "$TEST_HOME/alpha" "$TEST_HOME/beta"

# --- _profile_relpath ---

_TEST_NAME="relpath: sibling directories"
local result=$(_profile_relpath "$TEST_HOME/a/b/file.txt" "$TEST_HOME/a/c")
assert_eq "../b/file.txt" "$result"

_TEST_NAME="relpath: same directory"
result=$(_profile_relpath "$TEST_HOME/a/file.txt" "$TEST_HOME/a")
assert_eq "file.txt" "$result"

_TEST_NAME="relpath: nested deeper source"
result=$(_profile_relpath "$TEST_HOME/x/y/z/deep.txt" "$TEST_HOME/x")
assert_eq "y/z/deep.txt" "$result"

_TEST_NAME="relpath: target deeper than source"
result=$(_profile_relpath "$TEST_HOME/top.txt" "$TEST_HOME/x/y/z")
assert_eq "../../../top.txt" "$result"

_TEST_NAME="relpath: completely disjoint paths"
result=$(_profile_relpath "$TEST_HOME/alpha/file" "$TEST_HOME/beta")
assert_eq "../alpha/file" "$result"

# --- _profile_ln_s (file symlink) ---

_TEST_NAME="ln_s creates a relative symlink to a file"
echo "hello" > "$TEST_HOME/a/source.txt"
mkdir -p "$TEST_HOME/link_target_dir"
_profile_ln_s "$TEST_HOME/a/source.txt" "$TEST_HOME/link_target_dir/link.txt"
local raw=$(readlink "$TEST_HOME/link_target_dir/link.txt")
# Should be relative, not absolute
if [[ "$raw" == /* ]]; then
    fail "symlink is absolute: $raw"
else
    pass
fi

_TEST_NAME="ln_s relative symlink resolves correctly"
local content=$(cat "$TEST_HOME/link_target_dir/link.txt")
assert_eq "hello" "$content"

_TEST_NAME="ln_s overwrites existing symlink"
echo "world" > "$TEST_HOME/a/other.txt"
_profile_ln_s "$TEST_HOME/a/other.txt" "$TEST_HOME/link_target_dir/link.txt"
content=$(cat "$TEST_HOME/link_target_dir/link.txt")
assert_eq "world" "$content"

# --- _profile_ln_sn (directory symlink) ---

_TEST_NAME="ln_sn creates a relative symlink to a directory"
mkdir -p "$TEST_HOME/src_dir/sub"
echo "in dir" > "$TEST_HOME/src_dir/sub/data.txt"
_profile_ln_sn "$TEST_HOME/src_dir/sub" "$TEST_HOME/link_target_dir/dir_link"
raw=$(readlink "$TEST_HOME/link_target_dir/dir_link")
if [[ "$raw" == /* ]]; then
    fail "directory symlink is absolute: $raw"
else
    pass
fi

_TEST_NAME="ln_sn directory symlink resolves correctly"
content=$(cat "$TEST_HOME/link_target_dir/dir_link/data.txt")
assert_eq "in dir" "$content"

# --- _profile_symlink_matches ---

_TEST_NAME="symlink_matches returns true for matching relative symlink"
_profile_ln_s "$TEST_HOME/a/source.txt" "$TEST_HOME/link_target_dir/match_test"
if _profile_symlink_matches "$TEST_HOME/link_target_dir/match_test" "$TEST_HOME/a/source.txt"; then
    pass
else
    fail "symlink_matches should return true for correct relative symlink"
fi

_TEST_NAME="symlink_matches returns true for matching absolute symlink (backwards compat)"
ln -sf "$TEST_HOME/a/source.txt" "$TEST_HOME/link_target_dir/abs_test"
if _profile_symlink_matches "$TEST_HOME/link_target_dir/abs_test" "$TEST_HOME/a/source.txt"; then
    pass
else
    fail "symlink_matches should return true for correct absolute symlink"
fi

_TEST_NAME="symlink_matches returns false for wrong target"
_profile_ln_s "$TEST_HOME/a/source.txt" "$TEST_HOME/link_target_dir/wrong_test"
if _profile_symlink_matches "$TEST_HOME/link_target_dir/wrong_test" "$TEST_HOME/a/other.txt"; then
    fail "symlink_matches should return false for wrong target"
else
    pass
fi

_TEST_NAME="symlink_matches returns false for non-symlink"
echo "regular" > "$TEST_HOME/link_target_dir/regular_file"
if _profile_symlink_matches "$TEST_HOME/link_target_dir/regular_file" "$TEST_HOME/a/source.txt"; then
    fail "symlink_matches should return false for regular file"
else
    pass
fi

_TEST_NAME="symlink_matches returns false for nonexistent path"
if _profile_symlink_matches "$TEST_HOME/link_target_dir/does_not_exist" "$TEST_HOME/a/source.txt"; then
    fail "symlink_matches should return false for nonexistent path"
else
    pass
fi

# --- Integration: profile apply creates relative symlinks ---

_TEST_NAME="apply_claude creates relative symlinks for settings"
mkdir -p "$HOME/.claude"
_profile_apply_claude "default" > /dev/null 2>&1
if [[ -L "$HOME/.claude/settings.json" ]]; then
    raw=$(readlink "$HOME/.claude/settings.json")
    if [[ "$raw" == /* ]]; then
        fail "claude settings symlink is absolute: $raw"
    else
        pass
    fi
else
    fail "claude settings.json is not a symlink"
fi

_TEST_NAME="apply_claude relative symlink reads correctly"
local settings_content=$(cat "$HOME/.claude/settings.json" 2>/dev/null)
assert_contains "$settings_content" '"test": true'

_TEST_NAME="apply_mise creates relative symlink for single source"
mkdir -p "$HOME/.config/mise"
_profile_apply_mise "default" > /dev/null 2>&1
if [[ -L "$HOME/.config/mise/config.toml" ]]; then
    raw=$(readlink "$HOME/.config/mise/config.toml")
    if [[ "$raw" == /* ]]; then
        fail "mise config symlink is absolute: $raw"
    else
        pass
    fi
else
    fail "mise config.toml is not a symlink"
fi

_TEST_NAME="ensure_links creates relative symlinks"
touch "$TEST_DOTFILES/.zshenv" "$TEST_DOTFILES/.zshrc" "$TEST_DOTFILES/.zprofile" "$TEST_DOTFILES/.zsh_plugins.txt"
mkdir -p "$TEST_DOTFILES/functions"
_profile_ensure_links > /dev/null 2>&1
raw=$(readlink "$HOME/.zshenv")
if [[ "$raw" == /* ]]; then
    fail "core .zshenv symlink is absolute: $raw"
else
    pass
fi

_test_summary
