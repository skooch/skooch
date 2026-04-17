---
name: codebase-memory-quality
description: Code quality analysis expert. ALWAYS invoke this skill when the user asks about dead code, unused functions, complexity, refactor candidates, or cleanup opportunities. Do not search files manually — use codebase-memory-mcp search_graph with degree filters first.
---

# Code Quality Analysis

Use codebase-memory-mcp tools for quality analysis:

## Dead Code Detection
- `search_graph(max_degree=0, exclude_entry_points=true)` — find unreferenced functions
- `search_graph(max_degree=0, label="Function")` — unreferenced functions only

## Complexity Analysis
- `search_graph(min_degree=10)` — high fan-out functions
- `search_graph(label="Function", sort_by="degree")` — most-connected functions
