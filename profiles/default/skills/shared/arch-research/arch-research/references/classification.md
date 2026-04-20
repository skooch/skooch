# Idea Classification

Every entry under "Ideas Worth Stealing" gets one label. Picking the right label is the most load-bearing decision in the skill because it determines whether the idea graduates into a plan stub or gets forgotten on purpose.

## Labels

### `adopt`

The external OS's pattern is a near-direct fit. Applying it to our stack changes little beyond syntax and naming. A plan stub is warranted.

**Signals it fits:**
- The pattern is widely documented and battle-tested in the external OS.
- Our stack already has the primitives needed to implement it.
- Doing it removes a real gap, not a hypothetical one.
- Rough cost is known (S/M, not L/XL).

**Example** (from `zephyr.md`): Device Runtime PM with RAII guards — Zephyr's `pm_device_runtime_get/put` ref-counting maps directly to Rust's Drop-based ownership. Mechanism transfers wholesale.

### `translate`

The idea is sound but requires meaningful adaptation. Our stack's primitives, vocabulary, or constraints differ enough that a faithful port would feel wrong.

**Signals it fits:**
- The idea originated in a different paradigm (C + RTOS → Rust + async, cooperative → preemptive, single-core → dual-core).
- Adopting it requires new types or traits we don't have yet.
- The shape is right but the implementation is unavoidably bespoke.

**Example**: Zephyr's kernel objects (`k_sem`, `k_mutex`) translated into `embassy_sync::Mutex`/`Signal`/`Watch`. Same semantics, different mechanism.

### `keep`

We already have an equivalent or stronger version. No action. Call this out explicitly — it's evidence the skim was thorough rather than cherry-picked.

**Signals it fits:**
- The external OS's concept is present in our codebase under a different name.
- Our version has stronger guarantees (compile-time checks, better ergonomics, fewer failure modes).
- Adopting the external version would be a regression.

**Example**: Zephyr devicetree pin ownership vs Rust move semantics — we already catch wiring bugs at compile time, which is stronger than runtime devicetree checks.

### `skip`

The idea does not fit. Document why so it doesn't come back up.

**Signals it fits:**
- Solves a problem we don't have (wrong hardware class, wrong workload shape, wrong deployment model).
- Requires infrastructure we can't or won't add (MMU, formal verification, kernel/user split).
- Cost exceeds benefit by an order of magnitude.

**Example**: Zephyr's demand paging — no MMU on target MCU, inapplicable.

### `ask`

The classification depends on a decision the user needs to make. Surface the tradeoff and wait.

**Signals it fits:**
- The idea would change scope (new hardware variant, new dependency, new release policy).
- Adoption rules out another direction we're also considering.
- The right call needs product input, not architectural input.

**Example**: A debug shell. Useful, but competes for limited UART bandwidth with defmt — which backend to use is a user call.

## Classification decision tree

```
Does our stack already have an equivalent or stronger version?
├─ Yes → keep
└─ No → Is the pattern a near-direct fit with our primitives?
        ├─ Yes → adopt
        └─ No → Is the idea sound but needs adaptation?
                ├─ Yes → translate
                └─ No → Does it solve a problem we have?
                        ├─ No → skip
                        └─ Yes (but it's a user decision) → ask
```

## Historical / Tier-6 override

For Tier 6 OSes (PalmOS, Mac System 6/7, Newton, EPOC, BeOS, AmigaOS, RISC OS, GEOS, NeXTSTEP, CP/M, GO/PenPoint, Danger Hiptop):

- The `adopt` label is almost never correct — the code is obsolete, the APIs are bespoke, the target hardware is long gone.
- Default to `translate` for genuinely good ideas. The "Proposed" field does the translation work explicitly.
- Default to `keep` for patterns we already embody in a different form.
- `ask` remains valid for product-level decisions.
- `skip` with a clear reason still applies.

## Plan-stub handoff template

When the user confirms that an `adopt` or `translate` item should graduate to a plan, seed the plan stub with this skeleton:

```markdown
# <Idea name>

Source: `docs/architecture/comparisons/<os>.md` §<idea number>.

## Problem

<The "Our gap" from the comparison doc, expanded.>

## Proposed approach

<The "Proposed" from the comparison doc, expanded.>

## Scope

- In scope: <…>
- Out of scope: <…>

## Dependencies

<Other plans or subsystems this touches.>

## Verification

<How we'll know it worked.>
```

Path: the project's plan directory per its CLAUDE.md (typically `docs/plans/new/<idea-slug>/plan.md`).

Hand off to `todo-plan` once the stub exists if the user wants immediate execution tracking.
