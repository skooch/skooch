---
name: check-agent-standards
description: Standardize or migrate a repository's agent-facing layout to the shared convention. Use when an agent needs to set up a new repo or migrate an existing repo so repository instructions are discoverable through `AGENTS.md`, repo-local skills are discoverable through `.agents/skills/`, and plans live in `docs/plans/{new,in-progress,implemented,paused}`. Preserve any existing `CLAUDE.md` or `.claude/skills/` in place, and when either already exists make the generic entrypoint point to that existing location via a relative symlink after merging any missing non-conflicting guidance.
---

# Check Agent Standards

## Overview

Bring a repository onto the shared agent metadata layout without throwing away existing instructions. Treat repo-root `AGENTS.md` and `.agents/skills/` as the generic entrypoints, but preserve existing legacy agent-specific locations when they already contain the real content.

## Target Layout

- `AGENTS.md`
- `.agents/skills/<skill-name>/SKILL.md`
- `docs/plans/new/`
- `docs/plans/in-progress/`
- `docs/plans/implemented/`
- `docs/plans/paused/`
- Keep an existing `CLAUDE.md` only as a compatibility file in its current location.
- See [migration decision table](references/migration-decision-table.md) before changing any existing instruction file or plan tree.

## Workflow

1. Inventory the current layout.
- Inspect `AGENTS.md`, every `CLAUDE.md`, `.claude/plans`, `docs/plans`, `.claude/skills`, and `.agents/skills`.
- If multiple non-identical `CLAUDE.md` files exist, stop and ask the user which one is canonical before editing anything.

2. Normalize the instruction entrypoint.
- If any existing `CLAUDE.md` exists, do not move it.
- If repo-root `AGENTS.md` already exists as a normal file and differs from the existing `CLAUDE.md`, merge any missing repo-specific guidance into `CLAUDE.md` first.
- Then create or replace repo-root `AGENTS.md` with a relative symlink to the existing `CLAUDE.md`.
- If no `CLAUDE.md` exists anywhere, keep or create repo-root `AGENTS.md` as the canonical instruction file.
- Never reverse the relationship by turning an existing `CLAUDE.md` into a symlink to `AGENTS.md`.

3. Normalize plan storage.
- Canonicalize plans under `docs/plans/`.
- Ensure the enforced lifecycle folders exist exactly as `new/`, `in-progress/`, `implemented/`, and `paused/`.
- When migrating from `.claude/plans/`, move matching lifecycle folders into the matching `docs/plans/` folders without renaming the state.
- For loose plan markdown files from legacy locations, place them in `docs/plans/new/` unless their state is already obvious from surrounding context.
- On filename conflicts, stop and ask rather than overwriting or auto-renaming.

4. Normalize repo-local skills.
- Treat `.agents/skills/` as the generic entrypoint for discovery.
- If `.claude/skills/` exists as a real directory, do not move it.
- If both `.claude/skills/` and `.agents/skills/` exist as real directories, merge only missing non-conflicting skill folders into `.claude/skills/` first.
- If the same skill folder exists in both places with different contents, stop and ask instead of guessing which version wins.
- Then create or replace `.agents/skills` with a relative symlink to `.claude/skills`.
- If `.claude/skills/` does not exist and `.agents/skills/` does, keep `.agents/skills/` as the real skill root.
- If neither path exists, create `.agents/skills/`.
- If agent-style discovery is explicitly needed and `.claude/skills/` does not already exist, optionally create `.claude/skills` as a relative symlink to `../.agents/skills`.
- Keep each skill folder named after the skill frontmatter `name`.

5. Validate and report.
- Verify that repo-root `AGENTS.md` points to the expected target when a `CLAUDE.md` exists.
- Verify all four `docs/plans/` lifecycle folders exist.
- Verify repo-local skills are present under `.agents/skills/`.
- Summarize the final layout, any compatibility symlinks, and any unresolved conflicts.

## Rules

- Use relative symlinks, not absolute symlinks.
- Prefer moves and symlinks over duplicated instruction files.
- Never move an existing `CLAUDE.md` to a new path.
- Never replace an existing real `.claude/skills/` directory with a symlink to `.agents/skills/`.
- Never overwrite conflicting plan files or skill folders silently.
- Keep migrations idempotent so rerunning the skill mostly no-ops.
- If the repo already follows the standard, report that and avoid churn.

## Output Contract

- Report the final `AGENTS.md` state and, if relevant, its symlink target.
- Report the final plan root and confirm the four lifecycle folders.
- Report the final `.agents/skills` state and, if relevant, its symlink target.
- Report whether `.claude/skills` remains the real underlying directory or is present only as an optional compatibility symlink.
- Call out any conflicts or ambiguous legacy structure that still needs a user decision.
