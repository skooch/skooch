---
name: arch-review
description: Run iterative architecture reviews for a codebase, collect issues into a persistent review document, keep looping until issue discovery saturates, then synthesize themes and convert the issue list into a dependency-ordered checklist with t-shirt sizing. Use when a user wants a broad or deep architecture review, wants issues accumulated across multiple passes, or wants a review report turned into an actionable remediation backlog.
---

# Arch Review

Run architecture review as a looping discovery process, not a single-pass opinion dump.

**Announce at start:** "I'm using the arch-review skill to run the review in passes, collect issues into a persistent report, and keep going until issue discovery saturates."

## Use This Skill To

- Review an unfamiliar codebase from the surface down into deeper architectural seams.
- Collect issues into one persistent report instead of scattering them across chat replies.
- Revisit initial concerns and validate whether they are confirmed, mixed, or overstated.
- Keep reviewing until the likely issue surface is exhausted.
- Synthesize recurring themes across individual findings.
- Turn the final issue list into a logical checklist ordered by dependency and t-shirt size.

## Core Principles

- Review in passes. Do not assume the first pass found the real issues.
- Separate mapping from judgment. Understand the system shape before criticizing it.
- Separate suspicion from validation. Initial concerns are hypotheses until checked against code.
- Keep one report file as the source of truth and append or revise in place.
- Prefer evidence-backed findings with file references over generic architecture advice.
- Do not stop just because you found a few strong issues. Stop when new passes stop producing meaningful new findings.
- Do not recommend a rewrite when staged remediation is sufficient.

## Review Modes

- `surface`: map the system, its functional areas, and major boundaries.
- `deep`: validate specific concerns, inspect coupling, and identify root architectural seams.
- `saturation`: deliberately search for still-unreviewed areas or likely blind spots.
- `synthesis`: extract themes, group related issues, and build the final backlog.

Use `surface` first unless the user explicitly hands you a narrow concern to validate.

## Workflow

### 1. Establish Scope

Define:

- repo or codebase under review
- report path
- review depth
- whether this is a fresh report or an update to an existing one

If no report path is specified, create a review doc under the repo's docs area when appropriate. If the repo already has a review document for the current effort, update it in place.

### 2. Map The Codebase First

Before judging quality, identify:

- runtime and entrypoints
- major subsystems
- platform/framework layers
- feature/application layers
- persistence/config/state surfaces
- tooling, test, and automation layers

Write this map into the report before the findings backlog. For large repos, this is the first pass.

### 3. Create The Initial Issue Register

Use one persistent issue register in the report. For each issue, record:

- issue id
- title
- area or subsystem
- status: `new`, `validated`, `mixed`, `deferred`
- why it matters
- evidence with file references
- remediation class:
  - `local refactor`
  - `architectural remediation`
  - `track as debt`

Keep the register concise and factual. Avoid writing the same issue twice; expand or revise an existing issue instead.

For report structure, use [references/report-template.md](references/report-template.md).

### 4. Review In Loops

Review by workstream, not by random file hopping. Typical workstreams:

- runtime and boot
- UI/framework/display
- feature and state boundaries
- persistence/storage/config
- platform/connectivity/health
- tooling/test/automation/extensibility

For each workstream:

1. map the local subsystem boundaries
2. identify candidate issues
3. validate them against code
4. add or update findings in the report
5. note which neighboring areas still need inspection

If the user explicitly allows subagents or parallel review, split workstreams across subagents and synthesize their findings back into the main report.

### 5. Run A Saturation Pass

Do not stop after one round of deep dives. Run at least one explicit saturation check:

- what major area remains unreviewed?
- what high-coupling files were mentioned but not read?
- which findings are repeated symptoms of a deeper shared cause?
- did any “mixed” concern deserve re-checking from another angle?

Stop when one of these is true:

- two consecutive review passes produce no meaningful new issues
- remaining unreviewed areas are low-probability and clearly called out
- the user stops the review

When stopping, say why the loop is ending.

### 6. Validate Initial Concerns

After the first issue collection pass, revisit the major concerns and classify each as:

- `Confirmed`: the concern is real and supported by code evidence
- `Mixed`: the concern is partially real, but current constraints or design intent justify some of it
- `Overstated`: the concern looked worse than it is

Use this validation pass to prevent the final report from over-rotating on surface ugliness.

### 7. Synthesize Themes

After issue discovery saturates, group findings into cross-cutting themes such as:

- orchestration concentration
- boundary drift
- hidden coupling via global state
- transitional architecture lingering too long
- tooling source-of-truth brittleness

Themes should explain the codebase, not just summarize the issue list.

### 8. Build The Final Checklist

Convert the final validated issue set into a checklist backlog.

For each backlog item, assign:

- logical dependency order
- t-shirt size
- remediation class

Dependency order means “what should happen first so later work becomes easier or safer,” not “what looks most annoying.”

Use t-shirt sizes:

- `S`: narrow change, low blast radius, local boundary cleanup
- `M`: multi-file or multi-module change, moderate coordination
- `L`: cross-cutting architectural split or contract change
- `XL`: large multi-phase remediation requiring staged rollout

Order by dependency first, then by leverage within each dependency tier.

### 9. End With A Judgment

End the report with:

- what the architecture gets right
- what the most important real problems are
- what should be treated as debt instead of “fixed”
- the minimum high-leverage next actions

## Output Contract

The final report should contain, in this order:

1. scope and method
2. codebase or subsystem map
3. themes
4. issue register
5. validated concern matrix
6. remediation strategy
7. ranked backlog checklist
8. final judgment

The report may merge or rename sections to fit the repo, but it must preserve that information.

## Practical Rules

- Update the existing report in place instead of forking multiple review docs unless the user explicitly wants separate documents.
- Use file references for evidence-heavy claims.
- Be willing to downgrade a concern during validation.
- Prefer staged remediations with tradeoffs over abstract “should be cleaner” commentary.
- When recommending a split, name the likely new ownership boundary.
- Keep the backlog actionable. “Improve architecture” is not a checklist item.

## When To Use Other Skills

- Use `systemic-fix` thinking inside this skill when validating root architectural seams and comparing remediation options.
- Use `todo-plan` after the review if the user wants the backlog converted into an execution plan.
