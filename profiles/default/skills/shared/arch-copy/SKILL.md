---
name: arch-copy
description: Compare one source repository and one target repository so architectural practices, tooling, and repo conventions can be adopted appropriately instead of copied blindly. Use when starting a new project from an older repo, aligning a repo with another similar repo in the same ecosystem, or porting conventions between local paths or GitHub repositories via gh. Inventory both repos, classify each convention as adopt, translate, keep, skip, or ask, write a migration plan into the target repo first, and only apply changes after explicit approval including a commit strategy choice.
---

# Arch Copy

Use this skill to transfer conventions from a source repo into a target repo without flattening the target's identity or copying product-specific baggage.

Prefer intent-preserving adoption over file cloning. Default to analysis and a written migration plan first. Apply only after the user explicitly approves the plan, chooses `commit-by-item`, `commit-all`, or `no-commit`, and answers the plan's open decisions through a step-by-step question flow.

## Core Rules

- Treat the source repo as inspiration, not authority.
- Inventory both repos before recommending changes.
- Prefer same-tool adoption. If the source and target differ materially in ecosystem, toolchain, hosting model, or repo maturity, stop and ask instead of improvising a cross-ecosystem translation.
- Preserve target-specific instructions, architecture, and product behavior unless the user explicitly wants them replaced.
- Copy practices at the correct layer: policy, workflow, validation, docs, automation, or release process.
- Reject blind copying of secrets, deployment details, repo-specific packaging, product assets, org-specific identifiers, and workflows tied to the source repo's artifact names or release channels.
- Separate facts from assumptions. If a plan depends on an assumption that materially changes the recommendation, surface it.

## Workflow

1. **Resolve the repos.**
Identify the source and target as local paths or GitHub repos.
- For GitHub repos, use `gh` for inspection.
- For apply work, require a local checkout of the target before editing.

2. **Inventory both repos.**
Inspect the categories in [convention-categories.md](references/convention-categories.md).
- Read repo instructions first.
- Find current workflows, hooks, CI, linting, formatter, release automation, docs, issue templates, plan layouts, and supporting config.
- Note what exists in source only, target only, and both.

3. **Classify each convention.**
Use [classification-rules.md](references/classification-rules.md).
Assign every candidate one of:
- `adopt`
- `translate`
- `keep`
- `skip`
- `ask`

4. **Write the migration plan into the target repo.**
Use [output-template.md](references/output-template.md).
- Prefer the target's existing plan convention when one exists.
- If the target already has `docs/plans/new/`, write the plan there.
- Otherwise write a single low-churn proposal at `docs/arch-copy-<source-name>.md` unless the user asks to introduce a fuller plan hierarchy.
- The plan must include inventory, classifications, proposed edits, skipped items, open decisions, verification, the commit-choice prompt for the apply phase, and a decision walkthrough list that can be asked one question at a time.

5. **Pause before applying.**
Do not edit project files yet.
Ask the user whether to apply the plan and which commit mode to use:
- `commit-by-item`
- `commit-all`
- `no-commit`

6. **Walk through open decisions after commit choice.**
Once the user has chosen a commit mode, ask each open decision from the plan as a separate step-by-step question before applying changes.
- Ask one decision at a time in the order recorded in the plan.
- Present the concrete options, recommend one when appropriate, and give a short tradeoff.
- Record the user's answer back into the plan or working notes before moving to the next decision.
- If the user defers a decision, stop before implementation and surface the remaining blocker clearly.

7. **Apply cautiously after approval.**
Implement only the approved items.
- Keep commits atomic if committing.
- Preserve unrelated target conventions unless the plan explicitly changes them.
- Update affected docs and references in the same change set.

8. **Validate.**
Run the target repo's relevant checks for every adopted item.
- Formatting and linting
- Tests
- CI config validation where practical
- Doc or path-reference verification when layouts change

## Decision Notes

- Prefer `adopt` when the source convention fits the target with little or no semantic change.
- Prefer `translate` when the source intent is good but file paths, names, or target repo conventions require adaptation.
- Prefer `keep` when the target already has an equivalent or stronger convention.
- Prefer `skip` when the item is source-product-specific, tightly coupled to source release mechanics, or creates more maintenance burden than value.
- Prefer `ask` when adoption changes tool versions, supported platforms, release policy, ownership boundaries, or repo layout in a non-obvious way.

## Example Shape

For `/Users/skooch/projects/align-internal` -> `/Users/skooch/projects/codebase-memory-zig`:
- Adopt or translate Zig CI checks, formatting, test, and possibly cross-compile coverage.
- Ask before changing the Zig version or broadening release policy.
- Keep the target's stronger `AGENTS.md` or `CLAUDE.md` plus `docs/plans/` layout if it already exists.
- Skip source-specific GitHub Action packaging and artifact naming unless the target explicitly wants the same distribution model.

## Resources

- [adoption-workflow.md](references/adoption-workflow.md): expanded workflow and plan-path rules.
- [classification-rules.md](references/classification-rules.md): how to classify conventions.
- [convention-categories.md](references/convention-categories.md): inventory checklist.
- [output-template.md](references/output-template.md): migration plan template.
