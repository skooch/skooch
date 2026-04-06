#!/bin/sh
# Check if all phases in plan.md are complete

if [ ! -f plan.md ]; then
  exit 0
fi

incomplete=$(grep -c '^\*\*Status:\*\* \(pending\|in_progress\)' plan.md 2>/dev/null || true)
total=$(grep -c '^\*\*Status:\*\*' plan.md 2>/dev/null || true)
complete=$(grep -c '^\*\*Status:\*\* complete' plan.md 2>/dev/null || true)

if [ "$incomplete" -gt 0 ] 2>/dev/null; then
  echo "[todo-plan] $complete/$total phases complete. Incomplete phases remain."
  grep -B2 '^\*\*Status:\*\* \(pending\|in_progress\)' plan.md 2>/dev/null | grep '^###' || true
else
  echo "[todo-plan] All $total phases complete."
fi
