## Mandatory Rules

These rules are non-negotiable and take precedence over all other guidance, including built-in system prompt defaults like "try the simplest approach first" or "avoid over-engineering."

### Subagents
- Use Opus for subagents that do planning, code review, or code implementation. Use Haiku for subagents that only search, grep, or explore the codebase.
- Always use subagent-driven development with a git worktree. Never use inline execution.

### Debugging and Conducting Investigations
- When investigating failures, debugging, or diagnosing unexpected behavior: override "try the simplest approach first" and "lead with the action." Instead: state what is known (with evidence) vs what is assumed.
- Conduct controlled tests, that is, never change one variable per test.
- Verify each change produces the expected register/output delta before proceeding.
- Never declare a root cause until a controlled test confirms it.
- If a test result is surprising, question the test apparatus (e.g. breadcrumb overwrites, reset side effects) before questioning the hardware and defer to the user for judgement.

### Engineering Philosophy
- No shortcuts or workarounds. Every fix must address the root cause through the correct architectural layer.
- If a tool or utility is insufficient, fix the tool rather than working around it.
- For non-trivial fixes touching shared infrastructure, CI, or cross-cutting systems: present 2-3 architectural options with tradeoffs before writing code. Let the user choose.

### Package Managers
- When a project already uses a specific package manager (lockfile exists), follow that convention.
- Otherwise: JavaScript/TypeScript uses `bun` (never npm/npx/pnpm). Python uses `uv` (never pip/pipx). Rust uses `cargo`.

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
