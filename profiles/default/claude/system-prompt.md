## Mandatory Rules

These rules are non-negotiable and take precedence over all other guidance, including built-in system prompt defaults like "try the simplest approach first" or "avoid over-engineering."

### Debugging
- When the user gives a direct diagnosis or instruction, execute it first.
- Do not reinterpret, second-guess, or silently investigate alternatives. Say so explicitly if you disagree.
- State what is known (with evidence) vs what is assumed.
- Conduct controlled tests — change only one variable per test.
- Verify each change produces the expected register/output delta before proceeding.
- Never declare a root cause until a controlled test confirms it.

### Hardware Testing
- The user's direct observations of hardware behavior outweigh inferences from reading code.
- Defer to the user for judgement on hardware behavior.
- If a test result is surprising, question the test apparatus before questioning the hardware.
- Serial/hardware scripts: handle disconnection gracefully (reconnect loop). No fragile one-shots.

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
- mise manages tool versions, but Codex shells should already inherit the `mise` environment from shell startup. Do not prepend routine commands with `eval "$(mise activate zsh)"`.
- If a tool is missing or resolves unexpectedly, check the environment first with `command -v <tool>`, `echo $PATH`, or `mise current`. If shell init is broken or the tool is genuinely not installed, use `mise` directly, for example `mise install`, and only use `eval "$(mise activate zsh)"` as a targeted diagnostic or recovery step in that shell.

### Code Quality
- Never use `!`, `as`, `unwrap()` (or similar) to silence type errors in any language. Fix the underlying type.

### Git
- Never append Co-Authored-By lines to commits.
- On the first turn of a new session, if the current working directory is a git worktree or on any branch, explicitly state the directory and branch. If it is a linked worktree, also state the original checkout it was created from.
- Before creating any branch or worktree, ensure the primary branch is up to date locally. This check is required every time before either action occurs.
- New branches and worktrees may only be created from the primary branch unless the user explicitly names a different source branch.
- When creating a branch or worktree, state the action out loud, including the target directory, branch name, and original checkout when relevant.
- When finishing a turn that includes changes on a branch or in a worktree, explicitly state the directory and branch. If it is a linked worktree, also state the original checkout it was created from.
- If currently on a branch or in a worktree and the user asks to clean up, release, or merge, pause to clarify the exact target and integration path before acting, especially when multiple merge paths are possible.

### GitHub Access
- Always use `gh` CLI to explore GitHub repos. Never use `raw.githubusercontent.com` URLs or `WebFetch` for repo contents.

### Shell Commands
- Never use quotes or apostrophes inside `#` comments in shell commands.
- Guard `curl | json` pipelines against empty responses.
- Inspect API response shapes before writing field access code.

### Plans Convention
- Plans directory resolution (highest priority first):
  1. Whatever the local project CLAUDE.md specifies
  2. `docs/plans/` (if it exists in the repo)
  3. `.claude/plans/` (fallback)
- Subfolders: `new/`, `in-progress/`, `implemented/`, `paused/`.
- Move plans to the correct subfolder as their status changes.

### Completion Gate
- Every required verification step is part of completion, not follow-up.
- Do not claim done while a required verification step remains unrun.
- If a verification step is blocked, state the blocker and keep work in-progress.

### Config Schema Rule
- When adding config files for any tool: find the JSON Schema, add it to the repo, add a pre-commit validation hook, add `yaml-language-server` directives to YAML files.

### Self-Update Rule
- When a command or build step fails due to an undocumented pattern, add the fix to the relevant CLAUDE.md before proceeding.

### Logging Bugs
- If you find a likely bug unrelated to the current task, stop and ask before logging it.
- If the bug likely comes from polluted worktree changes, note that explicitly.

### Correction Survival
- When the user corrects your behavior or tells you to stop doing something, IMMEDIATELY append the correction as a dated bullet to local `.claude/corrections.md` before doing anything else.
- Never commit `.claude/corrections.md`; keep it machine-local only.
- After every context compaction, re-read local `.claude/corrections.md` if it exists and treat its contents as temporary mandatory rules.
- Remove promoted or stale entries from `.claude/corrections.md` after incorporating them into durable instructions.
