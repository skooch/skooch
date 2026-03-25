#!/bin/bash
# SubagentStart hook: logs subagent spawns and injects opus model reminder
# Input: JSON via stdin with agent_id, agent_type, session_id, etc.

INPUT=$(cat)
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // "unknown"')
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // "unknown"')
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Log to file for audit trail
LOG_FILE="$HOME/.claude/hooks/subagent-spawns.log"
echo "[$TIMESTAMP] SubagentStart: type=$AGENT_TYPE id=$AGENT_ID" >> "$LOG_FILE"

# Inject context reminding the subagent about the opus policy
cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"IMPORTANT: You are running under an Opus-only policy. If you need to dispatch any further work, always use model: opus. Never downgrade to sonnet or haiku."}}
EOF
