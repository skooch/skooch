---
name: arch-research
description: Research one external project, system, library, tool, or body of work — anything worth learning from — and produce a structured comparison document cataloging ideas worth adopting into the current project. Use whenever the user asks to research, compare, or learn from something external, whether it's a competing product, a reference implementation, an open-source library, a framework, a classic paper, a proprietary system, a PDF converter, an image processing pipeline, a database engine, a compiler, a build tool, a UI toolkit, an OS, a protocol, or any other body of software or software ideas. Also use when the user points at a comparisons backlog entry and says "do this one" or "fill in comparisons/<name>.md". Works across projects of any architecture or domain — firmware, backends, frontends, CLIs, data systems, research code, creative tools — by detecting context from the invoking project's agent-facing instructions (CLAUDE.md, AGENTS.md, README.md) rather than assuming any specific language, runtime, or domain. Produces a grounded doc with a "Where We Already Match or Beat X" table and tiered "Ideas Worth Stealing" entries, each classified adopt / translate / keep / skip / ask.
---

# Arch Research

Research one external subject at a time — another codebase, library, tool, paper, or system — and turn what you learn into a single comparison document that makes it easy to decide which ideas to adopt, translate, or skip. Treat the subject as a well-tested source of design patterns — not as authority, not as something to clone.

**Announce at start:** "I'm using the arch-research skill to research <subject> and produce a comparison doc at <path>. I'll ground the 'us' column via repo inspection before writing, loop on primary sources until discovery saturates, and classify each idea adopt/translate/keep/skip/ask."

## Terminology

- **Subject** — whatever we're researching. A library, tool, codebase, paper, product, protocol, system. The thing in the "Them" column.
- **Project** — the repo the user is working in. The thing in the "Us" column.
- **Idea** — a pattern, technique, or structure the subject embodies that might be worth adopting, translating, or skipping.

## Use This Skill To

- Catalog architectural and ergonomic ideas from an external subject in a form the current project can actually act on, regardless of what either one does.
- Produce a single comparison doc that looks and feels like siblings in the same folder (see `references/doc-template.md`).
- Classify each idea so "steal this" items graduate into plan stubs and "skip" items stop coming up in future discussions.
- Consolidate scattered prior-art references — notes embedded in design docs, chat history, old PR descriptions — into a single searchable home.

## When NOT To Use

- **Researching the current codebase.** Use a codebase-exploration skill or `arch-review` instead — this skill is outward-facing.
- **Reviewing a PR or spec.** Use `review` or `arch-review`.
- **Planning a refactor.** Use `systemic-fix` (to pick an approach) or `todo-plan` (to track execution).
- **Comparing two of your own repos.** Use `arch-copy` — same shape, different target type.
- **General web research unrelated to architecture decisions.** This skill produces a structured comparison doc; if that's not the deliverable, pick a different tool.

## Core Principles

- **One subject per invocation.** Refuse "compare us to everything". If the user names multiple, pick one and defer the rest to a backlog entry.
- **Ground the "us" column, don't infer it.** Every claim about the current project comes from a graph query, a file read, or explicit project docs. Never from prose memory or training-data recall.
- **Translate, don't copy.** Never paste verbatim code from the subject into the comparison doc. Restate ideas in the vocabulary the current project actually uses (detected from its agent-facing docs).
- **Cite or drop it.** Every non-obvious claim about the subject gets an inline source link (open-source repo file, developer guide URL, spec section, paper citation, postmortem). If you can't cite it, don't claim it.
- **Loop until saturation.** One pass of reading source material is rarely enough. Stop when an additional pass yields no new ideas, not when you hit a time budget.
- **Classify every idea.** Each entry in "Ideas Worth Stealing" gets a label: `adopt` / `translate` / `keep` / `skip` / `ask`. See `references/classification.md`.
- **Ask before promoting to a plan.** `adopt` items *may* graduate to plan stubs, but only after the user confirms — planning is a separate decision from research.

## Workflow

### 1. Scope

