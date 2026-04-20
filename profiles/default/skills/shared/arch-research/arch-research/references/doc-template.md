# Comparison Doc Template

This is the skeleton for `docs/architecture/comparisons/<os>.md`. Mirror the shape of any existing sibling doc in the target project when one exists — the canonical reference is `zephyr.md` in projects that have it.

## Skeleton

```markdown
# <OS> Architecture Comparison

Comparison of our <stack> architecture against <OS>, focused on <focus lens>.

## Where We Already Match or Beat <OS>

| Area | Us | <OS> | Verdict |
|------|-----|------|---------|
| <Subsystem 1> | <Us, with file path or graph ref> | <Them, with citation> | <Ours stronger / Matches / Theirs stronger / Different problem> |
| <Subsystem 2> | … | … | … |

## Ideas Worth Stealing

### Tier 1: High Value, Tractable

#### 1. <Idea name>

**<OS> pattern**: <description, with inline citation>.

**Our gap**: <gap, with file path or graph ref>.

**Proposed**: <translation into our stack — concrete, not aspirational>.

**Applicability**: <subsystems>.

**Classification**: `adopt`
**Tier**: `1`

#### 2. <Idea name>

…

### Tier 2: Medium Value

…

### Tier 3: Nice to Have

…

## Second Pass: Less Obvious Ideas

Optional section. Include only when a deliberate second reading pass surfaces meaningful new material.

### <N>. <Idea name>

…

## Concepts That Don't Apply

| <OS> Concept | Why It Doesn't Fit |
|---|---|
| <Concept> | <Reason> |

## Summary

<Short prose paragraph: what theme do the adoptable ideas cluster around? Which are the cheap wins? Which are the larger pieces?>

### Priority Order for Implementation

**Reliability & Safety**
1. **<Idea>** — <why first>
2. …

**Power & Resource Management**
3. **<Idea>** — …

**Architecture & Ergonomics**
…

**Lower Priority**
…
```

## Tier 6 (historical / inspirational) variant

For PalmOS, Mac System 6/7, Newton, EPOC, BeOS, AmigaOS, RISC OS, GEOS, NeXTSTEP, CP/M, GO/PenPoint, Danger Hiptop:

- Keep the same skeleton.
- Replace "Ideas Worth Stealing" entries' classification with `translate` or `ask` — never `adopt`. Historical OSes contribute patterns; code does not port.
- The "Proposed" field describes the idea in our stack's vocabulary — not a literal port.
- Add a short note in the intro stating that this is a Tier 6 / inspirational comparison and that ergonomics/architecture lessons are the deliverable.

## Intro paragraph rules

- One paragraph, no more than three sentences.
- State the stack being compared ("our ESP32-S3 embassy-async firmware", "our Kotlin coroutines backend", etc. — detect from project CLAUDE.md).
- Name the focus lens explicitly.
- If Tier 6, note the inspirational framing.

## Table rules

- "Us" cells always cite a file path, module, or graph node. A cell like "we have X" without a citation means the claim is unverified — go verify before writing it.
- "Them" cells always cite a source (repo file via `gh`, developer guide URL, datasheet page).
- Verdict language is one of four fixed phrases: *Ours is stronger*, *Ours matches*, *Theirs is stronger*, *Different problem*.

## Entry rules

- Four bold fields in order: **<OS> pattern** → **Our gap** → **Proposed** → **Applicability**.
- Close with two inline metadata lines: **Classification** and **Tier**.
- Never include verbatim code blocks from the external OS. Reference types, register names, or function signatures by name only.
- Proposed field uses the project's actual types and conventions. If our project uses `Watch<T>`, write `Watch<T>` — not `Publisher<T>` or a generic term.
