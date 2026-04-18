#!/usr/bin/env zsh
# Test runner for dotfiles profile system
# Usage: tests/run.sh [filter]
#   filter: optional substring to match test file names (e.g. "sync" runs test_sync.sh)

set -euo pipefail

# Isolate sandbox state from any git env vars leaked by a parent process.
# When invoked from a git hook (e.g. pre-commit), git exports GIT_DIR,
# GIT_INDEX_FILE, GIT_PREFIX, GIT_WORK_TREE into the hook environment. Any
# child `git` invocation in tests or helpers would otherwise point at the
# caller's git dir instead of the test sandbox.
unset GIT_DIR GIT_INDEX_FILE GIT_PREFIX GIT_WORK_TREE GIT_OBJECT_DIRECTORY GIT_NAMESPACE

TESTS_DIR="${0:A:h}"

# Determine zsh binary
if [[ -z "${ZSH_BIN:-}" ]]; then
    if command -v brew &>/dev/null; then
        ZSH_BIN="$(brew --prefix)/bin/zsh"
    else
        ZSH_BIN="$(command -v zsh)"
    fi
fi
PASS=0
FAIL=0
ERRORS=()

filter="${1:-}"

for test_file in "$TESTS_DIR"/test_*.sh; do
    [[ -f "$test_file" ]] || continue
    name=$(basename "$test_file" .sh)
    if [[ -n "$filter" && "$name" != *"$filter"* ]]; then
        continue
    fi
    echo "--- $name ---"
    if "${ZSH_BIN:-zsh}" "$test_file"; then
        (( PASS++ )) || true
    else
        (( FAIL++ )) || true
        ERRORS+=("$name")
    fi
    echo ""
done

echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo "Failed:"
    printf '  %s\n' "${ERRORS[@]}"
    exit 1
fi