Confirm:
- **Subject name** (exactly one).
- **Subject class** — codebase, library, framework, tool, product, protocol, paper, etc. This affects how sources are found (phase 5) and how historical framing is handled.
- **Focus lens** if given ("for its error-handling ergonomics", "for its plugin architecture", "for its rendering pipeline", "for its query planner"). If not given, ask — an unfocused comparison sprawls.
- **Historical / inspirational framing** if the subject is obsolete, archived, or from a previous generation. Historical framing softens adopt language (see `references/tier-guide.md`).

If the user named multiple subjects, pick the first and add the rest to the project's comparisons backlog file if one exists.

### 2. Detect project context

The skill must not assume the target project's stack or domain. Read:

- `CLAUDE.md` / `.claude/CLAUDE.md` / `AGENTS.md` — conventions, stack, constraints.
- `README.md` — elevator pitch and ecosystem.
- Package/dependency manifests (`Cargo.toml`, `package.json`, `pyproject.toml`, `go.mod`, `Gemfile`, `build.gradle`, `pom.xml`, `mix.exs`, etc.) — identify language, runtime, framework.
- `docs/` or `design/` — prior architecture notes set the house style.
- Any existing comparison docs — the canonical template for this project.

Use the detected stack and domain when writing the "Proposed" fields later. Never hardcode assumptions about what the project is.

### 3. Resolve output location

Check in order:
1. If a comparisons folder already exists in the project (common paths: `docs/architecture/comparisons/`, `docs/comparisons/`, `comparisons/`, `research/`), write there and match the sibling docs' shape.
2. If the project's agent-facing docs specify a location, use it.
3. Otherwise, default to `docs/comparisons/<name>.md` and confirm the path with the user before writing.

Never create the folder silently in an unusual location — the path is visible in the end-of-turn summary and should be predictable.

### 4. Our-side inventory (grounded)

Use whatever code-intelligence tools the project provides, in this preference order:

1. **Codebase knowledge graph** (e.g. `codebase-memory-mcp`, Sourcegraph, LSIF): `search_graph`, `get_architecture`, `trace_path`, `get_code_snippet`. If the project isn't indexed yet, index it first.
2. **Language servers / LSP**: `workspaceSymbol`, `documentSymbol`, `findReferences`, `goToDefinition`.
3. **Direct file tools**: `Glob`, `Grep`, `Read` — fall back when the graph returns insufficient results or the artifact is a non-code file.

See `references/us-side-queries.md` for query patterns organized by concern type (applicable across many kinds of project).

Write findings into a draft "Where We Already Match or Beat <subject>" table. Each row: `Area | Us | Them | Verdict`. The "Us" cell must cite a file path, module, or graph node so a reviewer can verify.

### 5. Their-side inventory (iterative)

Read primary sources. Preferences in order:

- Official open-source repository (use `gh` CLI where available, never raw web URLs for repo contents).
- Official documentation, spec, reference manual, or paper.
- RFCs, white papers, formal specs where relevant.
- Reimplementation and preservation projects (for subjects with active rewrites or archived originals).
- Postmortems, interviews, blog posts, conference talks from people who actually built the subject.

`references/them-side-sources.md` has pointers organized by subject class (codebase, library/framework, tool/binary, product/service, paper/spec, historical system) — consult it to seed your first reading pass.

**Loop until saturation.** After each reading pass, note candidate ideas and open questions. Run at least one more pass that specifically hunts for areas you haven't covered. Stop when two consecutive passes yield no new ideas.

Every non-obvious claim gets an inline citation as a markdown link.

### 6. Pairwise mapping

Fill in the "Where We Already Match or Beat <subject>" table with finalized rows. One row per area or concern in scope.

Verdict is one of four fixed phrases:
- *Ours is stronger* — with reason
- *Ours matches* — equivalent ergonomics or semantics
- *Theirs is stronger* — a real gap worth examining
- *Different problem* — they solve a need we don't have, or vice versa

Anything marked *Theirs is stronger* becomes a candidate for "Ideas Worth Stealing" in the next phase.

### 7. Ideas worth stealing

For each idea, produce a structured entry:

