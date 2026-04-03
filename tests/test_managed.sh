#!/usr/bin/env zsh
# Test managed files tracking and overwrite detection

source "${0:A:h}/harness.sh"

# --- _profile_write_managed / _profile_is_managed ---

_TEST_NAME="write_managed creates managed file"
_profile_write_managed "/path/one" "/path/two"
assert_file_exists "$PROFILE_MANAGED_FILE"

_TEST_NAME="is_managed returns true for managed path"
if _profile_is_managed "/path/one"; then
    pass
else
    fail "should be managed"
fi

_TEST_NAME="is_managed returns false for unmanaged path"
if _profile_is_managed "/path/unknown"; then
    fail "should not be managed"
else
    pass
fi

# --- _profile_check_overwrite ---

HOME="$TEST_HOME"

_TEST_NAME="check_overwrite passes when files are managed"
mkdir -p "$TEST_HOME/.claude"
echo '{}' > "$TEST_HOME/.claude/settings.json"
_profile_write_managed "$TEST_HOME/.claude/settings.json"
if _profile_check_overwrite "default" < /dev/null > /dev/null 2>&1; then
    pass
else
    fail "should pass for managed files"
fi

_TEST_NAME="check_overwrite warns about unmanaged files"
echo "unmanaged" > "$TEST_HOME/.gitconfig"
: > "$PROFILE_MANAGED_FILE"  # clear managed list
local output=$(echo "n" | _profile_check_overwrite "default" 2>&1)
assert_contains "$output" "unmanaged"

_test_summary
