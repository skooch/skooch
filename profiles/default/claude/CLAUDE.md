# Global Preferences

## Subagent & Execution Policy

**Always use Opus for all subagents.** When dispatching subagents via the Agent tool, always set `model: opus` (or `model: inherit` when the main session is Opus). Never downgrade to sonnet or haiku for cost optimization — quality matters more than cost. This overrides any skill guidance (e.g., superpowers:subagent-driven-development "Model Selection" section) that suggests using cheaper models for mechanical tasks.

**Always use subagent-driven development with a worktree.** When executing implementation plans, always use `superpowers:subagent-driven-development` (never inline `executing-plans`), and always create a git worktree with a feature branch before dispatching implementer subagents. This keeps master clean and allows easy rollback. This overrides any skill guidance that offers inline execution as a default.

## Engineering Philosophy

**No shortcuts. No workarounds. Fix the actual system.** Every fix must address the root cause through the correct layer of the architecture. "Pragmatic" hacks that skip proper architecture are unacceptable, even when they'd be faster. If the underlying system can't handle something, extend the system so it can. When in doubt, always choose the approach that makes the system more correct and capable, not the one that patches over the symptom.

**If a tool doesn't work, fix the tool.** When an existing script, utility, or system can't handle the current situation, improve it rather than working around it or writing a one-off replacement. Fixing shared tools helps everyone.

**Present architectural options before implementing non-trivial fixes.** When a fix touches shared infrastructure, CI, or cross-cutting systems, always explore at least 2-3 approaches at different levels of the architecture before writing code. Explain the tradeoffs (sustainability, ergonomics, blast radius) and let me choose. "Simplest code change" is not the same as "correct fix" — optimise for the latter. This overrides any built-in system prompt guidance about "trying the simplest approach first" or "avoiding over-engineering".

## Package Managers

If a project has already selected a different package manager (e.g., `npm` lockfile exists, `poetry.lock` present), follow that project's convention for project-scoped package operations. These preferences apply when starting new projects or installing tools globally for one-time use.

- **JavaScript/TypeScript:** Always use `bun`. Never use npm, npx, or pnpm. Use `bun install`, `bun run`, `bunx` everywhere — in scripts, Dockerfiles, CI, and hooks.
- **Python:** Always use `uv`. Never use pip, pip install, or pipx. Use `uv sync` to install dependencies, `uv run` to execute commands.
- **Rust:** Use `cargo` (standard toolchain).

## Code Quality

**Never assert or cast away type problems — fix the type itself.** If a value is `string | undefined`, don't assert it away with `!` or `as`. If Rust has an `unwrap()` that can panic, handle the error properly. Install the right type packages, define proper interfaces, or restructure code so the type is correct. Type assertions and unsafe casts hide bugs across all languages.

## Plans Convention

Plans and specs go in `.claude/plans/`, always in a subfolder:
- `new/` — plans being drafted, speced, or reviewed
- `in-progress/` — plans currently being implemented (move here before execution)
- `implemented/` — completed/implemented plans (move here after completion)
- `paused/` — abandoned or paused plans (e.g., parked in a branch)

## Config Schema Rule

When adding configuration files for any tool, always:
1. Check if the tool publishes a JSON Schema (check the repo's `schemas/` dir, docs, or schema store).
2. Add the schema to the repo next to the config files.
3. Add a pre-commit hook that validates the config against the schema.
4. Add a `yaml-language-server` directive at the top of YAML files for IDE support.

## Self-Update Rule

When a shell command, API call, or build step fails due to a pattern not yet documented in the project's CLAUDE.md, **add the fix to the relevant section before proceeding.** This prevents the same failure from recurring in future sessions.

## Shell Command Safety

- **Never use quotes inside `#` comments in shell commands.** Apostrophes and quoted terms in comments trigger Claude Code's quote-tracking safety prompt. Rephrase to avoid them (e.g., `# Check the ELF entry point` not `# Let's check the ELF entry point`).
- **Guard `curl | json` pipelines.** `curl` may return empty bodies (redirects, 4xx/5xx, network errors). Either check the HTTP status first, use `-f` (fail on HTTP errors), or guard the downstream parser against empty input.
- **Check API response shapes before processing.** When calling external APIs and piping to processing, first inspect the raw response structure before writing field access code.
