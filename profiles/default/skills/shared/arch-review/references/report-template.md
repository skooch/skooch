# Architecture Review Report Template

Use this as a lightweight structure for the persistent review document.

## Scope and Method

- what repo or codebase was reviewed
- what kinds of evidence were used
- whether the review was static, runtime-backed, or mixed
- whether subagents or parallel passes were used

## System Map

- major layers
- major subsystems
- major ownership boundaries

## Themes

- recurring architectural patterns
- repeated kinds of coupling or drift
- notable strengths worth preserving

## Issue Register

Recommended fields per issue:

- `AR-001` title
- area
- status: `new` / `validated` / `mixed` / `deferred`
- why it matters
- evidence
- remediation class

## Validated Concern Matrix

Recommended columns:

| Concern | Verdict | Remediation class | Short recommendation |
| --- | --- | --- | --- |

## Remediation Strategy

Group by phases such as:

- runtime control plane
- service boundaries
- startup and health
- tooling source of truth
- transitional debt

## Ranked Backlog

Checklist fields:

- checkbox
- title
- dependency tier or order
- t-shirt size
- target files or modules

Example:

- [ ] Split boot sequencing out of `src/bin/main.rs`
  - Dependency: `P0`
  - Size: `L`
  - Targets: `src/bin/main.rs`, `src/runtime/boot.rs`, `src/runtime/startup.rs`

## Final Judgment

- what is genuinely good
- what is genuinely problematic
- what should be left as debt
- what should happen next
