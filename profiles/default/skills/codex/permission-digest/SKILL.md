---
name: permission-digest
description: Compile home-scope permission requests and command approvals into a concise inbox digest for later rule syncing. Use when an agent needs to summarize permission prompts, batch repeated approval requests, or prepare candidate generic rules from `~/.codex/signals/*` into `~/.codex/inbox/*`.
---

# Permission Digest

## Purpose

Compile the latest home-scoped permission signals into a stable handoff file for later promotion into `~/.codex/rules/default.rules`.

## Workflow

1. Read `~/.codex/signals/permission-signals.jsonl` and `~/.codex/signals/command-signals.jsonl`.
2. Group by command family, risk level, and recent repetition.
3. Compare repeated families against `~/.codex/rules/default.rules` and treat families already covered by a broader `allow` rule as consolidated, not promotable.
4. If several repeated sibling families could be replaced by one broader allow, surface that as an explicit user-confirmation ask instead of auto-promoting the broader rule.
5. Drop one-offs, shell wrappers, and anything destructive or secret-related.
6. At session end, the home `Stop` hook writes the digest to `~/.codex/inbox/permission-digest.md` and `~/.codex/inbox/permission-digest.json`.
7. If nothing qualifies, write a short no-op digest instead of inventing rules.

## Output Contract

- Keep the markdown human-readable and the JSON machine-readable.
- Keep the markdown short: summary, observations, candidate rules, and notes.
- Keep the JSON stable and deterministic so the daily sync can parse it without model guesswork.
- Prefer normalized rule patterns such as `["git", "status"]` over raw shell lines.
- Use observation status `covered` when a repeated family is already allowed by an existing broader rule, so the digest stays human-useful without re-suggesting duplicates.
- When broader consolidation looks plausible, emit a separate user-confirmation ask rather than silently widening permissions.

## Rules

- Never emit raw secrets or raw command excerpts.
- Never promote a command family after a single sighting.
- Never suggest a rule that is already covered by an existing broader `allow` rule.
- Never widen a narrower cluster into a broader allow without surfacing it for explicit user confirmation.
- Keep this skill home-scoped; do not write repo-local state.

## Reference

See [inbox format](references/inbox-format.md) for the exact markdown and JSON layout.
