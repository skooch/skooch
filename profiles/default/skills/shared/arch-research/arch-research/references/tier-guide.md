# Tier Guide

Tiers group ideas by expected cost-to-value and by whether adoption language applies. Tier assignment is independent of classification — a single `adopt` idea could be Tier 1 (cheap + high value) or Tier 2 (medium cost), while a `translate` idea from a historical OS lives in Tier 6.

## Within-OS idea tiers (ideas inside one comparison doc)

### Tier 1: High Value, Tractable

- The gap is real and visible in incident logs, bug reports, or code smells.
- The translation into our stack is mechanical.
- Implementation cost is S or M (one developer, days not weeks).
- Adopting it does not block or constrain other work.

### Tier 2: Medium Value

- The gap exists but is not currently causing pain.
- Translation requires some new types or a small refactor.
- Implementation cost is M or L.
- Adopting it would be meaningful but is not urgent.

### Tier 3: Nice to Have

- The gap is real but niche.
- Adopting it improves tooling, debugging, or developer ergonomics more than runtime behavior.
- Cost may be any size; what distinguishes Tier 3 is lower urgency and lower frequency of hitting the gap.

## OS-level tiers (which OSes are worth a doc at all)

These match the tier structure used in `docs/architecture/comparisons/todo.md`. The tier of the OS itself affects how the comparison doc is framed:

- **Tier 1 OSes** (directly analogous, same class of device/problem) — PebbleOS, esp-rtos, WASP-OS, Bangle.js, AsteroidOS. Expect many `adopt` and `translate` entries.
- **Tier 2 OSes** (RTOSes with transferable ideas) — FreeRTOS, NuttX, Mynewt, RIOT, ThreadX, ChibiOS. Mix of `translate` and `keep`.
- **Tier 3 OSes** (Rust-native / novel isolation) — Tock, Hubris, Ariel OS, RTIC, Drone OS. Mostly `translate`; some direct `adopt` opportunities in idiomatic Rust patterns.
- **Tier 4 OSes** (bigger systems, principles only) — Fuchsia, seL4, QNX, Genode, Redox. Almost entirely `translate` or `ask`.
- **Tier 5 OSes** (skim-only) — RT-Thread, LiteOS. Short doc, mostly `keep`/`skip`.
- **Tier 6 OSes** (historical / inspirational) — PalmOS, Mac System 6/7, Newton, EPOC, BeOS, AmigaOS, RISC OS, GEOS, NeXTSTEP, CP/M, GO/PenPoint, Danger Hiptop. Special framing below.

## Tier 6 framing (historical / inspirational)

These OSes are often 20–40 years old, ran on hardware that no longer exists, and had constraints different from ours. They still carry ideas, but the framing has to be explicit:

- **Intro paragraph** says "this is an inspirational / ergonomics-focused comparison" so readers don't expect literal code transfer.
- **"Where We Already Match or Beat" table** is still useful, though more rows will have *Different problem* verdicts.
- **Ideas Worth Stealing** entries:
  - Classification defaults to `translate`. `adopt` is almost always wrong for a Tier 6 OS.
  - The "Proposed" field does heavy lifting — it's the entire translation into our stack's language.
  - `keep` is valuable: historical OSes often had ideas we've rediscovered, and pointing that out builds trust in the skim.
- **Tier assignment within the doc** still uses Tier 1/2/3 for value/cost, not the OS's own tier.
- **No "Proposed" should say "reimplement X"**. Translate the *shape* of the idea, not the artifact.

**Good Tier 6 "Proposed" example:**
> **Proposed**: Model our preferences layer on Newton's soup concept: a single typed object store where any subsystem can add records under its own tag, with a unified iteration/query API. Our current `define_preference!` macro grew per-key accessors, which is the opposite direction. A soup-shaped rewrite is a real refactor (Tier 2 cost) but it collapses six ad-hoc preference modules into one.

**Bad Tier 6 "Proposed" example:**
> **Proposed**: Add NewtonScript. ✗

## How to pick a tier for an individual idea

Work through the four questions in order. Stop at the first match.

1. **Is this shovel-ready?** The gap is visible in code, the translation is straightforward, cost is S/M. → **Tier 1**.
2. **Is this a real gap but not urgent?** Cost is M/L, translation requires new types or a refactor. → **Tier 2**.
3. **Is this ergonomic / tooling / debug polish?** Niche, but would help daily work. → **Tier 3**.
4. **Does this change the shape of the project?** Architectural, cross-cutting, or requires product decisions. → Leave tier blank and set Classification to `ask`.

If you find yourself wanting to put something in "Tier 4", stop — it probably belongs in `## Concepts That Don't Apply` instead.
