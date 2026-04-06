---
name: todo-plan
description: Turn a task or selected fix into a tracked execution plan with file-persisted progress. Use when asked to plan, break down, or track small-to-medium work, or when systemic-fix hands off a selected approach for implementation. Not for deep investigation (use systemic-fix) or large architectural specs.
---

# Todo Plan

Turn an approach into a tracked, file-persisted execution plan. Lightweight — plan, track, execute.

**Announce at start:** "I'm using the todo-plan skill to create a tracked execution plan."

## When to Use

- Small-to-medium tasks needing tracked execution (3+ steps)
- Systemic-fix handed off a selected approach
- User asks to "plan this", "break this down", or "track this"
- Any work requiring organization across multiple files or phases

**Skip for:** single-file edits, quick lookups, simple questions, deep investigation (use systemic-fix instead).

## Handoff from Systemic-Fix

If systemic-fix already ran and produced a diagnosis + selected fix:

1. Read the existing plan/recommendation output
2. **Skip discovery** — the investigation is done
3. Extract: fix description, file list, verification criteria
4. Go directly to File Map + Task Breakdown

Do not re-investigate what systemic-fix already diagnosed.

## Workflow

### 1. Scope Check

Before planning, assess scope. If the task spans multiple independent subsystems that don't share state or interfaces, decompose into separate plans — one per subsystem. Each plan should produce working, testable changes on its own.

### 2. File Map

List every file you'll create or modify before defining phases. This locks in decomposition early and prevents scope drift.

```markdown
## File Map
- Modify: `src/foo/bar.rs` (add handler)
- Modify: `src/foo/mod.rs` (register handler)
- Create: `tests/foo_test.rs`
```

### 3. Create Plan

Create `plan.md` in the project working directory using [templates/plan.md](templates/plan.md) as reference.

Rules:
- **No placeholders.** No "TBD", "TODO", "add appropriate handling", "similar to above". Every phase must be concrete.
- **Exact file paths.** Every phase references the files it touches from the file map.
- **Checkpoint items are checkboxes.** `- [ ]` for pending, `- [x]` for done.

### 4. Self-Review

After writing the plan, quick inline check (not a ceremony):

1. **Placeholder scan** — any vague language? Fix it.
2. **Consistency** — do file paths, function names, types match across phases?
3. **Ambiguity** — could any step be interpreted two ways? Make it explicit.

Fix issues inline. No re-review cycle.

### 5. Execute and Track

As you work:
- Mark checkboxes in `plan.md` as you complete items
- Update phase status: `pending` -> `in_progress` -> `complete`
- Append actions to `progress.md` (flat log, not structured tables)
- Log errors immediately — never silently retry

### 6. Findings (Optional)

Create `findings.md` only when research is needed during execution. Not required for every task. Use [templates/findings.md](templates/findings.md) as reference.

## Error Discipline

Log every error to the plan's error table. Never repeat a failed approach.

```
Attempt 1: Diagnose and fix (targeted)
Attempt 2: Alternative approach (different method/tool)
Attempt 3: Broader rethink (question assumptions, search for solutions)
After 3 failures: Escalate to user with what you tried
```

## Core Principle

```
Context Window = RAM (volatile, limited)
Filesystem = Disk (persistent, unlimited)
-> Write important state to disk. Re-read before decisions.
```

Re-read `plan.md` before major decisions. This keeps goals in the attention window.

## Templates

- [templates/plan.md](templates/plan.md) — Phase tracking + file map
- [templates/findings.md](templates/findings.md) — Research storage (optional)
- [templates/progress.md](templates/progress.md) — Session logging

## Scripts

- `scripts/check-complete.sh` — Verify all phases complete (Stop hook)
