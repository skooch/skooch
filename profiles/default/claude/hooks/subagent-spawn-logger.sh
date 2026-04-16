#!/bin/bash
# SubagentStart hook: logs subagent spawns and injects three-tier model policy reminder.
# Input: JSON via stdin with agent_id, agent_type, session_id, etc.

INPUT=$(cat)
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // "unknown"')
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // "unknown"')
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Log to file for audit trail (rotate at 1MB; keep one previous file as .1)
LOG_FILE="${CLAUDE_SUBAGENT_LOG:-$HOME/.claude/hooks/subagent-spawns.log}"
if [ -f "$LOG_FILE" ]; then
    SIZE=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    [ "$SIZE" -gt 1048576 ] && mv "$LOG_FILE" "$LOG_FILE.1"
fi
echo "[$TIMESTAMP] SubagentStart: type=$AGENT_TYPE id=$AGENT_ID" >> "$LOG_FILE"

# Inject context reminding the subagent about the three-tier model policy
cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"IMPORTANT: Three-tier subagent model policy is in effect. Match the model to the task: Opus for planning, speccing, original thinking, and code implementation. Sonnet for reviewing, scrutinizing, and comparing (code review, diff review, plan review). Haiku for searching, grepping, and exploring the codebase. Never use a heavier model than the task requires."}}
EOF
