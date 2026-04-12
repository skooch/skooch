# Classification Rules

Use these rules when deciding whether a source convention belongs in the target repo.

## Adopt

Choose `adopt` when:
- the same tool already exists or is clearly appropriate in the target
- the target lacks the convention
- the source convention is portable with only small path or naming edits
- the maintenance cost is low and the benefit is clear

Examples:
- adding a missing formatter check for the same language
- copying a basic CI job structure when commands and targets already exist
- adopting repo conventions like issue templates or plan docs when they fit the target's process

## Translate

Choose `translate` when the source intent is good but the implementation is too source-shaped.

Translate:
- file paths
- binary or artifact names
- repo names, action names, badges, docs links
- target-specific plan or agent layout
- commands that must align to the target's existing build surface

Examples:
- keep a CI job's `fmt` and `test` guarantees but rewrite the commands for the target repo
- preserve a tracked plan workflow while writing into the target's existing `docs/plans/` layout

## Keep

Choose `keep` when the target already has:
- an equivalent convention
- a stricter or better-integrated version
- a newer layout that the source would downgrade

Examples:
- target already has a stronger agent-doc layout
- target already pins a deliberate tool version
- target already has a better-fitting release process

## Skip

Choose `skip` when the item is not a general convention.

Usually skip:
- secrets and environment-specific config
- deployment wiring
- release artifact names tied to the source product
- product-specific packaging or composite GitHub Actions
- source-specific docs, examples, assets, or changelog history
- workflows whose value depends on infrastructure the target does not have

The `align-internal` `action.yml` and `problem-matcher.json` are a good example of `skip` unless the target also wants to ship a GitHub Action with the same distribution model.

## Ask

Choose `ask` when the item changes:
- tool or language version policy
- support matrix or release policy
- repo layout or canonical instruction entrypoints
- dependency policy
- ownership or review policy
- maintenance burden in a way the user may care about

Also choose `ask` when:
- the source and target conventions conflict and both are plausible
- the target repo is too young to reveal its desired direction
- adopting the source would add several new tools or services

## Version Rule

If a convention implies changing pinned versions, default to `ask`.

Examples:
- source pins Zig `latest` but target pins `0.15.1`
- source and target use the same linter but different config generations

## Biases

- Bias toward `keep` over destructive replacement.
- Bias toward `translate` over exact copying.
- Bias toward `skip` over cargo-cult automation.
- Bias toward `ask` when a change alters long-term maintenance or release expectations.
