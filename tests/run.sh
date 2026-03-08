#!/usr/bin/env zsh
# Test runner for dotfiles profile system
# Usage: tests/run.sh [filter]
#   filter: optional substring to match test file names (e.g. "sync" runs test_sync.sh)

set -euo pipefail

TESTS_DIR="${0:A:h}"
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
    if /opt/homebrew/bin/zsh "$test_file"; then
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
