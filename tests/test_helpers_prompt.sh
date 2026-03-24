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
