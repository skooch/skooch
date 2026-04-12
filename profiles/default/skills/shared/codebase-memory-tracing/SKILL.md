---
name: codebase-memory-tracing
description: Call chain and dependency expert. ALWAYS invoke this skill when the user asks who calls a function, what a function calls, needs impact analysis, or traces dependencies. Do not grep for function names directly — use codebase-memory-mcp trace_call_path first.
---

# Call Tracing & Impact Analysis

Use codebase-memory-mcp tools to trace call paths:

## Workflow
1. `search_graph(name_pattern=".*FuncName.*")` — find exact function name
2. `trace_call_path(function_name="FuncName", direction="both")` — trace callers + callees
3. `detect_changes` — find what changed and assess risk_labels

## Direction Options
- `inbound` — who calls this function?
- `outbound` — what does this function call?
- `both` — full context (callers + callees)
