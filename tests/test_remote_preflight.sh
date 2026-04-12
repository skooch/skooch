#!/usr/bin/env zsh
# Test remote-aware sync preflight decisions

source "${0:A:h}/harness.sh"

HOME="$TEST_HOME"
mkdir -p "$TEST_DOTFILES/.git"

typeset -g PRETEND_DIRTY=false
typeset -g PULL_CALLED=false

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
            return 0
            ;;
    esac
    return 0
}

_TEST_NAME="sync_preflight blocks a dirty repo that is behind upstream"
PRETEND_DIRTY=true
PULL_CALLED=false
local dirty_log=$(mktemp)
_profile_sync_preflight >"$dirty_log" 2>&1
local dirty_status=$?
local dirty_output=$(cat "$dirty_log")
rm -f "$dirty_log"
assert_eq "1" "$dirty_status"
assert_contains "$dirty_output" "Pull the upstream changes before syncing"

_TEST_NAME="sync_preflight fast-forwards a clean repo that is behind upstream"
PRETEND_DIRTY=false
PULL_CALLED=false
local clean_log=$(mktemp)
_profile_sync_preflight >"$clean_log" 2>&1
local clean_status=$?
rm -f "$clean_log"
assert_eq "0" "$clean_status"
assert_eq "true" "$PULL_CALLED"

_test_summary
