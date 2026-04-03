#!/usr/bin/env zsh
# Test machine ID: uses hardware UUID hash, not hostname

source "${0:A:h}/harness.sh"

# --- _profile_machine_id ---

_TEST_NAME="machine_id returns 12-char hex string"
local mid=$(_profile_machine_id)
assert_eq "12" "${#mid}" "length should be 12"

_TEST_NAME="machine_id is hex characters only"
if [[ "$mid" =~ ^[0-9a-f]{12}$ ]]; then
    pass
else
    fail "expected hex, got '$mid'"
fi

_TEST_NAME="machine_id is deterministic"
local mid2=$(_profile_machine_id)
assert_eq "$mid" "$mid2"

_TEST_NAME="machine_id is not the hostname"
local hostname_val=$(hostname)
assert_neq "$hostname_val" "$mid" "should not match hostname"

_TEST_NAME="machine_id is not the raw hardware UUID/machine-id"
if [[ "$(uname -s)" == "Darwin" ]]; then
    local raw_uuid=$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformUUID/{print $4}')
    assert_neq "$raw_uuid" "$mid" "should not be raw UUID"
elif [[ -f /etc/machine-id ]]; then
    local raw_uuid=$(cat /etc/machine-id)
    assert_neq "$raw_uuid" "$mid" "should not be raw machine-id"
else
    pass
fi

_test_summary
