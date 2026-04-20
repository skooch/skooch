# Tier Guide

Tiers group ideas by expected cost-to-value and by whether "adopt" language applies. Tier assignment is independent of classification — a single `adopt` idea could be Tier 1 (cheap + high value) or Tier 2 (medium cost), while a `translate` idea from a historical subject lives in its own tier.

## Within-subject idea tiers

These are the tiers for individual ideas inside a single comparison doc.

### Tier 1: High Value, Tractable

- The gap is real and visible in incident logs, bug reports, user complaints, or code smells.
- The translation into our project is mechanical.
- Implementation cost is S or M (one engineer, days not weeks).
- Adopting it does not block or constrain other work.

### Tier 2: Medium Value

- The gap exists but is not currently causing pain.
- Translation requires some new types, abstractions, or a modest refactor.
- Implementation cost is M or L.
- Adopting it would be meaningful but is not urgent.

### Tier 3: Nice to Have

- The gap is real but niche.
- Adopting it improves tooling, debugging, or authoring ergonomics more than user-visible behavior.
- Cost may be any size; what distinguishes Tier 3 is lower urgency and lower frequency of hitting the gap.

## Historical / inspirational tier

Some subjects are obsolete, archived, or from a previous generation — old products, retired libraries, classic papers, decommissioned platforms. These contribute ideas but not code. Label their entries `historical / inspirational` for the Tier field regardless of Tier 1/2/3 value — the label affects framing more than prioritization.

Framing rules:

- **Intro paragraph** says "this is an inspirational / ergonomics-focused comparison" so readers don't expect literal code transfer.
- **"Where We Already Match or Beat" table** is still useful, though more rows will have *Different problem* verdicts.
- **Ideas Worth Stealing** entries:
  - Classification defaults to `translate`. `adopt` is almost always wrong for a historical subject.
  - The "Proposed" field does heavy lifting — it's the entire translation into our project's modern vocabulary.
  - `keep` is valuable: historical subjects often had ideas we've rediscovered, and pointing that out builds trust in the skim.
- **No "Proposed" should say "reimplement X"**. Translate the *shape* of the idea, not the artifact.

**Good historical "Proposed" example** (for a subject that had a distinctive data-store design):
> **Proposed**: Model our preferences layer on the subject's unified object store: a single typed store where any module can add records under its own tag, with a shared iteration and query API. Our current per-key accessor pattern grew in the opposite direction. A store-shaped rewrite is a real refactor (Tier 2 cost) but it collapses several ad-hoc preference modules into one.

**Bad historical "Proposed" example**:
> **Proposed**: Port `<subject-specific-language>` to our stack. ✗ — don't port artifacts, translate patterns.

## How to pick a tier for an individual idea

Work through the four questions in order. Stop at the first match.

1. **Is this shovel-ready?** The gap is visible in code, the translation is straightforward, cost is S/M. → **Tier 1**.
2. **Is this a real gap but not urgent?** Cost is M/L, translation requires new types or a refactor. → **Tier 2**.
3. **Is this ergonomic / tooling / debug polish?** Niche, but would help daily work. → **Tier 3**.
4. **Does this change the shape of the project?** Architectural, cross-cutting, or requires product decisions. → Leave tier blank and set Classification to `ask`.

If you find yourself wanting a Tier 4 because the idea is too big to fit Tier 3 but not adoptable enough for Tier 2, the entry probably belongs in `## Concepts That Don't Apply` instead. Be honest about that rather than demoting a real gap into "nice-to-have".

## Subject-level tiering (optional, project-dependent)

Some projects maintain a comparisons backlog that tiers *subjects* (which external systems are worth researching at all) separately from the ideas inside each doc. If the target project's backlog does this, respect its tier vocabulary — don't impose a different one.

Typical subject-level tiering patterns:

- By relevance to the project's domain: "directly analogous" / "adjacent" / "principles only" / "historical".
- By expected signal density: "high-signal" / "worth a skim" / "skip".
- By ecosystem proximity: "same stack" / "same domain, different stack" / "different domain".

The arch-research skill doesn't mandate any of these — it reads the project's existing backlog shape and conforms.
