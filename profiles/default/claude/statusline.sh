#!/usr/bin/env bash
# Claude Code statusline: context usage, account usage, pwd, branch
set -euo pipefail
shopt -s extglob

INPUT=$(cat)

# Format seconds until reset as compact duration (1d5h, 5h, 23m)
fmt_reset() {
  local resets_at="$1"
  if [[ -z "$resets_at" || "$resets_at" == "null" ]]; then
    echo ""
    return
  fi
  local reset_epoch now_epoch diff_s days hours mins
  reset_epoch=$(date -jf "%Y-%m-%dT%H:%M:%S" "${resets_at%%.*}" "+%s" 2>/dev/null || date -d "$resets_at" "+%s" 2>/dev/null || echo "")
  if [[ -z "$reset_epoch" ]]; then
    echo ""
    return
  fi
  now_epoch=$(date "+%s")
  diff_s=$((reset_epoch - now_epoch))
  if [[ $diff_s -le 0 ]]; then
    echo "now"
    return
  fi
  days=$((diff_s / 86400))
  hours=$(( (diff_s % 86400) / 3600 ))
  mins=$(( (diff_s % 3600) / 60 ))
  if [[ $days -gt 0 ]]; then
    echo "${days}d${hours}h"
  elif [[ $hours -gt 0 ]]; then
    echo "${hours}h${mins}m"
  else
    echo "${mins}m"
  fi
}

# Parse JSON fields
ctx_pct=$(echo "$INPUT" | jq -r '.context_window.used_percentage // "?"')
five_hr_pct=$(echo "$INPUT" | jq -r '.rate_limits.five_hour.used_percentage // "?"')
five_hr_reset=$(echo "$INPUT" | jq -r '.rate_limits.five_hour.resets_at // ""')
seven_day_pct=$(echo "$INPUT" | jq -r '.rate_limits.seven_day.used_percentage // "?"')
seven_day_reset=$(echo "$INPUT" | jq -r '.rate_limits.seven_day.resets_at // ""')
cwd=$(echo "$INPUT" | jq -r '.cwd // ""')

# Shorten home dir and strip trailing dots
cwd="${cwd/#$HOME/~}"
if [[ $(echo "$cwd" | tr '/' '\n' | wc -l) -gt 3 ]]; then
  cwd="${cwd##*/}"
fi
cwd="${cwd%%+(.)}"

# Get git branch
branch=""
if command -v git &>/dev/null; then
  branch=$(git -C "$(echo "$INPUT" | jq -r '.cwd // "."')" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
fi

# Build output
parts=()
parts+=("ctx:${ctx_pct}%")

if [[ "$five_hr_pct" != "?" ]]; then
  reset_str=$(fmt_reset "$five_hr_reset")
  if [[ -n "$reset_str" ]]; then
    parts+=("5h:${five_hr_pct}%/${reset_str}")
  else
    parts+=("5h:${five_hr_pct}%")
  fi
fi
if [[ "$seven_day_pct" != "?" ]]; then
  reset_str=$(fmt_reset "$seven_day_reset")
  if [[ -n "$reset_str" ]]; then
    parts+=("7d:${seven_day_pct}%/${reset_str}")
  else
    parts+=("7d:${seven_day_pct}%")
  fi
fi

parts+=("$cwd")

if [[ -n "$branch" ]]; then
  parts+=("[$branch]")
fi

echo "${parts[*]}"
