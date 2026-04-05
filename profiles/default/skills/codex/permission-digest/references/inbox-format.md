# Permission Inbox Format

Use this exact handoff pair:

- `~/.codex/inbox/permission-digest.md`
- `~/.codex/inbox/permission-digest.json`

## Markdown

Keep the markdown short and readable.

Required sections:

1. `# Permission Digest`
2. `## Summary`
3. `## Observations`
4. `## Candidate Rules`
5. `## Consolidation Candidates`
6. `## Notes`

Suggested content:

- Summary: one or two sentences with the time window and whether anything was promoted.
- Observations: bullets grouped by normalized family, each with `count`, `sessions`, `first_seen`, and `last_seen`.
- Candidate Rules: bullets showing the normalized `prefix_rule` pattern and a short justification.
- Consolidation Candidates: bullets showing broader rules that should only be applied after the user confirms the wider scope.
- Notes: mention if the digest is empty, partial, or intentionally conservative.

## JSON

Use a stable object with these top-level keys:

- `generated_at`
- `window_days`
- `source_files`
- `session_count`
- `observations`
- `candidate_rules`
- `consolidation_candidates`
- `notes`

Recommended observation object:

- `family`
- `count`
- `session_count`
- `first_seen`
- `last_seen`
- `risk`
- `status`

Recommended `status` values:

- `observed` for families that have not crossed the promotion threshold
- `covered` for repeated families that are already allowed by an existing broader rule
- `candidate` for repeated families that are not yet covered and should be considered for promotion
- `consolidate` for repeated families that should be discussed as part of a broader allow instead of auto-promoted individually

Recommended candidate rule object:

- `pattern`
- `decision`
- `justification`
- `observed_count`

Recommended consolidation candidate object:

- `pattern`
- `decision`
- `justification`
- `member_families`
- `observed_count`

## Guardrails

- Normalize to command families, not raw shell lines.
- Do not suggest command families that are already covered by an existing broader `allow` rule.
- Do not auto-promote a broader allow inferred from multiple narrower families; emit it as a user-confirmation ask instead.
- Skip destructive, network-fetching, credential, and publish actions.
- Ignore one-off observations unless a later reducer explicitly promotes them.
- Keep the output deterministic enough for a batch sync job to consume without model interpretation.
