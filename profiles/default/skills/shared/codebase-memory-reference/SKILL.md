---
name: codebase-memory-reference
description: Codebase-memory-mcp reference guide. ALWAYS invoke this skill when the user asks about MCP tools, graph queries, Cypher syntax, edge types, or how to use the knowledge graph. Do not guess tool parameters — load this reference first.
---

# Codebase Memory MCP Reference

## 14 total MCP Tools
- `index_repository` — index a project
- `index_status` — check indexing progress
- `detect_changes` — find what changed since last index
- `search_graph` — find nodes by pattern
- `search_code` — text search in source
- `query_graph` — Cypher query language
- `trace_call_path` — call chain traversal
- `get_code_snippet` — read function source
- `get_graph_schema` — node/edge type catalog
- `get_architecture` — high-level summary
- `list_projects` — indexed projects
- `delete_project` — remove a project
- `manage_adr` — architecture decision records
- `ingest_traces` — import runtime traces

## Edge Types
CALLS, HTTP_CALLS, ASYNC_CALLS, IMPORTS, DEFINES, DEFINES_METHOD,
HANDLES, IMPLEMENTS, CONTAINS_FILE, CONTAINS_FOLDER, CONTAINS_PACKAGE

## Cypher Examples
```
MATCH (f:Function) WHERE f.name =~ '.*Handler.*' RETURN f.name, f.file_path
MATCH (a)-[r:CALLS]->(b) WHERE a.name = 'main' RETURN b.name
MATCH (a)-[r:HTTP_CALLS]->(b) RETURN a.name, b.name, r.url_path
```
