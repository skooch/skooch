# Decision Framework

Use this reference when comparing remedies or preparing the final plan for the user.

## Evaluation Criteria

Score each serious option against these questions:

- Does it remove the root cause, or only mask the symptom?
- Does it place responsibility at the correct architectural layer?
- Does it preserve or strengthen system invariants?
- Does it simplify contracts, ownership, or state transitions?
- Does it leave the system simpler overall after the change lands?
- Does it leave the system more open to future change instead of baking in more rigidity?
- Does it reduce hidden coupling, duplication, or drift between sources of truth?
- Does it improve developer ergonomics or reduce cognitive load for the people who will maintain and extend this code?
- Does it behave correctly under retries, concurrency, partial failure, and stale state?
- Is it efficient enough for the real hot paths, data volumes, and latency constraints involved?
- Does it improve observability, diagnosability, and testability?
- Does it avoid introducing new policy exceptions, one-off conditionals, or fragile sequencing?
- Does it respect current framework or library guidance from authoritative sources?
- Does it leave the codebase easier to reason about after the fix lands?

## Project Context Weighting

Before choosing an option, determine how this project should weight the criteria above.

Ask these questions:

- What is this project for, and what outcomes matter most?
- What kinds of future change are likely or strategically important?
- What operational, product, regulatory, platform, or staffing constraints limit the design space?
- Which failures are most dangerous here: incorrectness, downtime, latency, operator confusion, developer confusion, migration risk, or inability to extend the system?
- Which qualities deserve extra weight in this codebase: simplicity, adaptability, ergonomics, performance, reliability, observability, or something else?
- Which qualities can be traded slightly because this particular project values others more?

Do not treat the framework as flat scoring. Apply it in context.

## Red Flags

Treat an option as suspect if it mainly does one of these:

- Adds a guard around a state that should never exist.
- Retries or delays work without explaining why the underlying race or ordering issue exists.
- Patches only one caller when the contract is wrong for every caller.
- Duplicates logic instead of restoring a single source of truth.
- Hard-codes around bad data instead of fixing validation, ownership, or data production.
- Improves the visible symptom but leaves the system impossible to debug next time.

## Architecture Questions

Ask these before settling on a recommendation:

- What invariant was violated?
- What is this project optimizing for at a high level?
- What risks and limitations of this project should change how the options are judged?
- Where should that invariant be enforced?
- Which component truly owns this decision or state transition?
- Which option leaves the system simpler?
- Which option leaves the system more open to future change?
- Which option gives developers the best ergonomics and the lowest cognitive load?
- Which option has the best performance profile for the actual workload that matters here?
- What earlier point in the flow could prevent the bad state from existing?
- What contract, schema, or lifecycle rule is currently implicit and should become explicit?
- What nearby code would become simpler if the root issue were fixed correctly?

## Online Research Expectations

When external behavior matters:

- Prefer official framework, language, library, or standard documentation.
- Check version-specific behavior instead of assuming older guidance still applies.
- Use issue trackers or RFCs only to clarify edge cases, compatibility, or known pitfalls.
- Treat blog posts and forum threads as secondary sources, not as the final authority.

## Plan Template

Use this structure for the final recommendation:

1. Problem statement
- Symptom, expected behavior, actual behavior, scope, and impact.

2. Evidence
- Reproduction, logs, failing tests, traces, code references, and observed facts.

3. Assumptions and validation status
- Which assumptions were validated, which remain open, and what would change if they are wrong.

4. Project context and weighting
- High-level goals, purpose, risks, limitations, and which decision qualities were weighted most heavily.

5. Architecture findings
- Relevant code paths, ownership boundaries, invariants, and failure mechanism.

6. Options considered
- List each serious option, how it would work, and why it was rejected or retained.

7. Recommended fix
- State the selected fix and explain why it is the cleanest and most effective answer.

8. Implementation plan
- Ordered steps, affected boundaries, migration concerns, and required tests or instrumentation.

9. Verification plan
- Tests, runtime checks, metrics, logs, rollout checks, and regression coverage.

10. Residual risks
- Remaining uncertainties, follow-up work, and any validation still worth doing.
