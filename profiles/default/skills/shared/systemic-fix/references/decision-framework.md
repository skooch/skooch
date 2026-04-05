# Decision Framework

## Intervention Classification

- **Local refactor**: behavior-preserving localized change, no shared boundary changes.
- **Architectural remediation**: changes shared contracts, data flow, ownership, lifecycle, or boundaries.
- **Track as debt**: understood, paying down now is worse tradeoff.

State why chosen class fits better than the other two.

## Evaluation Criteria

Score each option. Do not treat the framework as flat scoring. Apply it in context.

**Root cause and correctness:**
- Removes root cause or masks symptom?
- Correct under retries, concurrency, partial failure, stale state?
- Preserves/strengthens invariants?

**Architecture:**
- Places responsibility at correct architectural layer? Right component truly owns the decision/state?
- Simplifies contracts, ownership, state transitions?
- Reduces coupling, duplication, source-of-truth drift?
- What invariant was violated? Where should it be enforced?
- What earlier point could prevent the bad state?

**System quality:**
- Leaves system simpler after the change lands, easier to reason about?
- Makes future change easier instead of baking in more rigidity?
- Improves observability, diagnosability, testability?
- Improves developer ergonomics, reduces cognitive load for the people who will maintain and extend this code?
- Efficient enough for real hot paths, data volumes, and latency constraints?

**Constraints and tradeoffs:**
- Surfaces real tradeoffs vs aesthetic claims?
- Makes product, operational, regulatory, platform, staffing, and compatibility constraints explicit?
- Aligns with authoritative framework/library guidance?
- Avoids introducing new policy exceptions, one-off conditionals, fragile sequencing?
- Preserves compatibility or makes breaks explicit?
- Reasonable rollback/reversibility?
- Retires debt, reduces interest, or justifies deferral?

**Context questions** (before choosing):
- What outcomes matter most? What future change is likely or strategically important?
- What constraints limit design space?
- Most dangerous failures? Extra-weight qualities? Acceptable trades?

## Red Flags

Suspect if option mainly: guards impossible state; retries without explaining race; patches one caller when contract wrong for all; duplicates logic vs single source of truth; hard-codes around bad data; improves visible symptom but leaves the system impossible to debug next time; jumps to rewrite without incremental option; labels remediation as refactoring; insists on paying debt without justifying cost.

## Remediation Expectations

- [Remediation playbook](remediation-playbook.md) for snapshot/scenarios.
- 2+ serious options with tradeoffs, reversibility, compatibility, debt impact.
- 1+ incremental modernization option before rewrite-shaped change.
- Rollout/compatibility approach, not just target end state.

## Research Expectations

When external behavior matters:

- Prefer official docs, specs, library docs, standards, RFCs.
- Check version-specific behavior instead of assuming older guidance still applies.
- Issue trackers/RFCs only for edge cases, compatibility, known pitfalls.
- Treat blogs and forums as secondary sources, not as the final authority.

## Plan Template

Every recommendation starts with:

1. **Intervention class** — which, and brief why.
2. **Problem** — symptom, expected vs actual, scope, impact.
3. **Evidence** — reproduction, logs, tests, traces, code refs.
4. **Assumptions** — validated, open, what changes if wrong.

### Lightweight mode

5. **Options** — serious options, why rejected/retained.
6. **Fix** — selected, why cleanest effective answer.
7. **Verification** — tests, checks, regression coverage.
8. **Residual risks** — remaining uncertainties, follow-up work, and any validation still worth doing.

### Remediation mode

5. **Context** — goals, future change, weighted qualities, constraints.
6. **Architecture + scenarios** — boundaries, ownership, contracts, data flow; success/non-regression scenarios.
7. **Options matrix** — tradeoffs, reversibility, compatibility, debt per option.
8. **Recommendation** — selected, why best architectural answer.
9. **ADR** — context, decision, consequences.
10. **Rollout** — steps, boundaries, migration, compatibility approach.
11. **Verification** — tests, checks, regression coverage.
12. **Debt + risks** — retired/deferred, remaining risk, follow-up.

### Debt tracking mode

5. **Why not now** — tradeoff justification.
6. **Deferral cost** — complexity, friction, operational cost.
7. **Trigger** — signal to revisit.
8. **Safeguards** — tests, observability, guardrails.
