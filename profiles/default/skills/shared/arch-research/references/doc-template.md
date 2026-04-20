# Comparison Doc Template

This is the skeleton for the output of one arch-research pass. Always prefer to match the shape of any existing sibling doc in the target project's comparisons folder — house style beats template.

## Skeleton

```markdown
# <Subject> Architecture Comparison

Comparison of <our stack / our project> against <subject>, focused on <focus lens>.

## Where We Already Match or Beat <Subject>

| Area | Us | <Subject> | Verdict |
|------|-----|-----------|---------|
| <Area 1> | <Us, with file path or graph ref> | <Them, with citation> | <Ours stronger / Matches / Theirs stronger / Different problem> |
| <Area 2> | … | … | … |

## Ideas Worth Stealing

### Tier 1: High Value, Tractable

#### 1. <Idea name>

**<Subject> pattern**: <description, with inline citation>.

**Our gap**: <gap, with file path or graph ref>.

**Proposed**: <translation into our stack — concrete, not aspirational, in our project's vocabulary>.

**Applicability**: <areas or modules>.

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

| <Subject> Concept | Why It Doesn't Fit |
|---|---|
| <Concept> | <Reason> |

## Summary

<Short prose paragraph: what theme do the adoptable ideas cluster around? Which are the cheap wins? Which are the larger pieces?>

### Priority Order for Implementation

<Group by categories appropriate to the project's domain. Examples below — pick what fits.>

**<Category 1>**
1. **<Idea>** — <why first>
2. …

**<Category 2>**
3. **<Idea>** — …

**Lower Priority**
…
```

## Domain-appropriate priority categories

Pick categories that match the project's actual concerns. Example sets:

- **Systems / backend**: Reliability, Performance, Observability, Ergonomics
- **Frontend / UI**: Correctness, UX, Performance, Extensibility
- **Data systems**: Throughput, Durability, Consistency, Operability
- **Developer tools**: Correctness, Speed, Ergonomics, Extensibility
- **Scientific / research code**: Reproducibility, Performance, Clarity
- **Creative tools**: Output quality, Authoring ergonomics, Performance, Extensibility
- **Protocol / spec implementations**: Conformance, Interop, Performance

Don't force all four into the priority list if only two apply.

## Historical / inspirational variant

For subjects that are obsolete, archived, or from a previous generation:

- Same skeleton, but the intro paragraph explicitly names the inspirational framing so readers don't expect literal code transfer.
- Classifications skew toward `translate` and `keep`. `adopt` is almost always wrong when the subject runs on dead hardware, uses a defunct language, or assumes a platform the project will never touch.
- The "Proposed" field does more work — it's the entire translation into our project's vocabulary.
- See `tier-guide.md` for the full framing rules.

## Intro paragraph rules

- One paragraph, no more than three sentences.
- State the stack or domain being compared — detect from the project's agent-facing docs (`CLAUDE.md`, `AGENTS.md`, `README.md`). Don't say "our codebase" if you can say "our <specific-stack> <specific-domain>".
- Name the focus lens explicitly.
- If historical/inspirational, note the framing.

## Table rules

- "Us" cells always cite a file path, module, or graph node. A cell like "we have X" without a citation means the claim is unverified — go verify before writing it.
- "Them" cells always cite a source (repo file, developer guide URL, spec section, paper citation).
- Verdict language is one of four fixed phrases: *Ours is stronger*, *Ours matches*, *Theirs is stronger*, *Different problem*.

## Entry rules

- Four bold fields in order: **<Subject> pattern** → **Our gap** → **Proposed** → **Applicability**.
- Close with two inline metadata lines: **Classification** and **Tier**.
- Never include verbatim code blocks from the subject. Reference types, function names, or concepts by name only — no pasted source.
- The "Proposed" field uses the project's actual vocabulary. Detect the right terms from the project's code and docs; don't invent generic placeholder names when the real ones are available.
