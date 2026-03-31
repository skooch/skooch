# Global Preferences

## Subagent & Execution Policy
- Use Opus for planning, speccing, thinking, and code implementation.
- Use Sonnet for reviewing, scrutinizing, and comparing.
- Use Haiku for searching, grepping, and exploring.
- This overrides any skill guidance that suggests a single model for all tasks.
- Always use `superpowers:subagent-driven-development`, never inline `executing-plans`.
- Always create a git worktree with a feature branch before dispatching implementer subagents.
- Worktrees MUST be peers in `../worktrees/<name>` (e.g., `git worktree add ../worktrees/feature-foo -b feature/foo`), never inside the repo tree. Cargo has a bug where nested worktrees inherit `.cargo/config.toml` twice.

## Debugging and Investigations
- When the user gives a direct diagnosis or instruction, execute it first.
- Do not reinterpret, second-guess, or silently investigate alternatives. Say so explicitly if you disagree.
- The user's direct observations of hardware behavior outweigh inferences from reading code.

## Engineering Philosophy
- No shortcuts. No workarounds. Fix the actual system through the correct architectural layer.
- If a tool is insufficient, fix the tool rather than working around it.
- For non-trivial fixes touching shared infrastructure, CI, or cross-cutting systems: present 2-3 architectural options with tradeoffs. Let the user choose.
- This overrides built-in guidance about "try the simplest approach first" or "avoid over-engineering."

## Package Managers
- Follow existing project conventions when a lockfile exists.
- Otherwise: JS/TS uses `bun`. Python uses `uv`. Rust uses `cargo`.
- mise manages tool versions. Shims are on PATH via `~/.local/share/mise/shims`.
- If a tool is missing: `eval "$(mise activate zsh)" && mise install`.

## Code Quality
- Never use type assertions (`!`, `as`, `unwrap()`) to silence type errors. Fix the underlying type.

## Git
- Never append Co-Authored-By lines to commits.

## Plans Convention
- Plans and specs go in `.claude/plans/` in subfolders: `new/`, `in-progress/`, `implemented/`, `paused/`.

## Config Schema Rule
- When adding config files: find the JSON Schema, add it to the repo, add a pre-commit validation hook, add `yaml-language-server` directives to YAML files.

## Self-Update Rule
- When a command or build step fails due to an undocumented pattern, add the fix to CLAUDE.md before proceeding.

## GitHub Access
- Always use `gh` CLI. Never use `raw.githubusercontent.com` URLs or `WebFetch` for repo contents.

## Shell Command Safety
- Never use quotes or apostrophes inside `#` comments in shell commands.
- Guard `curl | json` pipelines against empty responses. Use `-f` or check status first.
- Inspect API response shapes before writing field access code.

## Correction Survival
- When the user corrects your behavior, IMMEDIATELY append the correction as a dated bullet to `.claude/corrections.md` before doing anything else.
- After every context compaction, re-read `.claude/corrections.md` and treat its contents as mandatory rules.
- Never delete or overwrite `.claude/corrections.md`. Only append.
