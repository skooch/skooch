# Primary Source Pointers

Where to find authoritative information about the subject, organized by subject class. Use the highest-confidence source available; cite it inline in the comparison doc.

## General source hierarchy

In descending order of authority:

1. **Official source repository** — the code itself is the most authoritative description of behavior. Use `gh` CLI to inspect (`gh repo view`, `gh api repos/...`). Never use `raw.githubusercontent.com` URLs or `WebFetch` for repo contents.
2. **Official documentation** — developer guide, reference manual, API docs, spec, standard.
3. **Official announcements and changelogs** — release notes, migration guides, deprecation notices.
4. **Project-maintained design docs** — RFCs, ADRs, design proposals inside the repo.
5. **Maintainer writings** — blog posts, conference talks, interviews by people who wrote the code.
6. **Reimplementation and preservation projects** — active rewrites (e.g. clean-room reimplementations) or archival efforts that have reverse-engineered the subject.
7. **Academic or industry papers** — especially for subjects that originated in research.
8. **Third-party tutorials and explanations** — lowest authority; useful as a starting map but verify specifics against higher-authority sources.

Primary sources cited as inline markdown links in the comparison doc.

## By subject class

### Open-source codebase (library, framework, tool)

- **Repo**: `gh repo view <owner>/<repo>`, browse via `gh api repos/<owner>/<repo>/contents/...`.
- **Docs**: usually at a subdomain or `/docs/` in the repo. Check `README.md` for pointers.
- **Changelogs / release notes**: `gh release list`, `CHANGELOG.md`, `RELEASE_NOTES.md`.
- **RFCs / design docs**: look for `docs/rfcs/`, `design/`, `architecture/`, `adr/` directories.
- **Benchmarks**: often `bench/` or `benchmarks/`; reveal performance priorities.

### Proprietary or closed-source product

- **Official documentation**: product site, developer portal.
- **SDK / API references**: downloadable SDK archives, OpenAPI specs.
- **Technical blog posts by the vendor**.
- **Reverse-engineering / preservation communities**: many closed products have active RE communities that have published detailed writeups.
- **Patents and legal filings**: sometimes the most detailed description of internal mechanisms.

### Language or runtime

- **Language specification** (often multi-hundred-page PDF or HTML spec).
- **Reference implementation** source.
- **Standard library** source (frequently the best example of idiomatic usage).
- **RFC / proposal process archives** (e.g. TC39 proposals, PEPs, Rust RFCs).
- **Compiler-team blog posts and design notes**.
- **Conference talks** by the language designers.

### Protocol or standard

- **RFC / spec document** (primary).
- **Reference implementation** (often cited in the RFC).
- **Interop test suites** — reveal edge cases and conformance levels.
- **Implementer notes** from people who shipped a compliant implementation.

### Database / storage engine

- **Source code** for the storage engine.
- **Architecture documentation** — most mature databases have architecture pages.
- **Academic papers** — most foundational DBs have associated papers (SQLite, PostgreSQL, LevelDB, RocksDB, CockroachDB, etc.).
- **Internal-design blog posts** from the maintainers.
- **Query optimizer / planner documentation** — specifically relevant if the focus lens is query processing.

### Compiler or build tool

- **Source**, especially the IR / pass directory.
- **Developer documentation** — contributor guides often reveal design intent.
- **Academic papers** for foundational tools.
- **Design docs** in the repo.

### UI toolkit or graphics system

- **Source** for the widget / primitive library.
- **API reference**.
- **Design system documentation** — reveals the ergonomics decisions.
- **Community-authored deep-dive articles** on rendering, layout, input handling.

### Creative / media tool (PDF, image, audio, video)

- **File format specification** (PDF spec, PNG spec, etc.).
- **Reference implementation source** (e.g. libpng for PNG, MuPDF for PDF).
- **Community forums and issue trackers** — reveal edge cases and real-world usage.
- **Archival / forensic tools** — often describe file format internals in remarkable detail.

### Academic paper

- **The paper itself** (primary).
- **Any reference implementation** the authors released.
- **Later papers citing it** — especially those that extend, critique, or operationalize the work.
- **Author blog posts or retrospectives**.

### Historical system (obsolete OS, retired product, archived library)

- **Preservation projects** — often the best-organized source of knowledge.
- **Books written about the system** — especially design-postmortem books.
- **Developer interviews and oral histories**.
- **Archived developer documentation** on archive.org or similar.
- **Emulators and compatibility layers** — their source reveals what they had to emulate, which tells you what was load-bearing in the original.

## Citation rules in the comparison doc

Every non-obvious claim about the subject gets an inline citation:

- **Source link**: `[description](URL)` — a specific URL, not a homepage.
- **Code reference**: `` `<owner>/<repo>` at `path/to/file.ext` `` with a commit or release tag if precision matters.
- **Spec reference**: `[RFC 1234 §5.2](https://...)`, `[ECMAScript §12.4](https://...)`.
- **Paper reference**: author + year + venue, with DOI or arXiv link.

If you have only a weak source (tutorial, blog post with no author credentials, forum comment), either find a stronger one or drop the claim. A comparison doc's credibility depends on its citations.

## When sources conflict

If primary sources disagree (e.g. documentation contradicts the code), prefer the code and note the contradiction inline. This is useful information — it means the documentation is stale or the behavior is undocumented.

## When sources are absent

Some subjects have poor documentation. If the only authoritative source is the code itself, that's fine — cite specific files and functions. If there's genuinely no accessible primary source (proprietary with no SDK, no public design docs, no active community), state that explicitly in the intro paragraph: "Primary sources for <subject> are limited; this comparison draws from <what's actually available>."
