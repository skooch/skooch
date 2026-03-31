#!/usr/bin/env bash
# Claude Code statusline: context usage, account usage, pwd, branch
set -euo pipefail

INPUT=$(cat)

# Parse JSON fields
ctx_pct=$(echo "$INPUT" | jq -r '.context_window.used_percentage // "?"')
five_hr=$(echo "$INPUT" | jq -r '.rate_limits.five_hour.used_percentage // "?"')
seven_day=$(echo "$INPUT" | jq -r '.rate_limits.seven_day.used_percentage // "?"')
cwd=$(echo "$INPUT" | jq -r '.cwd // ""')

# Shorten home dir
cwd="${cwd/#$HOME/~}"
# Show only last 2 path components if long
if [[ $(echo "$cwd" | tr '/' '\n' | wc -l) -gt 3 ]]; then
  cwd=".../${cwd##*/}"
fi

# Get git branch
branch=""
if command -v git &>/dev/null; then
  branch=$(git -C "$(echo "$INPUT" | jq -r '.cwd // "."')" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
fi

# Build output
parts=()
parts+=("ctx:${ctx_pct}%")

if [[ "$five_hr" != "?" ]]; then
  parts+=("5h:${five_hr}%")
fi
if [[ "$seven_day" != "?" ]]; then
  parts+=("7d:${seven_day}%")
fi

parts+=("$cwd")

if [[ -n "$branch" ]]; then
  parts+=("[$branch]")
fi

echo "${parts[*]}"
