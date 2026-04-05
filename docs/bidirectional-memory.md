# Bidirectional Shared Memory for Claude Code and Codex

## Background

This repo was originally configured around Claude Code, with important project context stored in Claude-specific files such as `.claude/CLAUDE.md`, `.claude/MEMORY.md`, and `.claude/rules/*.md`. `.claude/corrections.md` is separate machine-local scratch space and is not part of shared committed memory.

During the Codex onboarding review, we separated two distinct concerns:

1. **Shared instructions**
   These are stable project rules, conventions, and workflows that should apply to any coding agent or human contributor. This is what `AGENTS.md` is for.

2. **Shared memory**
   This is not the same as documentation. Memory is useful specifically because it can contain recent decisions, temporary constraints, branch-local context, current workstream status, and important recent events that an agent benefits from having injected into context rather than needing to discover by reading docs.

The key architectural point is:

- Documentation is opt-in: an agent can choose whether to read it.
- Memory is intended to be preloaded or injected automatically.

That means documentation cannot fully replace memory.

## What We Observed

### Claude Code side

Claude already has an explicit repo-local memory surface:

- `.claude/MEMORY.md`

This file is being used as a persistent, project-scoped working memory that includes architecture notes, hardware findings, workflow conventions, recent discoveries, and temporary constraints.

### Codex side

In the local Codex environment, we verified that:

- Codex has a home directory at `~/.codex/`
- Codex has a `~/.codex/memories/` directory
- Codex tracks per-thread memory-related state in `~/.codex/state_5.sqlite`
- Codex stores fields such as `memory_mode` and a `raw_memory` column in local state

However, we did **not** find evidence that Codex currently auto-loads a repo-local memory file such as `.codex/MEMORY.md` or `.claude/MEMORY.md`.

The current evidence suggests:

- Codex has a memory mechanism
- some of that memory is synthesized from prior session history and local state
- there is no obvious repo-local binding for this project yet

## Problem Statement

We want a memory system that is:

- shared between Claude Code and Codex
- bidirectional
- repo agnostic in its core design
- capable of holding recent and temporary context, not just permanent docs
- not dependent on one tool's native format as the long-term source of truth

We do **not** want to:

- duplicate overlapping hand-maintained memory files forever
- rely on docs as a substitute for memory
- make `.claude/MEMORY.md` the permanent canonical format for every tool
- tightly couple the shared-memory design to one vendor-specific implementation

## Architectural Conclusion

The right abstraction is a **neutral canonical memory layer** with tool-specific adapters.

That means:

- a shared, tool-agnostic memory store is the source of truth
- Claude gets a projection into `.claude/MEMORY.md`
- Codex gets a projection into whatever memory surface or injection path Codex can consume most reliably
- each tool may still have local-only memory outside the shared layer

This is a different role from `AGENTS.md`:

- `AGENTS.md` is for durable instructions
- shared memory is for injected recent context

## Proposed Architecture

### 1. Canonical shared memory store

Create one neutral memory artifact outside tool-specific formats.

Suggested location options:

- repo-local: `.agent-memory/shared.md`
- repo-local: `.agent-memory/shared.json`
- repo-local: `.agent-memory/shared.yaml`

Recommendation:

- use a repo-local canonical file so the shared memory travels with the repo/worktree context
- keep the schema structured enough for machine sync, but readable enough for humans

A Markdown file with frontmatter is likely the best first version.

Example shape:

```md
---
schema: agent-memory-v1
scope: repo
repo: tdeck-pro-rust
updated_at: 2026-04-02T10:30:00+11:00
updated_by: codex
---

## Active Constraints
- Do not use `AT+CFUN=7` on the A7682E modem.
- Avoid PSRAM/task-allocation recommendations for current memory optimization work.

## Recent Decisions
- Shared cross-agent instructions belong in `AGENTS.md`.
- Shared volatile context should not live only in Claude-specific memory.

## Current Workstreams
- Agent interoperability setup in progress.
- Worktree: `../worktrees/agent-interoperability`.

## Temporary Warnings
- Main checkout is dirty; avoid using it for doc restructuring.

## Recent Events
- 2026-04-02: Initial Codex interoperability review completed.
```

### 2. Tool-specific adapters

#### Claude adapter

A Claude adapter should:

- import shared memory into `.claude/MEMORY.md`
- preserve Claude-local sections that should not be shared
- optionally export approved shared sections back into the canonical store

#### Codex adapter

A Codex adapter should:

