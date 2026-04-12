# Skill Auto-Share: Close the Orphan Timing Gap

## Problem

When agents create skills during sessions, they land in native directories (`~/.claude/skills/`, `~/.codex/skills/`). The profile system's orphan ingestion (`_profile_ingest_orphan_skills`) correctly moves these to `profiles/default/skills/shared/` — but only during `profile sync`, which is manual and easy to forget.

**Root cause:** Missing feedback loop. The system has ingestion (pull on sync) but no interception (push on creation). The gap is temporal, not architectural.

## Evidence

| Fact | Source | Implication |
|------|--------|-------------|
| Orphan ingestion works correctly | `sync.sh:950-1034` | Logic is sound, just needs earlier trigger |
| `profile use` skips orphan ingestion | `sync.sh:1156` (apply vs sync) | Skills orphaned between `use` and `sync` |
| Claude has PostToolUse hooks | Hook docs | Can intercept Write to SKILL.md immediately |
| Codex has NO PostToolUse hooks | Only SessionStart/UserPromptSubmit/Stop | Cannot intercept at creation time |
| Skills require SKILL.md to be valid | `sync.sh:969` | Clear detection criterion |
| Shared routing already works via audience dirs | `sync.sh:1036-1148` | No routing changes needed |

## Classification

**Local refactor** — all infrastructure exists. We're adding a trigger, not redesigning the system.

## Options

### Option A: Agent-specific hooks + apply-time ingestion (recommended)

Three layers of defense against orphaned skills:

1. **Claude PostToolUse hook** — Fires immediately when SKILL.md is written to `~/.claude/skills/<name>/SKILL.md`. Runs single-skill ingestion inline (move → scaffold openai.yaml → symlink back). Subsequent writes to the skill dir follow the symlink to the shared location. Returns `additionalContext` informing Claude the skill was auto-shared.

2. **Codex Stop hook** — Runs orphan scan at session end. Codex lacks PostToolUse, so this is the earliest reliable trigger. Skills created during a Codex session get ingested when it ends.

3. **`profile use` includes orphan ingestion** — Add `_profile_ingest_orphan_skills` to `_profile_apply_skills`. Catches anything missed on next profile activation.

All three call the same core function: a standalone `skill-auto-share` script that runs single-skill or batch ingestion.

**Tradeoffs:**
- (+) Zero friction for Claude (immediate), reasonable for Codex (session end)
- (+) Three independent triggers — belts and suspenders
- (+) Single ingestion function, multiple callers
- (-) Two hook mechanisms (PostToolUse vs Stop) because of agent capability gap
- (-) Codex skills don't move until session ends (acceptable — skill is usable locally until then)

**Agent-specific opt-out:** Skills intended to be agent-specific go in `profiles/default/skills/claude/` or `codex/` directory. The hook can detect this by checking if the user explicitly created it via skill-creator with an agent-specific flag, or by a naming convention. Simplest: hook always ingests to shared, user moves to agent-specific audience dir if needed (same as today's manual workflow, just faster).

### Option B: Shell-function wrapper with fswatch

Use `fswatch` (or `kqueue`) to watch `~/.claude/skills/` and `~/.codex/skills/` for new SKILL.md files, triggering ingestion in real-time regardless of which agent created them.

**Tradeoffs:**
- (+) Agent-agnostic — works for any future agent too
- (+) Real-time for all agents
- (-) External daemon dependency (fswatch)
- (-) Harder to manage lifecycle (start/stop, backgrounding, error handling)
- (-) Shell overhead for always-on watcher
- (-) Doesn't integrate with profile system's existing hook patterns

### Option C: Only add orphan ingestion to `profile use`

Simplest possible change: add `_profile_ingest_orphan_skills` to `_profile_apply_skills`.

**Tradeoffs:**
- (+) One-line change
- (+) No new hooks or scripts
- (-) Only catches orphans on next `profile use`, not during session
- (-) Doesn't solve the core timing problem — just makes the window smaller

## Recommendation

**Option A**. It's the only option that closes the timing gap at creation time for Claude (the primary agent) while covering Codex at session end. Option C is worth doing regardless as defense-in-depth (and it's a one-liner), but alone it doesn't solve the problem. Option B solves it universally but introduces external daemon complexity.

## Implementation Plan

### Step 1: Standalone ingestion script
Create `lib/profile/skill-auto-share.sh` (or integrate into helpers.sh):
- `_profile_ingest_single_skill <agent> <skill_dir>` — move one skill to shared, scaffold, symlink
- Reuses logic from `_profile_ingest_orphan_skills` but for a single skill
- Callable from hooks, scripts, and profile functions

### Step 2: Claude PostToolUse hook
Create `profiles/default/claude/hooks/skill-auto-share.sh`:
- Reads stdin JSON, extracts `tool_input.file_path`
- Pattern match: `~/.claude/skills/*/SKILL.md` (and NOT a symlinked parent dir)
- Calls `_profile_ingest_single_skill claude <skill_dir>`
- Returns JSON with `additionalContext` informing Claude

Add to `profiles/default/claude/settings.json`:
```json
"PostToolUse": [{
    "matcher": "Write",
    "hooks": [{
        "type": "command",
        "command": "~/.claude/hooks/skill-auto-share.sh"
    }]
}]
```

### Step 3: Codex Stop hook
Add to `profiles/default/codex/hooks.json`:
- Stop event runs `_profile_ingest_orphan_skills` (batch scan, not single-skill)
- Or a standalone script that sources the profile helpers and runs ingestion

### Step 4: Apply-time ingestion (Option C as bonus)
Change `_profile_apply_skills` in `sync.sh:1156`:
```bash
_profile_apply_skills() {
    _profile_ingest_orphan_skills
    _profile_skills_link "$1" "apply"
}
```

### Step 5: Tests
- Test single-skill ingestion: create orphan, run ingestion, verify move + symlink
- Test PostToolUse hook: simulate Write event JSON, verify ingestion
- Test apply-time: create orphan, run profile use, verify ingested

## Verification

- [ ] Create skill via Claude skill-creator → appears in `profiles/default/skills/shared/` immediately
- [ ] Create skill manually in `~/.codex/skills/` → ingested on Codex session end
- [ ] Run `profile use b` with orphan in `~/.claude/skills/` → ingested during apply
- [ ] Existing shared skills (symlinked) are NOT re-ingested on edit
- [ ] Agent-specific skills in `profiles/*/skills/codex/` are not affected

## Residual Risk

- Codex skills have a window (session duration) where they're agent-local. Acceptable because the skill is still usable, just not shared yet.
- If a skill is genuinely agent-specific, user must manually move it from `shared/` to `claude/` or `codex/` audience dir after auto-ingestion. This is a low-frequency operation.
