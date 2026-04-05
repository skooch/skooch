# Migration Decision Table

## Instructions Files

| Situation | Action |
| --- | --- |
| Existing `CLAUDE.md` only | Leave it where it is and create repo-root `AGENTS.md` as a relative symlink to it. |
| Existing `CLAUDE.md` plus repo-root `AGENTS.md` with identical content | Replace repo-root `AGENTS.md` with a relative symlink to the existing `CLAUDE.md`. |
| Existing `CLAUDE.md` plus repo-root `AGENTS.md` with different content | Merge any missing repo-specific guidance from `AGENTS.md` into the existing `CLAUDE.md`, then replace repo-root `AGENTS.md` with a relative symlink to that `CLAUDE.md`. |
| Repo-root `AGENTS.md` only | Keep `AGENTS.md` as the canonical instruction file. |
| Neither file exists | Create repo-root `AGENTS.md`. |
| More than one non-identical `CLAUDE.md` exists | Stop and ask the user which file is canonical. |

Use relative symlinks. Example: if the preserved file is `.claude/CLAUDE.md`, the correct entrypoint is `AGENTS.md -> .claude/CLAUDE.md`.

## Plans

Canonical plan root: `docs/plans/`

Required lifecycle folders:

- `docs/plans/new/`
- `docs/plans/in-progress/`
- `docs/plans/implemented/`
- `docs/plans/paused/`

Migration rules:

- Move files from `.claude/plans/new/` to `docs/plans/new/`.
- Move files from `.claude/plans/in-progress/` to `docs/plans/in-progress/`.
- Move files from `.claude/plans/implemented/` to `docs/plans/implemented/`.
- Move files from `.claude/plans/paused/` to `docs/plans/paused/`.
- Move loose legacy plan files into `docs/plans/new/` unless their state is unambiguous.
- On path conflicts, stop and ask instead of overwriting.

## Repo-Local Skills

Generic skill entrypoint: `.agents/skills/`

Migration rules:

| Situation | Action |
| --- | --- |
| Existing `.claude/skills/` only | Leave it where it is and create `.agents/skills` as a relative symlink to `.claude/skills`. |
| Existing `.claude/skills/` plus `.agents/skills/` with non-conflicting extra skills in `.agents/skills/` | Merge the missing skill folders into `.claude/skills/`, then replace `.agents/skills` with a relative symlink to `.claude/skills`. |
| Existing `.claude/skills/` plus `.agents/skills/` with conflicting same-name skills | Stop and ask the user which version is canonical. |
| Existing `.agents/skills/` only | Keep `.agents/skills/` as the real skill root. |
| Neither path exists | Create `.agents/skills/`. |

Keep skill folder names aligned with each skill's frontmatter `name`.

Compatibility rule:

- If `.claude/skills/` did not previously exist but agent-style discovery is explicitly needed, create `.claude/skills` as a relative symlink to `../.agents/skills`.
- Do not replace an existing real `.claude/skills/` directory with a symlink to `.agents/skills`.
