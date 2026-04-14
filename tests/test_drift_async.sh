#!/usr/bin/env zsh
# Test async drift check: cache staleness, cached output, pidfile dedup

source "${0:A:h}/harness.sh"

HOME="$TEST_HOME"
PROFILE_DRIFT_CACHE="$TEST_STATE/drift-cache"

# --- _profile_drift_cache_stale ---

_TEST_NAME="drift_cache_stale returns stale when no cache exists"
rm -f "$PROFILE_DRIFT_CACHE"
_profile_drift_cache_stale
assert_eq "0" "$?"

_TEST_NAME="drift_cache_stale returns fresh after cache is written"
echo "cached result" > "$PROFILE_DRIFT_CACHE"
_profile_drift_cache_stale
assert_eq "1" "$?"

_TEST_NAME="drift_cache_stale returns stale when cache is old"
touch -t 200001010000.00 "$PROFILE_DRIFT_CACHE"
_profile_drift_cache_stale
assert_eq "0" "$?"

# --- _profile_check_drift_async: cached output ---

_TEST_NAME="check_drift_async shows cached output"
echo "Profile(s) 'default' have safe changes ready to sync." > "$PROFILE_DRIFT_CACHE"
touch "$PROFILE_DRIFT_CACHE"  # reset mtime to now (fresh cache)
local output=$(_profile_check_drift_async 2>/dev/null)
assert_contains "$output" "safe changes ready to sync"

_TEST_NAME="check_drift_async shows nothing when cache is empty"
: > "$PROFILE_DRIFT_CACHE"
touch "$PROFILE_DRIFT_CACHE"
local empty_output=$(_profile_check_drift_async 2>/dev/null)
assert_eq "" "$empty_output"

# --- _profile_check_drift_async: skip fork when fresh ---

_TEST_NAME="check_drift_async does not fork when cache is fresh"
echo "cached" > "$PROFILE_DRIFT_CACHE"
touch "$PROFILE_DRIFT_CACHE"
local pidfile="$PROFILE_STATE_DIR/drift-check.pid"
rm -f "$pidfile"
_profile_check_drift_async 2>/dev/null
# Wait briefly for any background fork to start
sleep 0.1
if [[ -f "$pidfile" ]]; then
    fail "pidfile created despite fresh cache"
else
    pass
fi

# --- _profile_check_drift_async: background fork ---

_TEST_NAME="check_drift_async forks background check when cache is stale"
# Stub _profile_check_drift to produce known output quickly
_profile_check_drift() { echo "background result"; }
rm -f "$PROFILE_DRIFT_CACHE" "$pidfile"
_profile_check_drift_async 2>/dev/null
# Wait for background to complete
sleep 0.5
local bg_result=""
[[ -f "$PROFILE_DRIFT_CACHE" ]] && bg_result=$(<"$PROFILE_DRIFT_CACHE")
assert_eq "background result" "$bg_result"

# --- Pidfile dedup ---

_TEST_NAME="pidfile with live PID prevents duplicate fork"
_profile_check_drift() { echo "should not run"; }
rm -f "$PROFILE_DRIFT_CACHE"
echo $$ > "$pidfile"  # current shell PID is alive
_profile_check_drift_async 2>/dev/null
sleep 0.1
# Cache should not have been written (no fork happened)
if [[ -f "$PROFILE_DRIFT_CACHE" ]]; then
    fail "background fork ran despite live pidfile"
else
    pass
fi
rm -f "$pidfile"

_TEST_NAME="stale pidfile with dead PID gets cleaned up"
_profile_check_drift() { echo "recovered"; }
rm -f "$PROFILE_DRIFT_CACHE"
echo 99999 > "$pidfile"  # dead PID
_profile_check_drift_async 2>/dev/null
sleep 0.5
local recovered=""
[[ -f "$PROFILE_DRIFT_CACHE" ]] && recovered=$(<"$PROFILE_DRIFT_CACHE")
assert_eq "recovered" "$recovered"

_test_summary
