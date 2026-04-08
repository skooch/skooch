---
name: fix-ticket
description: >
  End-to-end ticket implementation workflow. Takes a Linear ticket ID and handles
  everything: checks out the default branch, pulls latest, installs dependencies,
  fetches ticket details from Linear, creates the branch, reviews the approach,
  implements the fix with clean atomic commits, runs appropriate tests, pushes,
  and creates a PR using the repo PR template. Use this skill whenever the user
  provides a Linear ticket ID and wants it implemented, says "fix ticket", "work on
  ticket", "implement this ticket", or gives you a ticket identifier like DEX-123,
  CON-456, BIZ-789, NOT-100, etc.
---

# Fix Ticket

Implements a Linear ticket end-to-end: from branch creation through to a merged-ready PR.

## Arguments

This skill expects a Linear ticket ID as its argument (e.g., `DEX-123`).

## Workflow

### Phase 1: Setup

1. **Fetch the ticket** from Linear using the `mcp__claude_ai_Linear__get_issue` tool with the ticket ID. Extract:
   - Title
   - Description/body
   - Branch name (Linear generates one — use it as-is)
   - Status, priority, labels, assignee for context

2. **Prepare the repo:**
   - Detect the default branch: `git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'`
   - Check it out and pull: `git checkout <default-branch> && git pull`
   - Install dependencies: `pnpm install`

3. **Create the feature branch** using the branch name from Linear:
   ```bash
   git checkout -b <linear-branch-name>
   ```

### Phase 2: Validate and review

Before writing any code, validate the ticket against the actual codebase and think critically:

**Validate accuracy first.** The ticket may contain stale or incorrect details — file paths that moved, assumptions about how something works, or commands that no longer apply. Read the relevant code and verify:

- Do the file paths, function names, and config referenced in the ticket actually exist?
- Are the described symptoms or broken behaviors reproducible?
- Are the proposed commands/changes correct for the current state of the codebase?

If the ticket contains inaccuracies, note them and adjust the implementation accordingly. If the inaccuracies are severe enough to change scope or direction, flag them to the user before proceeding.

**Then review the approach.** Once the facts are validated:

- Does the proposed approach make sense architecturally?
- Is there a meaningfully better approach than what the ticket implies?

**If you identify a significantly better approach** — not just stylistic preference, but something that changes correctness, maintainability, or scope — present both options to the user with tradeoffs and ask which to proceed with. Frame it concisely: what the ticket suggests, what you think is better, and why.

If the ticket approach is sound (or differences are minor), proceed without prompting.

### Phase 3: Implement

Write the fix following the project conventions in CLAUDE.md. Key principles:

- **Atomic commits**: Each commit should represent one logical change. If the fix naturally breaks into steps (e.g., add schema field, update resolver, add tests), commit each separately.
- **Commit messages**: Use the format `[TICKET-ID] Short description of change`. Keep messages focused on *what* changed and *why*.
- **No self-references**: Never include `Co-Authored-By` lines, AI attribution, or any mention of Claude/AI in commits or PR descriptions.
- **Lint after every change**: Run `pnpm biome check --write <changed-files>` on any modified files before committing.

### Phase 4: Test

Testing is mandatory. The scope depends on what changed — use judgment to determine appropriate coverage:

| What changed | What to test |
|---|---|
| Business logic / resolvers | Run unit tests and integration tests for affected modules: `cd <service> && pnpm test <files>` and `pnpm test:int <files>` |
| GraphQL schema | Regenerate types (`pnpm graphql-schema:update`), run type checks (`pnpm tsc --noEmit`), run related tests |
| Dockerfile | Build the image (`docker build`), verify it starts and responds |
| Database schema / Prisma | Run `pnpm prisma generate`, then integration tests |
| Package code (packages/*) | Build the package (`pnpm turbo build --filter=<package>`), test downstream consumers |
| Infrastructure (Pulumi) | Run `pulumi preview` if available, verify types |
| Config / CI files | Validate syntax, dry-run if possible |

Always run type checks on affected services: `cd <service> && NODE_OPTIONS=--max-old-space-size=8192 pnpm tsc --noEmit`

If tests fail, fix them. If a test failure reveals a problem with your implementation, fix the implementation — not the test.

### Phase 5: Push and create PR

If all tests pass, push and create the PR without asking for confirmation.

1. **Push the branch:**
   ```bash
   git push -u origin <branch-name>
   ```

2. **Create the PR** using the repo template structure. The PR body should follow this format:

   ```
   [Ticket description — a concise summary of what was done and why, referencing the Linear ticket]

   ## Breaking Changes
   - [List any, or "None"]

   ## Definition of Done
   - [x/blank] Logging and monitoring considerations
   - [x/blank] Schema changes are forwards and backwards compatible
   - [x/blank] Changes to infrastructure use Pulumi
   - [x/blank] Testing coverage is maintained/improved

   ## For the reviewer
   1. [Key change or area to focus review on]
   2. [Another key change if applicable]
   3. [Any gotchas or non-obvious decisions]
   ```

   Fill in the Definition of Done checklist honestly based on what applies. Check items that are satisfied; leave unchecked items that are not relevant but explain in the reviewer section if something important was intentionally skipped.

   Use `gh pr create` with `--title` and `--body`:
   ```bash
   gh pr create --title "[TICKET-ID] Short title" --body "$(cat <<'EOF'
   ...PR body...
   EOF
   )"
   ```

3. **Return the PR URL** to the user.

## Error handling

- If the Linear ticket cannot be found, tell the user and stop.
- If `pnpm install` fails, attempt `pnpm install --no-frozen-lockfile` once. If it still fails, report the error.
- If the branch already exists locally, ask the user whether to reset it or continue from where it is.
- If tests fail after reasonable fix attempts (2-3 tries), stop and present the failures to the user rather than looping.

## What this skill does NOT do

- It does not merge the PR.
- It does not assign reviewers (the user can do this from the PR URL).
- It does not update the Linear ticket status (the Linear-GitHub integration handles this).
