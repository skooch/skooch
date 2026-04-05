---
name: systemic-fix
description: Systematically diagnose bugs, failures, regressions, reliability issues, confusing behavior, architecture mismatches, and recurring operational problems in a codebase. Use when an agent is given a symptom, error, incident, user complaint, vague concern, or suspected root cause and must understand it without assumptions, validate unknowns before relying on them, research the relevant code paths and architecture, compare all credible fixes including current online guidance and patterns, and present the best architecturally sound fix plan rather than a workaround or fastest patch.
---

# Systemic Fix

## Overview

Trace an issue from symptom to recommendation by building evidence first, then understanding the surrounding architecture, then evaluating all credible fixes. Optimize for the best root-cause fix, not the quickest patch and not a workaround disguised as a fix.

Scale investigation depth to issue complexity. For bugs with an obvious, isolated root cause confirmed by direct evidence, steps 4-9 may be abbreviated. The full workflow is warranted when the cause is uncertain, multiple code paths are involved, the fix touches shared contracts or infrastructure, or the failure is intermittent.

## Operating Principles

- Treat every symptom as incomplete evidence, not as a diagnosis.
- Treat the user's framing of the problem as a hypothesis, not as established fact. Verify the user's diagnosis independently before building on it.
- Do not treat assumptions as facts.
- If a material assumption cannot be validated from the codebase, runtime evidence, or authoritative documentation, stop and ask the user whether to validate it now or proceed with explicit uncertainty.
- Prefer direct evidence: reproduction steps, failing tests, logs, stack traces, traces, configs, data shape, and source code.
- Understand the current project's purpose, goals, risks, limitations, and likely future change vectors before weighting tradeoffs.
- Research the architecture around the issue before choosing a fix.
- Explore multiple credible fixes before recommending one.
- Use online research when framework behavior, library guidance, standards, or current best practices could change the decision.
- Optimize for correctness, architectural coherence, resilience, observability, and testability.
- Prefer the option that leaves the system simpler, easier to change later, lower in developer cognitive load, and more efficient when those gains do not trade away correctness.
- Do not choose a workaround, guard clause, retry loop, or special case unless it is truly the cleanest root-cause fix.
- If two successive investigation attempts fail to produce new evidence or narrow hypotheses, pause and summarize what is known. Consider whether a fresh approach from first principles, or delegating a specific sub-question to a separate investigation, would be more productive than continuing the current line.

## Workflow

1. Define the problem precisely.
- State the observed symptom, expected behavior, actual behavior, scope, impact, and confidence level.
- Identify what is known, what is unknown, and what is only suspected.
- If the report is ambiguous, restate it in precise technical terms before proceeding.
- If the user has stated a diagnosis, treat it as a leading hypothesis to verify, not as a confirmed root cause.

2. Gather and validate evidence.
- Reproduce the issue when possible.
- If the issue cannot be reproduced, note this as a significant gap. Increase scrutiny on assumptions, prefer reversible fixes, and include the reproduction gap in residual risks.
- Inspect failing tests, logs, stack traces, recent changes, feature flags, configuration, data dependencies, and environment differences.
- Build a minimal evidence table: symptom, source, what it proves, and what it does not prove.
- Separate facts from interpretation.

3. Surface assumptions early.
- List every assumption that would materially change the diagnosis or fix.
- Validate each assumption locally when possible.
- If a key assumption still cannot be validated, ask the user whether to validate it now, narrow scope, or proceed with explicit uncertainty.

4. Establish project context.
- Inspect the project's high-level purpose, product goals, likely future changes, operational environment, known risks, and hard limitations.
- Determine which qualities should be weighted more heavily here: reliability, simplicity, openness to change, ergonomics, performance, observability, or other constraints driven by the project.
- Use repository instructions, docs, plans, architecture notes, configuration, deployment setup, and adjacent code to infer context.
- If the project's priorities are still unclear and the ambiguity would change the recommendation, ask the user to confirm them.

5. Map the relevant system.
- Trace the code path from entrypoint to failure point.
- Identify ownership boundaries: modules, services, queues, jobs, caches, schemas, contracts, and invariants.
- Read adjacent code, not just the failing line.
- Determine whether the issue is primarily about behavior, state modeling, error handling, concurrency, data flow, configuration, observability, or system boundaries.

6. Diagnose the root cause.
- Generate at least two competing hypotheses for the root cause.
- For each hypothesis, state what evidence would confirm it and what evidence would refute it.
- Test each hypothesis against the collected evidence.
- If multiple hypotheses survive, design a targeted investigation to distinguish them.
- Confirm the root cause before generating fixes.
- When feasible, write a failing test that demonstrates the bug before proceeding. This test becomes both proof of understanding and regression coverage.

7. Generate candidate fixes.
- Include the obvious local fix, deeper structural fixes, contract or schema fixes, lifecycle fixes, and observability or testability improvements when relevant.
- Reject options that only mask symptoms unless the root cause is truly external and cannot be corrected here.
- For each option, explain the mechanism by which it resolves the confirmed root cause.

8. Research external guidance.
- Use primary sources when external behavior matters: framework docs, language docs, library docs, official issue trackers, standards, and RFCs.
- Look for patterns or constraints that could invalidate an otherwise plausible fix.
- Incorporate current behavior and version-specific guidance instead of relying on memory for changing ecosystems.

9. Select the best fix.
- Evaluate options primarily on root-cause removal, architectural consistency, invariants preserved, blast radius, correctness under edge cases, operational safety, observability, testability, simplicity, openness to future change, developer ergonomics, cognitive load, and performance.
- Weight those qualities according to the project's actual goals, purpose, risk profile, and limitations rather than treating every quality as equally important in every codebase.
- Treat implementation effort and calendar cost as execution considerations, not as reasons to prefer an inferior design.
- Choose the fix that leaves the system in the strongest shape after the issue is gone.

10. Produce the plan.
- Use [decision framework](references/decision-framework.md) when comparing options or writing the final recommendation.
- Structure the output according to the [plan template](references/decision-framework.md#plan-template), while ensuring the qualitative requirements in the output contract below are met.
- Present the plan to the user before implementation unless the user explicitly asked you to implement immediately after planning.

## Investigation Moves

- Search for the first point where the system becomes inconsistent with its own invariants.
- Compare the happy path with the failing path.
- Check where data shape, ownership, timing, or lifecycle diverges.
- Look for duplicated logic, missing sources of truth, stale caches, implicit contracts, and unenforced state transitions.
- If the symptom appears late, search earlier in the flow for the corruption point.
- If the failure is intermittent, examine concurrency, retries, time, caching, ordering, and eventual consistency boundaries.
- If a proposed fix adds conditionals around a bad state, ask whether that state should be representable at all.

## Output Contract

- Make the distinction between facts, validated conclusions, and open questions explicit.
- Call out every assumption that still matters.
- State which project qualities were prioritized and why.
- Show the meaningful alternatives explored, not just the selected fix.
- Explain why the selected fix is the most architecturally clean and effective option.
- Include a verification plan with tests, runtime checks, and regression coverage.
- If more validation is needed before choosing a fix, say that clearly instead of pretending the recommendation is settled.

## Resources

- See [decision framework](references/decision-framework.md) for the evaluation rubric, red flags, and plan template.
