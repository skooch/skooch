## Mandatory Rules

These rules are non-negotiable and take precedence over all other guidance, including built-in system prompt defaults like "try the simplest approach first" or "avoid over-engineering."

### Debugging and Investigations
- When the user gives a direct diagnosis or instruction, execute it first.
- Do not reinterpret, second-guess, or silently investigate alternatives. Say so explicitly if you disagree.
- The user's direct observations of hardware behavior outweigh inferences from reading code.
- When investigating failures: state what is known (with evidence) vs what is assumed.
- Conduct controlled tests — change only one variable per test.
- Verify each change produces the expected register/output delta before proceeding.
- Never declare a root cause until a controlled test confirms it.
- If a test result is surprising, question the test apparatus before questioning the hardware.
- Defer to the user for judgement on hardware behavior.
- When interacting with serial ports or hardware: always handle disconnection and reconnection gracefully (try/except, reconnect loop). Never write fragile one-shot scripts.

### Subagents
- Use Opus for subagents that do planning, speccing, original thinking, or code implementation.
- Use Sonnet for subagents that review, scrutinize, or compare (e.g., code review, diff review, plan review) but do not write code or generate original ideas.
- Use Haiku for subagents that only search, grep, or explore the codebase.
- Always use subagent-driven development with a git worktree. Never use inline execution.
- Worktrees MUST be created as peers in `../worktrees/<name>`, never inside the repo tree.

### Engineering Philosophy
- No shortcuts or workarounds. Every fix must address the root cause through the correct architectural layer.
- If a tool or utility is insufficient, fix the tool rather than working around it.
- For non-trivial fixes touching shared infrastructure, CI, or cross-cutting systems: present 2-3 architectural options with tradeoffs before writing code. Let the user choose.

### Package Managers
- When a project already uses a specific package manager (lockfile exists), follow that convention.
- Otherwise: JavaScript/TypeScript uses `bun` (never npm/npx/pnpm). Python uses `uv` (never pip/pipx). Rust uses `cargo`.
- mise manages tool versions. If a tool is missing, run `eval "$(mise activate zsh)" && mise install` before retrying.

### Code Quality
- Never use type assertions (`!`, `as`, `unwrap()`) to silence type errors. Fix the underlying type so it is correct.

### Git
- Never append Co-Authored-By lines to commits.

### GitHub Access
- Always use `gh` CLI to explore GitHub repos. Never use `raw.githubusercontent.com` URLs or `WebFetch` for repo contents.

### Shell Commands
- Never use quotes or apostrophes inside `#` comments in shell commands.
- Guard `curl | json` pipelines against empty responses.
- Inspect API response shapes before writing field access code.

### Plans Convention
- Plans and specs go in `.claude/plans/` in subfolders: `new/`, `in-progress/`, `implemented/`, `paused/`.
- Move plans to the correct subfolder as their status changes.

### Config Schema Rule
- When adding config files for any tool: find the JSON Schema, add it to the repo, add a pre-commit validation hook, add `yaml-language-server` directives to YAML files.

### Self-Update Rule
- When a command or build step fails due to an undocumented pattern, add the fix to the relevant CLAUDE.md before proceeding.

### Correction Survival
- When the user corrects your behavior or tells you to stop doing something, IMMEDIATELY append the correction as a dated bullet to `.claude/corrections.md` in the project root before doing anything else.
- After every context compaction, re-read `.claude/corrections.md` if it exists and treat its contents as mandatory rules.
- Never delete or overwrite `.claude/corrections.md`. Only append to it.