```markdown
#### <N>. <Idea name>

**<Subject> pattern**: [concise description of how they do it, with a citation]

**Our gap**: [what we're missing, grounded in a file/graph reference]

**Proposed**: [how the idea translates into our stack — concrete, not aspirational, using our project's actual vocabulary]

**Applicability**: [which parts of our project it touches]

**Classification**: `adopt` | `translate` | `keep` | `skip` | `ask`
**Tier**: `1 (high-value tractable)` | `2 (medium)` | `3 (nice-to-have)` | `historical / inspirational`
```

Group entries by tier under `## Ideas Worth Stealing` → `### Tier N: …`.

See `references/classification.md` for how to pick the classification label, and `references/tier-guide.md` for tier assignment — especially the rules for historical/inspirational subjects that soften "adopt" language.

### 8. Second pass

After the first round of ideas lands, deliberately hunt for what's missing:

- What common area does the subject address that we didn't discuss? (Often: testing, observability, error reporting, update/migration flow, resource cleanup, debugging affordances, edge cases.)
- Which of their strengths have we not mentioned because they felt obvious?
- Which "our gaps" are actually symptoms of a shared deeper pattern worth calling out once?

Add a `## Second Pass: Less Obvious Ideas` section if the second round surfaces meaningful material. Don't force a section if it doesn't.

### 9. Concepts that don't apply

Close with a table of things from the subject that deliberately do *not* port. This is load-bearing — it signals that the skim was thorough, not cherry-picked.

```markdown
## Concepts That Don't Apply

| <Subject> Concept | Why It Doesn't Fit |
|---|---|
```

### 10. Summary and priority

End with:
- A short prose summary of the theme the adoptable ideas cluster around.
- A "Priority Order for Implementation" list grouping `adopt`/`translate` items by category and ranking within each. Categories should match the project's domain (e.g. Reliability / Performance / Ergonomics for a systems codebase; Correctness / UX / Extensibility for a user-facing tool; Throughput / Durability / Observability for a data system).

### 11. Update the backlog

- If the project has a comparisons backlog file (common name: `todo.md` in the comparisons folder), tick the subject's checkbox and move the entry to a Done section. Preserve the backlog's existing shape; don't impose one.
- If no backlog exists, don't create one unless the user asks.
- If new candidate subjects came up during research, suggest adding them to the backlog (don't add unilaterally).

### 12. Handoff (optional, ask first)

For each `adopt` idea, ask whether the user wants a plan stub. Do not create plan docs unilaterally.

If confirmed, create a stub following the project's plan conventions (detected from its agent-facing docs) and hand off to `todo-plan` for tracking. Stub skeleton is in `references/classification.md` under "Plan-stub handoff template".

## Output Contract

The comparison doc must contain, in order:

1. Title and one-paragraph intro naming the focus lens and stack being compared.
2. `## Where We Already Match or Beat <subject>` — table.
3. `## Ideas Worth Stealing` — tiered subsections with entries in the structured format.
4. `## Second Pass: Less Obvious Ideas` — optional.
5. `## Concepts That Don't Apply` — table.
6. `## Summary` — short prose + priority list.

See `references/doc-template.md` for the skeleton. If sibling docs exist in the project's comparisons folder, match their exact shape over the template — house style beats template.

## Resources

- [doc-template.md](references/doc-template.md) — skeleton for the output doc.
- [classification.md](references/classification.md) — adopt/translate/keep/skip/ask definitions and the plan-stub template.
- [tier-guide.md](references/tier-guide.md) — tier definitions and the historical/inspirational language caveat.
- [us-side-queries.md](references/us-side-queries.md) — query patterns for common concern types across project types.
- [them-side-sources.md](references/them-side-sources.md) — primary-source pointers organized by subject class.

## When To Use Other Skills

- Use a codebase-exploration skill directly for the our-side inventory phase (e.g. `codebase-memory-exploring`).
- Use `arch-copy` if the "subject" is another repo you own, not a third-party body of work.
- Use `systemic-fix` when an idea's translation into our stack needs architectural comparison of options.
- Use `todo-plan` to turn an accepted `adopt` idea into a tracked execution plan.
- Use `arch-review` for broad review of our own codebase — this skill is outward-facing only.
