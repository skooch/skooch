#!/usr/bin/env zsh
# Test remote-aware sync preflight decisions

source "${0:A:h}/harness.sh"

HOME="$TEST_HOME"
mkdir -p "$TEST_DOTFILES/.git"

typeset -g PRETEND_DIRTY=false
typeset -g PULL_CALLED=false
typeset -g PULL_EXIT=0
typeset -g PULL_STDERR=""

git() {
    case "$3" in
        rev-parse)
            return 0
            ;;
        fetch)
            return 0
            ;;
        rev-list)
            printf '0\t2\n'
            return 0
            ;;
        status)
            [[ "$PRETEND_DIRTY" == true ]] && echo " M profiles/default/codex/config.toml"
            return 0
            ;;
        pull)
            PULL_CALLED=true
            [[ -n "$PULL_STDERR" ]] && echo "$PULL_STDERR" >&2
            return "$PULL_EXIT"
            ;;
    esac
    return 0
}

_TEST_NAME="sync_preflight attempts fast-forward even when the worktree is dirty"
PRETEND_DIRTY=true
PULL_CALLED=false
PULL_EXIT=0
PULL_STDERR=""
local dirty_ok_log=$(mktemp)
_profile_sync_preflight >"$dirty_ok_log" 2>&1
local dirty_ok_status=$?
rm -f "$dirty_ok_log"
assert_eq "0" "$dirty_ok_status"
assert_eq "true" "$PULL_CALLED"

_TEST_NAME="sync_preflight reports a helpful error when a dirty worktree blocks the fast-forward"
PRETEND_DIRTY=true
PULL_CALLED=false
PULL_EXIT=1
PULL_STDERR="error: Your local changes to the following files would be overwritten by merge"
local dirty_fail_log=$(mktemp)
_profile_sync_preflight >"$dirty_fail_log" 2>&1
local dirty_fail_status=$?
local dirty_fail_output=$(cat "$dirty_fail_log")
rm -f "$dirty_fail_log"
assert_eq "1" "$dirty_fail_status"
assert_eq "true" "$PULL_CALLED"
assert_contains "$dirty_fail_output" "Fast-forward failed"
assert_contains "$dirty_fail_output" "Commit or stash the conflicting files"

_TEST_NAME="sync_preflight fast-forwards a clean repo that is behind upstream"
PRETEND_DIRTY=false
PULL_CALLED=false
PULL_EXIT=0
PULL_STDERR=""
local clean_log=$(mktemp)
_profile_sync_preflight >"$clean_log" 2>&1
local clean_status=$?
rm -f "$clean_log"
assert_eq "0" "$clean_status"
assert_eq "true" "$PULL_CALLED"

_test_summary
