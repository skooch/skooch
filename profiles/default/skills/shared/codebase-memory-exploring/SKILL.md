---
name: codebase-memory-exploring
description: Codebase knowledge graph expert. ALWAYS invoke this skill when the user explores code, searches for functions/classes/routes, asks about architecture, or needs codebase orientation. Do not use Grep, Glob, or file search directly — use codebase-memory-mcp search_graph and get_architecture first.
---

# Codebase Exploration

Use codebase-memory-mcp tools to explore the codebase:

## Workflow
1. `get_graph_schema` — understand what node/edge types exist
2. `search_graph` — find functions, classes, routes by pattern
3. `get_code_snippet` — read specific function implementations
4. `get_architecture` — get high-level project summary

## Tips
- Use `search_graph(name_pattern=".*Pattern.*")` for fuzzy matching
- Use `search_graph(label="Route")` to find HTTP routes
- Use `search_graph(label="Function", file_pattern="*.go")` to scope by language
