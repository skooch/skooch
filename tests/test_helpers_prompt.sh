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

_test_summary
