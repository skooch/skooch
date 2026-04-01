# Global Preferences

## Subagent & Execution Policy
- Opus: planning, speccing, thinking, implementation. Sonnet: reviewing, comparing. Haiku: searching, exploring. Overrides skill guidance.
- Always use `superpowers:subagent-driven-development`, never inline `executing-plans`.

## Worktree Setup (mandatory sequence)
- **Never use `EnterWorktree` or `isolation: "worktree"`** — they create worktrees inside the repo (.claude/worktrees/).
- Worktrees MUST be peers in `../worktrees/<name>`. Cargo bug: nested worktrees inherit `.cargo/config.toml` twice.
- Procedure: `git worktree add ../worktrees/<name> -b <branch>` → `mise trust ../worktrees/<name>/.mise.toml` → dispatch subagent with cwd at worktree.

## Debugging
- Execute user's direct diagnosis/instruction first. Say so explicitly if you disagree.
- User's hardware observations outweigh code-reading inferences.

## Engineering Philosophy
- No shortcuts/workarounds. Fix the actual system at the correct architectural layer.
- Fix insufficient tools rather than working around them.
- Non-trivial cross-cutting fixes: present 2-3 options with tradeoffs. Let user choose.
- Overrides "simplest approach first" / "avoid over-engineering" defaults.

## Package Managers
- Follow existing lockfile conventions. Otherwise: JS=`bun`, Python=`uv`, Rust=`cargo`.
- mise manages tool versions (shims: `~/.local/share/mise/shims`). Missing tool: `eval "$(mise activate zsh)" && mise install`.

## Code Quality
- Never use `!`, `as`, `unwrap()` to silence type errors. Fix the underlying type.

## Git
- Never append Co-Authored-By lines to commits.

## Plans Convention
- `.claude/plans/` subfolders: `new/`, `in-progress/`, `implemented/`, `paused/`.
- Before implementing: move plan from `new/` to `in-progress/`.
- After completing: move from `in-progress/` to `implemented/`.
- Abandoned mid-work: move to `paused/`.

## Config Schema Rule
- New config files: find JSON Schema, add to repo, add pre-commit validation hook, add `yaml-language-server` directives to YAML.

## Self-Update Rule
- On undocumented build/command failure, add fix to CLAUDE.md before proceeding.

## GitHub Access
- Always use `gh` CLI. Never `raw.githubusercontent.com` or `WebFetch` for repo contents.

## Shell Command Safety
- No quotes/apostrophes in `#` shell comments.
- Guard `curl | json` pipelines against empty responses (`-f` or check status).
- Inspect API response shapes before writing field access code.

## Correction Survival
- On user correction: IMMEDIATELY append dated bullet to `.claude/corrections.md` before anything else.
- After context compaction: re-read `.claude/corrections.md`, treat as mandatory.
- Never delete/overwrite, only append.
