#!/usr/bin/env zsh
# Test that all profile modules load correctly and key functions exist

source "${0:A:h}/harness.sh"

_TEST_NAME="profile function exists"
assert_eq "function" "$(whence -w profile | awk '{print $2}')"

_TEST_NAME="_profile_ensure_links exists"
assert_eq "function" "$(whence -w _profile_ensure_links | awk '{print $2}')"

_TEST_NAME="_profile_sync_config exists"
assert_eq "function" "$(whence -w _profile_sync_config | awk '{print $2}')"

_TEST_NAME="_profile_apply_claude exists"
assert_eq "function" "$(whence -w _profile_apply_claude | awk '{print $2}')"

_TEST_NAME="_profile_diff exists"
assert_eq "function" "$(whence -w _profile_diff | awk '{print $2}')"

_TEST_NAME="_profile_take_snapshot exists"
assert_eq "function" "$(whence -w _profile_take_snapshot | awk '{print $2}')"

_TEST_NAME="_profile_check_drift exists"
assert_eq "function" "$(whence -w _profile_check_drift | awk '{print $2}')"

_TEST_NAME="_profile_machine_id exists"
assert_eq "function" "$(whence -w _profile_machine_id | awk '{print $2}')"

_TEST_NAME="_profile_collect_dirs exists"
assert_eq "function" "$(whence -w _profile_collect_dirs | awk '{print $2}')"

_TEST_NAME="_profile_dedup_dotfiles exists"
assert_eq "function" "$(whence -w _profile_dedup_dotfiles | awk '{print $2}')"

_TEST_NAME="_profile_register exists"
assert_eq "function" "$(whence -w _profile_register | awk '{print $2}')"

_TEST_NAME="_profile_sync_brew exists"
assert_eq "function" "$(whence -w _profile_sync_brew | awk '{print $2}')"

_TEST_NAME="_profile_sync_vscode exists"
assert_eq "function" "$(whence -w _profile_sync_vscode | awk '{print $2}')"

_TEST_NAME="_profile_sync_mise exists"
assert_eq "function" "$(whence -w _profile_sync_mise | awk '{print $2}')"

_TEST_NAME="_profile_sync_claude exists"
assert_eq "function" "$(whence -w _profile_sync_claude | awk '{print $2}')"

_TEST_NAME="_profile_sync_iterm exists"
assert_eq "function" "$(whence -w _profile_sync_iterm | awk '{print $2}')"

_test_summary
