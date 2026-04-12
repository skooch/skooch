# Adoption Workflow

Use this when the work spans more than one obvious file copy.

## 1. Establish Scope

- Confirm one source repo and one target repo.
- Confirm the repos are similar enough for same-tool adoption.
- If the user wants multiple source repos, synthesize them only after identifying one canonical source for each convention family.

## 2. Gather Evidence

Inventory both repos using the convention categories checklist.

Minimum evidence:
- Repo instructions and local agent docs
- CI and automation files
- Toolchain and version pins
- Lint, format, test, and hook config
- Docs, templates, and release files
- Existing plan or process layout in the target

Record findings as:

| Convention | Source evidence | Target evidence | Initial read |
|---|---|---|---|

## 3. Compare Intention Before Files

Ask what the source file is trying to guarantee.

Examples:
- A CI workflow may enforce formatting, tests, and cross-platform builds.
- A plan layout may enforce tracked execution and stable locations.
- A release workflow may enforce packaging and changelog generation.

Copy the guarantee, not the file, unless the file already fits the target unchanged.

## 4. Classify

Use one status per convention:
- `adopt`: copy with minimal edits
- `translate`: preserve intent but adapt names, paths, layout, or conventions
- `keep`: target already has an equal or better solution
- `skip`: not appropriate for the target
- `ask`: meaningful tradeoff or missing fact

## 5. Choose Plan Path

Write the migration plan into the target repo before applying.

Path rules:
- If `docs/plans/new/` exists, write `docs/plans/new/arch-copy-<source-name>.md`.
- Else if the target has another clear plan convention, follow that convention.
- Else write `docs/arch-copy-<source-name>.md`.
- Do not introduce a full plan tree unless the user wants that as part of the migration.

## 6. Ask Before Apply

After writing the plan, stop and ask:
- whether to apply now
- whether to use `commit-by-item`, `commit-all`, or `no-commit`

Interpret commit modes as:
- `commit-by-item`: one commit per approved convention bundle
- `commit-all`: one commit for the whole migration
- `no-commit`: leave the worktree dirty for review

After the user picks a commit mode, walk the plan's open decisions in order as separate questions.
- Ask one question at a time instead of bundling all decisions into one message.
- Show the concrete options for that decision and recommend one when the tradeoff is clear.
- Note the answer before asking the next question.
- If a decision remains unresolved, stop before apply and report it as the active blocker.

## 7. Validate Per Bundle

For each applied bundle, run the validation that proves the convention actually works in the target repo.

Examples:
- lint and format configs: run the formatter or linter
- CI workflows: run equivalent local commands and validate syntax where practical
- hook config: verify referenced commands exist
- plan or docs layout: verify references and paths

## 8. Report Residual Risk

Always call out:
- untested workflows
- skipped source-specific automation
- open version decisions
- conventions intentionally kept from the target