- import shared memory into a Codex-consumable memory surface
- preserve Codex-local memory separately
- optionally export approved shared sections back into the canonical store

Because Codex's exact repo-local memory injection mechanism is not yet confirmed, the adapter should initially target a configurable output destination.

Potential destinations:

- `~/.codex/memories/...`
- a future Codex hook/plugin entrypoint
- a generated prompt/include mechanism if Codex exposes one later

### 3. Shared vs local memory partitioning

The canonical shared memory should contain only information appropriate for both tools.

Shared:

- recent decisions
- active technical constraints
- current branch/worktree context
- notable recent findings
- current workstream status
- temporary but cross-tool relevant warnings

Tool-local:

- Claude-specific permissions
- Codex-specific runtime behavior
- UI/editor integration details specific to one tool
- per-tool preferences and operational residue
- secrets or machine-specific credentials

### 4. Controlled bidirectionality

The system should be bidirectional, but not free-form.

Recommended rule:

- only designated shared sections sync both ways
- tool-local sections never sync into the canonical shared store

This avoids garbage, duplication, and accidental leakage of tool-specific operational state.

## Recommended Implementation Plan

### Phase 1: Define the schema

Define a first shared schema, for example `agent-memory-v1`, with explicit sections:

- Active Constraints
- Recent Decisions
- Current Workstreams
- Temporary Warnings
- Recent Events

Keep the first version intentionally small and opinionated.

### Phase 2: Normalize current Claude memory

Refactor `.claude/MEMORY.md` conceptually into:

- shared memory content
- Claude-local memory content

This can be done either by:

- explicit section markers inside `.claude/MEMORY.md`, or
- splitting into `.claude/MEMORY.shared.md` and `.claude/MEMORY.local.md`

Recommendation:

- prefer explicit section markers or a two-file split so automation is deterministic

### Phase 3: Create a repo-local sync tool

Add a repo-local sync tool, for example:

- `scripts/sync_agent_memory.py`

Responsibilities:

- read the canonical shared memory store
- project it into `.claude/MEMORY.md`
- project it into Codex memory output
- optionally merge shared updates back from tool-specific memory files

The sync tool should support modes such as:

- `export-claude`
- `export-codex`
- `import-claude`
- `import-codex`
- `sync`

### Phase 4: Add Codex integration

Once we identify the most reliable Codex injection point, add a Codex adapter.

Possible approaches:

- write to `~/.codex/memories/...`
- install a Codex hook or plugin that imports canonical shared memory at session start
- generate a Codex-readable include file or startup context file if supported

At the moment, this is the part with the most uncertainty.

### Phase 5: Automate with hooks/plugins

Once the canonical model and sync behavior are stable, automate it.

Possible automation points:

- Claude startup/shutdown hooks
- Codex startup/shutdown hooks
- wrapper commands like `codex-memory-sync` and `claude-memory-sync`
- git hooks for selective canonical-memory updates, if that proves useful

## Preferred End State

The preferred end state is:

- `AGENTS.md` for stable shared instructions
- a canonical shared memory store for injected recent context
- `.claude/MEMORY.md` as a projection, not the ultimate source of truth
- a Codex memory projection or hook-backed injection path
- tool-local overlays for each agent where needed

## Practical Recommendation

Start simple:

1. Create the canonical shared memory schema and file.
2. Partition current Claude memory into shared vs Claude-local material.
3. Build a repo-local sync script.
4. Add a configurable Codex adapter target.
5. Only after that, invest in hooks/plugins for automation.

This sequence keeps the design repo agnostic, avoids premature coupling to uncertain Codex internals, and still moves toward true bidirectional shared memory.

## Open Questions

These still need to be answered before final implementation:

1. What exact file naming or indexing convention does Codex use inside `~/.codex/memories/`?
2. Does Codex support a startup hook, plugin, or config-based memory import path?
3. Should the canonical shared memory live in Markdown with frontmatter, or in a stricter machine-first format like JSON/YAML?
4. How should conflicts be resolved when both tools modify shared memory concurrently?
5. Should branch/worktree context be part of shared memory, or derived dynamically by adapters?

## Summary

The main decision from this investigation is:

- shared instructions and shared memory are different architectural layers
- `AGENTS.md` solves the first problem
- a neutral canonical memory layer with tool-specific adapters is the right solution for the second
- the right long-term design is bidirectional and repo agnostic, with hooks/plugins as an automation layer on top of a canonical store, not as the store itself
