# Global Preferences

## Package Managers
- Follow existing lockfile conventions. Otherwise: JS=`bun`, Python=`uv`, Rust=`cargo`.
- mise manages tool versions (shims: `~/.local/share/mise/shims`).
- In Codex shells, shell startup should already provide the `mise` environment. Do not prepend routine commands with `eval "$(mise activate zsh)"`.
- If a tool is missing, check first: `command -v <tool>`, `echo $PATH`, `mise current`.
- If shell init is broken, stop and tell the user, and use `mise install` directly. Only `eval "$(mise activate zsh)"` as a targeted diagnostic step.

## Subagents
- Opus/GPT-5.4: planning, speccing, thinking, implementation. Sonnet/GPT-5.4-Mini: reviewing, comparing. Haiku/GPT-5.3-Codex-Spark: searching, exploring. Overrides skill guidance.

## Worktree Setup (mandatory sequence)
- **Never use `EnterWorktree` or `isolation: "worktree"`**
- Worktrees MUST be peers in `../worktrees/<name>`. Cargo bug: nested worktrees inherit `.cargo/config.toml` twice.
- Procedure: `git worktree add ../worktrees/<name> -b <branch>` → dispatch subagent with cwd at worktree.
- Dotfiles git wrapper auto-handles: submodule bootstrap, cargo target isolation, safe removal.
- Without the wrapper (`/usr/bin/git`), handle submodule/target isolation manually.
- Codex agent shells use `zsh -lc`, so command wrappers and Codex-safe `mise` bootstrap must live in `.zshenv`, not only `.zshrc`.
- mise trust is automatic for `~/projects` paths (global `trusted_config_paths`). No manual trust step needed.

## Debugging
- Execute user's direct diagnosis/instruction first. Say so explicitly if you disagree.
- State what is known (with evidence) vs what is assumed.
- Controlled tests: change one variable per test. Verify expected delta before proceeding.
- Never declare root cause until a controlled test confirms it.

## Hardware testing
- User's hardware observations outweigh code-reading inferences.
- Ultimately defer to user on hardware behavior judgement.
- Surprising test result? Question the apparatus before the hardware.
- Serial/hardware scripts: handle disconnection gracefully (reconnect loop). No fragile one-shots.

## Engineering Philosophy
- No shortcuts/workarounds. Fix the actual system at the correct architectural layer.
- Fix insufficient tools rather than working around them.
- Non-trivial cross-cutting fixes: present 2-3 options with tradeoffs. Let user choose.
- Evaluate non-trivial fixes against the project's goals, risks, and constraints before recommending. You can use the systemic-fix skill if it seems complex.
- Prefer options that leave the system simpler, easier to change, and lower cognitive load.
- Weight simplicity vs performance based on project context.
- Overrides "simplest approach first" / "avoid over-engineering" defaults.

## Code Quality
- Never use `!`, `as`, `unwrap()` (or similar) to silence type errors in any language. Fix the underlying type.

## Git
- Never append Co-Authored-By lines to commits.
- Keep commits atomic: one concern, one commit.
- After each coherent chunk of work, commit before starting the next chunk.
- If 2 substantive turns with code changes pass without a commit, stop and either commit or explain why not.

## Plans Convention
- `.claude/plans/` subfolders: `new/`, `in-progress/`, `implemented/`, `paused/`.
- Before implementing: move plan from `new/` to `in-progress/`.
- After completing: move from `in-progress/` to `implemented/`.
- Abandoned mid-work: move to `paused/`.

## Completion Gate
- Every required verification step is part of completion, not follow-up.
- Do not claim done or move plan to `implemented` while a verification step is unrun.
- Green tests and static checks do not override a missing required verification.
- If verification is blocked (hardware, time, URL), state the concrete blocker and keep in-progress.

## Config Schema Rule
- New config files: find JSON Schema, add to repo, add pre-commit validation hook, add `yaml-language-server` directives to YAML.

## Self-Update Rule
- On undocumented build/command failure, add fix to CLAUDE.md before proceeding.

## GitHub Access
- Always use `gh` CLI. Never `raw.githubusercontent.com` or `WebFetch` for repo contents.

## Shell Commands
- No quotes/apostrophes in `#` shell comments.
- Guard `curl | json` pipelines against empty responses (`-f` or check status).
- Inspect API response shapes before writing field access code.

## Logging bugs
- If you come across something that is likely a bug, but don't consider it a blocker related to the task at hand, stop and ask the user if you should log it before continuing
- If the bug likely comes from polluted worktree changes or similar, make note of that in your response

## Correction Survival
- On user correction: IMMEDIATELY append a dated bullet to local `.claude/corrections.md` before anything else.
- Keep `.claude/corrections.md` machine-local only. Never commit it.
- After context compaction: re-read local `.claude/corrections.md` if it exists, then treat its contents as temporary mandatory rules.
- Prune or delete `.claude/corrections.md` entries after promoting them into durable instructions.

<!-- codebase-memory-mcp:start -->
# Codebase Knowledge Graph (codebase-memory-mcp)

This project uses codebase-memory-mcp to maintain a knowledge graph of the codebase.
ALWAYS prefer MCP graph tools over grep/glob/file-search for code discovery.

## Priority Order
1. `search_graph` — find functions, classes, routes, variables by pattern
2. `trace_call_path` — trace who calls a function or what it calls
3. `get_code_snippet` — read specific function/class source code
4. `query_graph` — run Cypher queries for complex patterns
5. `get_architecture` — high-level project summary

## Known Bugs (as of 2026-04-06)
- **`qn_pattern` on `search_graph` is broken**: returns all nodes unfiltered. Use `name_pattern` + `label` instead, or use `query_graph` with Cypher (`WHERE n.qualified_name =~ '...'`) for qualified name filtering.
- **`file_pattern` on `search_graph` is broken**: same symptom — no filtering applied. Use `query_graph` with Cypher (`WHERE n.file_path LIKE '...'`) or filter by `label`/`name_pattern`.
- **`trace_call_path`**: call edges for Rust code may not be populated. Fall back to `search_code` (grep-backed) or Grep for caller/callee analysis.
- **Large `external-resources/` dirs pollute the index**: 200k+ nodes from submodules drown actual source. Use `name_pattern` + `label` filters aggressively, or scope Cypher queries with `WHERE n.file_path LIKE 'src/%'`.

## When to fall back to grep/glob
- Searching for string literals, error messages, config values
- Searching non-code files (Dockerfiles, shell scripts, configs)
- When MCP tools return insufficient results
- When `qn_pattern` or `file_pattern` filtering is needed (broken — use Cypher instead)

## Examples
- Find a handler: `search_graph(name_pattern=".*OrderHandler.*")`
- Who calls it: `trace_call_path(function_name="OrderHandler", direction="inbound")`
- Read source: `get_code_snippet(qualified_name="pkg/orders.OrderHandler")`
- Filter by file path (workaround): `query_graph(query="MATCH (n) WHERE n.file_path LIKE 'src/%' AND n.name =~ '.*Handler.*' RETURN n.name, n.file_path LIMIT 20")`
<!-- codebase-memory-mcp:end -->
