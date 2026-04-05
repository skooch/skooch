---
name: systemic-fix
description: Systematically diagnose bugs, failures, regressions, reliability issues, confusing behavior, architecture mismatches, and recurring operational problems. Use when given a symptom, error, incident, user complaint, vague concern, or suspected root cause and must diagnose without assumptions, compare credible fixes, and recommend the most durable fix plan rather than a workaround or fastest patch.
---

# Systemic Fix

Gather evidence, understand architecture, choose the smallest intervention that removes the root cause at the correct layer. Not a rewrite mandate, not ideal-architecture seeking, not incident response — focuses on code/design remediation. Not a workaround disguised as a fix.

Scale investigation depth to issue complexity. Abbreviate for obvious isolated bugs with direct evidence. Full flow when cause is uncertain, multiple paths involved, shared contracts/infrastructure affected, fix changes behavior/boundaries, or the failure is intermittent.

## Principles

- Treat every symptom as incomplete evidence, not as a diagnosis. User diagnoses are hypotheses — verify independently before building on it.
- Assumptions are not facts. If a material assumption cannot be validated from code, runtime evidence, or authoritative documentation, stop and ask.
- Prefer direct evidence: reproduction, failing tests, logs, traces, configs, data shape, code.
- Understand purpose, goals, risks, limitations, compatibility, and likely future change vectors before weighing tradeoffs.
- Make constraints explicit; research surrounding architecture; classify intervention before recommending.
- Explore multiple credible fixes. Research online when framework behavior, library guidance, standards, or current best practices could change the decision.
- Optimize for correctness, coherence, resilience, observability, testability, reversibility, compatibility.
- Prefer simpler, easier to change later, lower in developer cognitive load — without sacrificing correctness.
- Reject workarounds, guard clauses, retry loops, or special cases unless genuinely the cleanest root-cause fix.
- Two passes that fail to produce new evidence or narrow hypotheses: pause, summarize, reconsider from first principles. Consider whether delegating a specific sub-question to a separate investigation would be more productive than continuing the current line.

## Workflow

1. **Define problem.** Symptom, expected vs actual, scope, impact, confidence level. Knowns/unknowns/suspicions. Restate ambiguity in precise technical terms. Stated diagnoses = leading hypotheses to verify, not confirmed root causes.

2. **Gather evidence.** Reproduce when possible; if not, note it as a significant gap, increase scrutiny on assumptions, prefer reversible fixes, carry gap as residual risk. Inspect tests, logs, stack traces, recent changes, feature flags, config, data deps, env diffs. Evidence table: symptom | source | proves | doesn't prove. Separate facts from interpretation.

3. **Surface assumptions.** List every assumption that would materially change diagnosis/fix. Validate locally. Key assumption open? Ask: validate, narrow scope, or proceed with explicit uncertainty.

4. **Establish context.** Purpose, goals, likely future change, operational environment, compatibility, risks, hard limitations. Which qualities matter most: reliability, simplicity, openness to change, ergonomics, performance, observability. Infer from repository instructions, docs, plans, architecture notes, config, deployment, adjacent code. Ambiguity changes recommendation? Ask the user to confirm.

5. **Map system.** Trace code path from entrypoint to failure point. Identify ownership boundaries: modules, services, queues, jobs, caches, schemas, contracts, invariants. Read adjacent code, not just the failing line. Classify: behavior, state modeling, error handling, concurrency, data flow, config, observability, or system boundaries.

6. **Diagnose root cause.** 2+ competing hypotheses; for each, state what evidence would confirm and what would refute. Test against evidence. Multiple survive? Targeted investigation to distinguish them. Confirm before fixes. Write a failing test first when feasible — it becomes both proof of understanding and regression coverage.

7. **Classify intervention.** Per [decision framework](references/decision-framework.md): local refactor | architectural remediation | track as debt. State why chosen class fits better than the other two.

8. **Generate and research fixes.** Local, structural, contract/schema, lifecycle, observability fixes as relevant. Reject symptom masking unless root cause is external/uncorrectable. Explain the mechanism by which each resolves the confirmed root cause. Use primary sources for external behavior; check version-specific guidance instead of relying on memory for changing ecosystems. For `remediation`: [playbook](references/remediation-playbook.md), 2+ serious options, tradeoffs/reversibility/compatibility/debt. Rewrite-shaped? Include incremental modernization option.

9. **Select best fix.** [Decision framework](references/decision-framework.md) criteria: root-cause removal, blast radius, correctness under edge cases, operational safety, weighted by project context rather than treating every quality as equally important in every codebase. Treat implementation effort and calendar cost as execution considerations, not as reasons to prefer an inferior design. Pick what leaves the system strongest.

10. **Stop or plan.** Stop if evidence weak, assumptions open, or scope drifting to unbounded rewrite. Follow [plan template](references/decision-framework.md#plan-template). Present before implementation unless told otherwise.

## Investigation Moves

- Find first broken invariant; compare happy vs failing paths.
- Where does data shape, ownership, timing, or lifecycle diverge?
- Duplication, missing sources of truth, stale caches, implicit contracts, unenforced state transitions.
- Symptom late? Search earlier in the flow for corruption point.
- Intermittent? Concurrency, retries, timing, caching, ordering, eventual consistency boundaries.
- Fix adds conditionals around bad state? Should that state be representable at all?
- Fix points to subsystem replacement? What smaller boundary shift works incrementally?

## Output Contract

Mode: `lightweight` (obvious local bugs) or `remediation` (architecture-affecting). Default lightweight.

Content per [plan template](references/decision-framework.md#plan-template). Always: distinguish facts/validated conclusions/open questions, call out every assumption that still matters, state prioritized qualities, show meaningful alternatives explored, explain why selected fix is the most architecturally clean and effective option, include verification plan. Debt: state what's deferred, why, trigger. If more validation is needed, say that clearly instead of pretending the recommendation is settled.

## Resources

- [Decision framework](references/decision-framework.md): classification, evaluation, red flags, plan template.
- [Remediation playbook](references/remediation-playbook.md): architecture snapshot, scenarios, options matrix templates.
