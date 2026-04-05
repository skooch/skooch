# Global Preferences

## Package Managers
- Follow existing lockfile conventions. Otherwise: JS=`bun`, Python=`uv`, Rust=`cargo`.
- mise manages tool versions (shims: `~/.local/share/mise/shims`).
- In Codex shells, shell startup should already provide the `mise` environment. Do not prepend routine commands with `eval "$(mise activate zsh)"`.
- If a tool is missing or resolves unexpectedly, check the environment first with `command -v <tool>`, `echo $PATH`, or `mise current`. If shell init is broken or the tool is genuinely not installed, use `mise` directly, for example `mise install`, and only use `eval "$(mise activate zsh)"` as a targeted diagnostic or recovery step in that shell.

## Subagent & Execution Policy
- Opus/GPT-5.4: planning, speccing, thinking, implementation. Sonnet/GPT-5.4-Mini: reviewing, comparing. Haiku/GPT-5.3-Codex-Spark: searching, exploring. Overrides skill guidance.

## Worktree Setup (mandatory sequence)
- **Never use `EnterWorktree` or `isolation: "worktree"`** — they create worktrees inside the repo (.claude/worktrees/).
- Worktrees MUST be peers in `../worktrees/<name>`. Cargo bug: nested worktrees inherit `.cargo/config.toml` twice.
- Procedure: `git worktree add ../worktrees/<name> -b <branch>` → dispatch subagent with cwd at worktree.
- The dotfiles git wrapper auto-handles: submodule bootstrap (via `--reference`), cargo target isolation (`.cargo/.worktree-target`), and safe removal (submodule deinit before remove).
- Codex agent shells use `zsh -lc`, so command wrappers and Codex-safe `mise` bootstrap must live in `.zshenv`, not only `.zshrc`.
- mise trust is automatic for `~/projects` paths (global `trusted_config_paths`). No manual trust step needed.

## Debugging
- Execute user's direct diagnosis/instruction first. Say so explicitly if you disagree.
- User's hardware observations outweigh code-reading inferences.

## Engineering Philosophy
- No shortcuts/workarounds. Fix the actual system at the correct architectural layer.
- Fix insufficient tools rather than working around them.
- Non-trivial cross-cutting fixes: present 2-3 options with tradeoffs. Let user choose.
- Evaluate non-trivial/systemic fixes in the context of the current project's goals, purpose, risks, and constraints before recommending a direction.
- Prefer the option that leaves the system simpler, easier to change, lower in developer cognitive load, and more efficient or performant; weight those factors based on the project context.
- Overrides "simplest approach first" / "avoid over-engineering" defaults.

## Code Quality
- Never use `!`, `as`, `unwrap()` to silence type errors. Fix the underlying type.

## Git
- Never append Co-Authored-By lines to commits.

## Plans Convention
- `.claude/plans/` subfolders: `new/`, `in-progress/`, `implemented/`, `paused/`.
- Before implementing: move plan from `new/` to `in-progress/`.
- After completing: move from `in-progress/` to `implemented/`.
- Abandoned mid-work: move to `paused/`.

## Completion Gate
- When working from a written plan or an explicit verification checklist, every required verification step is part of completion, not follow-up.
- Do not claim completion, stop implementation, or move a plan to `implemented` while a required manual, slow, or end-to-end verification step remains unrun.
- Green unit tests, full test suites, and static checks do not override a missing required verification step.
- If a required verification step is blocked by time, a broken source URL, unavailable hardware, or another external dependency, say so explicitly with the concrete blocker, keep the work in-progress unless the user agrees otherwise, and treat the task as incomplete.

## Config Schema Rule
- New config files: find JSON Schema, add to repo, add pre-commit validation hook, add `yaml-language-server` directives to YAML.

## Self-Update Rule
- On undocumented build/command failure, add fix to CLAUDE.md before proceeding.
- 2026-04-05: `~/.claude/skills/.system/skill-creator/scripts/quick_validate.py` may run under a `python3` without `PyYAML`; keep the validator dependency-free enough to validate simple skill frontmatter instead of assuming `yaml` is installed.
- 2026-04-05: In `exec_command` shells, `profile` may be unavailable as a shell function even under `zsh -lc`; source `lib/profile/index.sh` explicitly before invoking `profile` subcommands from automation.
- If a `~/.codex/hooks/*.py` hook fails with `permission denied`, invoke it via `python3 <hook> ...` because the symlink target may be missing the executable bit.
- If a workflow overrides `HOME`, do not rely on `mise` shims continuing to work. Capture a real interpreter path first, then use that absolute binary after `HOME` changes.

## GitHub Access
- Always use `gh` CLI. Never `raw.githubusercontent.com` or `WebFetch` for repo contents.

## Shell Command Safety
- No quotes/apostrophes in `#` shell comments.
- Guard `curl | json` pipelines against empty responses (`-f` or check status).
- Inspect API response shapes before writing field access code.

## Correction Survival
- On user correction: IMMEDIATELY append a dated bullet to local `.claude/corrections.md` before anything else.
- Keep `.claude/corrections.md` machine-local only. Never commit it.
- After context compaction: re-read local `.claude/corrections.md` if it exists, then treat its contents as temporary mandatory rules.
- Prune or delete `.claude/corrections.md` entries after promoting them into durable instructions.
