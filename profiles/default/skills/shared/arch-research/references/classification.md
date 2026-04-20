# Idea Classification

Every entry under "Ideas Worth Stealing" gets one label. Picking the right label is the most load-bearing decision in the skill because it determines whether the idea graduates into a plan stub or gets filed as explicitly-not-doing-this.

## Labels

### `adopt`

The subject's pattern is a near-direct fit. Applying it to our project changes little beyond syntax and naming. A plan stub is warranted.

**Signals it fits:**
- The pattern is widely documented and battle-tested in the subject.
- Our project already has the primitives needed to implement it.
- Doing it removes a real gap, not a hypothetical one.
- Rough cost is known and bounded (S/M, not L/XL).

**Example shape**: a compression library's streaming decoder API maps one-to-one onto an interface our own codec already exposes — same iterator discipline, same back-pressure model, same error vocabulary. Adopting it is mostly renaming.

### `translate`

The idea is sound but requires meaningful adaptation. Our project's primitives, vocabulary, constraints, or paradigm differ enough that a faithful port would feel wrong.

**Signals it fits:**
- The idea originated in a different paradigm (sync → async, single-threaded → concurrent, in-memory → disk-backed, callback-based → promise-based, etc.).
- Adopting it requires new types, traits, or abstractions we don't have yet.
- The shape is right but the implementation is unavoidably bespoke for our stack.

**Example shape**: a build tool's content-addressed caching model is worth adopting, but their target language is C++ and ours is TypeScript — the idea transfers, the artifacts don't. Same content-addressing pattern, different implementation.

### `keep`

We already have an equivalent or stronger version. No action. Call this out explicitly — it's evidence the skim was thorough rather than cherry-picked.

**Signals it fits:**
- The subject's concept is present in our project under a different name.
- Our version has stronger guarantees (compile-time checks, better ergonomics, fewer failure modes, stronger typing).
- Adopting the subject's version would be a regression.

**Example shape**: the subject uses a string-keyed plugin registry; our project has a typed enum of plugin kinds. The subject is more flexible; ours catches typos at compile time. Keep ours.

### `skip`

The idea does not fit. Document why so it doesn't come back up.

**Signals it fits:**
- Solves a problem we don't have (wrong domain, wrong workload, wrong scale).
- Requires infrastructure we can't or won't add.
- Cost exceeds benefit by an order of magnitude.
- Depends on platform features unavailable in our deployment context.

**Example shape**: the subject ships an IPC framework for cross-process coordination; our project is a single-process CLI. Not applicable.

### `ask`

The classification depends on a decision the user needs to make. Surface the tradeoff and wait.

**Signals it fits:**
- Adoption would change project scope (new dependency, new platform, new release policy).
- Picking this rules out another direction we're also considering.
- The right call needs product, business, or design input, not architectural input.

**Example shape**: the subject has two different plugin loading strategies (static-compile-in vs dynamic-at-runtime). Which fits our project depends on whether we ever want third-party extensions — a product question.

## Classification decision tree

```
Does our project already have an equivalent or stronger version?
├─ Yes → keep
└─ No → Is the pattern a near-direct fit with our primitives?
        ├─ Yes → adopt
        └─ No → Is the idea sound but needs adaptation?
                ├─ Yes → translate
                └─ No → Does it solve a problem we have?
                        ├─ No → skip
                        └─ Yes (but it's a user decision) → ask
```

## Historical / inspirational override

For subjects that are obsolete, archived, or from a previous generation, the `adopt` label is almost never correct — the code is gone, the APIs are bespoke, the target environment is long retired. Specific rules:

- Default to `translate` for genuinely good ideas. The "Proposed" field does the translation work explicitly, in our project's modern vocabulary.
- Default to `keep` for patterns we already embody in a different form — point out the lineage.
- `ask` remains valid for product-level decisions.
- `skip` with a clear reason still applies to ideas whose premise has aged out.

## Plan-stub handoff template

When the user confirms that an `adopt` or `translate` item should graduate to a plan, seed the stub with this skeleton at the project's plan location (detected from its agent-facing docs — typical paths are `docs/plans/new/<slug>/`, `.claude/plans/new/<slug>/`, or whatever the project's CLAUDE.md specifies):

```markdown
# <Idea name>

Source: `<path-to-comparison-doc>` §<idea number>.

## Problem

<The "Our gap" from the comparison doc, expanded with context from affected modules.>

## Proposed approach

<The "Proposed" from the comparison doc, expanded into concrete steps using the project's actual vocabulary.>

## Scope

- In scope: <…>
- Out of scope: <…>

## Dependencies

<Other plans, modules, or subsystems this touches. Link to specific files.>

## Verification

<How we'll know it worked. Tests, metrics, user-visible behavior — whichever applies to this domain.>
```

Hand off to `todo-plan` once the stub exists if the user wants immediate execution tracking. Otherwise the stub sits in `new/` until prioritized.
