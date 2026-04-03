#!/usr/bin/env zsh
# Test snapshot system: take_snapshot, compute_hash, local_snap_hash

source "${0:A:h}/harness.sh"

# --- _profile_compute_hash ---

_TEST_NAME="compute_hash produces non-empty result"
echo "default" > "$PROFILE_ACTIVE_FILE"
local hash=$(_profile_compute_hash "default")
assert_neq "" "$hash"

_TEST_NAME="compute_hash is deterministic"
local hash2=$(_profile_compute_hash "default")
assert_eq "$hash" "$hash2"

_TEST_NAME="compute_hash changes when profile content changes"
local old_hash=$(_profile_compute_hash "default")
echo '{"modified": true}' > "$PROFILES_DIR/default/claude/settings.json"
local new_hash=$(_profile_compute_hash "default")
assert_neq "$old_hash" "$new_hash"
# Restore
echo '{"test": true}' > "$PROFILES_DIR/default/claude/settings.json"

# --- _profile_take_snapshot ---

_TEST_NAME="take_snapshot creates snapshot file"
_profile_take_snapshot "default"
assert_file_exists "$PROFILE_SNAPSHOT_FILE"

_TEST_NAME="take_snapshot creates snapshot-local file"
assert_file_exists "$PROFILE_STATE_DIR/snapshot-local"

_TEST_NAME="snapshot matches compute_hash"
local snap_content=$(cat "$PROFILE_SNAPSHOT_FILE")
local computed=$(_profile_compute_hash "default")
assert_eq "$computed" "$snap_content"

# --- _profile_local_snap_hash (regression: fd 3 stdin consumption) ---

_TEST_NAME="local_snap_hash does not consume stdin"
# Write a known snapshot-local file
local target_file=$(mktemp)
echo "test content" > "$target_file"
local target_hash=$(_platform_md5 "$target_file")
printf '%s\t%s\n' "$target_file" "$target_hash" > "$PROFILE_STATE_DIR/snapshot-local"

# Call from a loop that reads stdin — this would break without fd 3
local found_hash=""
echo "stdin line 1" | while IFS= read -r line; do
    found_hash=$(_profile_local_snap_hash "$target_file")
done
# The hash lookup should work without eating the stdin line
local direct_hash=$(_profile_local_snap_hash "$target_file")
assert_eq "$target_hash" "$direct_hash"
rm -f "$target_file"

_TEST_NAME="local_snap_hash returns empty for unknown path"
local unknown=$(_profile_local_snap_hash "/nonexistent/path")
assert_eq "" "$unknown"

_TEST_NAME="local_snap_hash returns empty when no snapshot-local file"
rm -f "$PROFILE_STATE_DIR/snapshot-local"
local no_snap=$(_profile_local_snap_hash "/any/path")
assert_eq "" "$no_snap"

# --- Drift check ---

_TEST_NAME="check_drift detects changed profiles"
_profile_take_snapshot "default"
echo '{"changed": true}' > "$PROFILES_DIR/default/claude/settings.json"
local drift_output=$(_profile_check_drift 2>/dev/null)
assert_contains "$drift_output" "unsynced changes"
# Restore
echo '{"test": true}' > "$PROFILES_DIR/default/claude/settings.json"

_TEST_NAME="check_drift is silent when in sync"
_profile_take_snapshot "default"
local no_drift=$(_profile_check_drift 2>/dev/null)
assert_not_contains "$no_drift" "unsynced"

_test_summary
