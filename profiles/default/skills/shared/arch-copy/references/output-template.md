# Output Template

Use this template for the written migration plan in the target repo.

```md
# Plan: Adopt Conventions From <source> Into <target>

## Goal
Adopt the source repo's useful conventions into the target repo without overwriting stronger target-specific choices or copying source-specific product baggage.

## Repos
- Source: `<path-or-gh-repo>`
- Target: `<path-or-gh-repo>`

## Summary
- Overall fit: `<high|medium|low>`
- Recommendation: `<apply selected items|apply after decisions|do not proceed>`

## Inventory
| Convention | Source evidence | Target evidence | Classification | Notes |
|---|---|---|---|---|
| CI | | | | |
| Lint/format | | | | |
| Repo instructions | | | | |

## Proposed Changes
- `<bundle 1>`
- `<bundle 2>`

## Keep In Target
- `<existing target convention worth preserving>`

## Skip From Source
- `<source-specific item and reason>`

## Open Decisions
| Order | Decision | Options | Recommended choice | Why it matters |
|---|---|---|---|---|
| 1 | | | | |

## Apply Approval
Before implementation, ask whether to apply now and which commit mode to use:
- `commit-by-item`
- `commit-all`
- `no-commit`

## Decision Walkthrough
After the user chooses a commit mode, ask each open decision as its own step-by-step question in the order above.
- Question 1: `<decision 1>`
- Question 2: `<decision 2>`
- Stop and wait for an answer after each question.

## Verification
- `<command or check>`
- `<command or check>`

## Residual Risks
- `<risk>`
```

## Example Notes For The Zig Pair

For a source/target pair like `~/projects/<source-repo>` -> `~/projects/<target-repo>` (e.g. comparing two Zig repos), a good plan would usually:
- adopt or translate formatting, test, and CI checks
- ask before changing Zig version policy
- keep the target's existing agent-doc and plan layout
- skip the source repo's GitHub Action packaging unless the target also wants to publish an action
