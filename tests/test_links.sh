#!/usr/bin/env zsh
# Test _profile_ensure_links: symlink creation, idempotency, backup

source "${0:A:h}/harness.sh"

# Override HOME so we don't touch real home
HOME="$TEST_HOME"

# Create the source files ensure_links expects
touch "$TEST_DOTFILES/.zshenv" "$TEST_DOTFILES/.zshrc" "$TEST_DOTFILES/.zprofile" "$TEST_DOTFILES/.zsh_plugins.txt"
mkdir -p "$TEST_DOTFILES/functions"

_TEST_NAME="ensure_links creates symlinks"
_profile_ensure_links > /dev/null 2>&1
assert_symlink "$TEST_HOME/.zshenv" "$TEST_DOTFILES/.zshenv"

_TEST_NAME="ensure_links creates .zshrc symlink"
assert_symlink "$TEST_HOME/.zshrc" "$TEST_DOTFILES/.zshrc"

_TEST_NAME="ensure_links creates .zprofile symlink"
assert_symlink "$TEST_HOME/.zprofile" "$TEST_DOTFILES/.zprofile"

_TEST_NAME="ensure_links creates .zsh_plugins.txt symlink"
assert_symlink "$TEST_HOME/.zsh_plugins.txt" "$TEST_DOTFILES/.zsh_plugins.txt"

_TEST_NAME="ensure_links creates .zsh_functions dir symlink"
assert_symlink "$TEST_HOME/.zsh_functions" "$TEST_DOTFILES/functions"

_TEST_NAME="ensure_links is idempotent (no output on re-run)"
local output=$(_profile_ensure_links 2>&1)
assert_eq "" "$output" "should produce no output when links already correct"

_TEST_NAME="ensure_links backs up existing regular files"
rm "$TEST_HOME/.zshenv"
echo "existing content" > "$TEST_HOME/.zshenv"
local output=$(_profile_ensure_links 2>&1)
assert_contains "$output" "Backed up"
assert_file_exists "$TEST_HOME/.zshenv.bak"
assert_symlink "$TEST_HOME/.zshenv" "$TEST_DOTFILES/.zshenv"

_test_summary
