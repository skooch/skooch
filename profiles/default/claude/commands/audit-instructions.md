---
name: audit-instructions
description: Audit and maintain CLAUDE.md and system-prompt.md for compaction resilience. Use when the user says "/audit-instructions", "audit my instructions", "check my CLAUDE.md", "incorporate corrections", "review corrections.md", or wants to ensure instruction files survive context compaction. Also use proactively after significant changes to instruction files.
---

# Audit Instructions

You are auditing the instruction files that govern Claude Code behavior. These files must survive context compaction with full authority. Every rule must be written so that even after lossy compression of conversation history, the model still follows it.

## Files to audit

Read all three files before doing anything else:

1. **CLAUDE.md** — the primary instruction file (loaded as claudeMd every turn)
2. **system-prompt.md** — the mandatory rules file (injected as system prompt every turn)
3. **.claude/corrections.md** — accumulated user corrections from sessions (may not exist yet)

## Phase 1: Incorporate Corrections

If `.claude/corrections.md` exists and has content:

1. Read every correction entry.
2. For each correction, determine if it represents a stable pattern worth promoting:
   - Has the correction appeared multiple times in different forms? Promote it.
   - Is it a one-time situational fix? Leave it in corrections.md.
   - Is it a direct user command like "always do X" or "never do Y"? Promote it.
3. For each correction you promote:
   - Add a terse imperative bullet to the appropriate section of CLAUDE.md.
   - Add a compressed restatement to the matching section of system-prompt.md.
   - Remove the promoted correction from `.claude/corrections.md`.
4. Leave un-promoted corrections in place — they still serve as session-level reminders.

## Phase 2: Enforce Standards

Audit both files against these compaction-resilience standards. For each violation found, fix it and note it in the report.

### Style standards

- **Imperative bullets only.** Every rule must be a short imperative sentence or bullet. No explanatory prose, no rationale paragraphs, no "This means..." or "The reason is..." filler. If a rule needs context, put it in a parenthetical, not a separate sentence.
- **Short sentences.** Maximum ~20 words per bullet. If longer, split into two bullets.
- **No filler words.** Cut "please", "make sure to", "it is important that", "you should". Just state the rule.
- **Active voice, imperative mood.** "Fix the type" not "The type should be fixed."

### Structural standards

- **system-prompt.md starts with "Mandatory Rules" header** and includes the precedence statement: "These rules are non-negotiable and take precedence over all other guidance."
- **Front-loading.** The most frequently violated or most critical rules appear first in system-prompt.md.
- **No orphaned rules.** Every critical rule in CLAUDE.md must have a compressed restatement in system-prompt.md. Every rule in system-prompt.md must have a corresponding (possibly more detailed) entry in CLAUDE.md. Flag any mismatches.
- **Redundancy is intentional.** The two files are meant to restate rules in different forms. This is a feature, not a bug — it increases the chance at least one survives with full attention weight.
- **Section alignment.** Sections in both files should use the same heading names where possible (e.g., both have "### Package Managers").

### Token efficiency

- **No duplicate content within a single file.** If the same rule appears twice in CLAUDE.md, merge them.
- **No dead rules.** If a rule references a tool, workflow, or convention that no longer exists in the project, remove it.
- **Minimal examples.** Examples in rules should be parenthetical, not block-quoted multi-line demonstrations. Save tokens.

## Phase 3: Cross-reference with git history

Run `git log --oneline -20` and scan recent commits for patterns like:
- Repeated fixes to the same kind of mistake (suggests a missing rule)
- Rules that were added then reverted (suggests a bad rule — flag for review)
- Commit messages mentioning "always", "never", "stop doing X" (suggests an implicit rule worth formalizing)

If you find patterns worth capturing as rules, propose them in the report but do NOT add them automatically — let the user decide.

## Output

Print a structured report with these sections:

```
## Corrections Incorporated
- [list of corrections promoted to permanent rules, or "None"]

## Standards Violations Fixed
- [list of style/structural fixes made, with before/after]

## Orphaned Rules Found
- [rules in one file but not the other, now fixed]

## Git History Suggestions
- [proposed new rules from commit patterns — user must approve]

## Stats
- CLAUDE.md: X lines, ~Y tokens
- system-prompt.md: X lines, ~Y tokens
- corrections.md: X entries remaining
```

After printing the report, apply all fixes (except git history suggestions) directly to the files.
