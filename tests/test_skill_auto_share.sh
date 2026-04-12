#!/usr/bin/env zsh
# Test skill auto-share: single-skill ingestion, batch orphan ingestion,
# apply-time ingestion, and the Claude PostToolUse hook script.

source "${0:A:h}/harness.sh"

# Override HOME so agent dirs are inside the test sandbox
HOME="$TEST_HOME"

# --- Helper: create an orphan skill in an agent directory ---

create_orphan_skill() {
    local agent="$1" skill_name="$2" description="${3:-Test skill}"
    local skill_dir="$TEST_HOME/.$agent/skills/$skill_name"
    mkdir -p "$skill_dir"
    cat > "$skill_dir/SKILL.md" <<EOF
---
name: $skill_name
description: $description
---

# $skill_name
Test content.
EOF
}

# --- _profile_ingest_single_skill tests ---

_TEST_NAME="ingest_single_skill: moves orphan to shared and symlinks back"
create_orphan_skill claude test-skill-a "A test skill"
local skill_dir="$TEST_HOME/.claude/skills/test-skill-a"
local output=$(_profile_ingest_single_skill "$skill_dir" "claude" 2>&1)
assert_file_exists "$PROFILES_DIR/default/skills/shared/test-skill-a/SKILL.md"
assert_file_exists "$PROFILES_DIR/default/skills/shared/test-skill-a/agents/openai.yaml"
assert_symlink "$TEST_HOME/.claude/skills/test-skill-a" "$PROFILES_DIR/default/skills/shared/test-skill-a"
assert_contains "$output" "ingested test-skill-a from claude -> shared"

_TEST_NAME="ingest_single_skill: scaffolds openai.yaml with extracted metadata"
local yaml_content=$(cat "$PROFILES_DIR/default/skills/shared/test-skill-a/agents/openai.yaml")
assert_contains "$yaml_content" "display_name"
assert_contains "$yaml_content" "A test skill"

_TEST_NAME="ingest_single_skill: skips if already in profile"
# Remove the symlink so it looks like a real dir again
rm -f "$TEST_HOME/.claude/skills/test-skill-a"
create_orphan_skill claude test-skill-a "Duplicate"
local skill_dir="$TEST_HOME/.claude/skills/test-skill-a"
_profile_ingest_single_skill "$skill_dir" "claude" >/dev/null 2>&1
assert_eq "1" "$?"

_TEST_NAME="ingest_single_skill: skips symlinked directories"
mkdir -p "$TEST_HOME/.claude/skills"
ln -sfn "/some/fake/target" "$TEST_HOME/.claude/skills/symlinked-skill"
_profile_ingest_single_skill "$TEST_HOME/.claude/skills/symlinked-skill" "claude" 2>&1
assert_eq "1" "$?"

_TEST_NAME="ingest_single_skill: skips directories without SKILL.md"
mkdir -p "$TEST_HOME/.claude/skills/no-skillmd"
echo "not a skill" > "$TEST_HOME/.claude/skills/no-skillmd/README.md"
_profile_ingest_single_skill "$TEST_HOME/.claude/skills/no-skillmd" "claude" 2>&1
assert_eq "1" "$?"

_TEST_NAME="ingest_single_skill: skips .system directory"
mkdir -p "$TEST_HOME/.claude/skills/.system"
echo "---\nname: system\n---" > "$TEST_HOME/.claude/skills/.system/SKILL.md"
_profile_ingest_single_skill "$TEST_HOME/.claude/skills/.system" "claude" 2>&1
assert_eq "1" "$?"

# --- _profile_ingest_orphan_skills (batch) tests ---

_TEST_NAME="ingest_orphan_skills: ingests from both claude and codex"
create_orphan_skill claude batch-claude-skill "From Claude"
create_orphan_skill codex batch-codex-skill "From Codex"
local output=$(_profile_ingest_orphan_skills 2>&1)
assert_file_exists "$PROFILES_DIR/default/skills/shared/batch-claude-skill/SKILL.md"
assert_file_exists "$PROFILES_DIR/default/skills/shared/batch-codex-skill/SKILL.md"
assert_symlink "$TEST_HOME/.claude/skills/batch-claude-skill" "$PROFILES_DIR/default/skills/shared/batch-claude-skill"
assert_symlink "$TEST_HOME/.codex/skills/batch-codex-skill" "$PROFILES_DIR/default/skills/shared/batch-codex-skill"

_TEST_NAME="ingest_orphan_skills: deduplicates across agents"
# Create same skill in both agent dirs
rm -f "$TEST_HOME/.claude/skills/duped-skill"
rm -f "$TEST_HOME/.codex/skills/duped-skill"
create_orphan_skill claude duped-skill "From Claude first"
create_orphan_skill codex duped-skill "From Codex second"
local output=$(_profile_ingest_orphan_skills 2>&1)
assert_file_exists "$PROFILES_DIR/default/skills/shared/duped-skill/SKILL.md"
# Only one should be ingested, second should be skipped
assert_contains "$output" "ingested duped-skill from claude"
assert_contains "$output" "skipped orphan duped-skill in codex"

# --- Apply-time ingestion tests ---

_TEST_NAME="apply_skills: ingests orphans during profile apply"
create_orphan_skill claude apply-time-skill "Created during session"
echo "default" > "$PROFILE_ACTIVE_FILE"
local output=$(_profile_apply_skills "default" 2>&1)
assert_file_exists "$PROFILES_DIR/default/skills/shared/apply-time-skill/SKILL.md"
assert_contains "$output" "ingested apply-time-skill"

# --- Claude PostToolUse hook script tests ---
# Use the actual hook script from the repo source (not the test dotfiles copy)
HOOK_DIR="${0:A:h}/../profiles/default/claude/hooks"
CODEX_HOOK_DIR="${0:A:h}/../profiles/default/codex/hooks"

_TEST_NAME="hook: ingests skill on SKILL.md write to claude dir"
# Ensure no leftover from earlier tests
rm -rf "$TEST_HOME/.claude/skills/hook-test-skill" "$PROFILES_DIR/default/skills/shared/hook-test-skill"
create_orphan_skill claude hook-test-skill "Hook created skill"
local hook_input='{"tool_name":"Write","tool_input":{"file_path":"'$TEST_HOME'/.claude/skills/hook-test-skill/SKILL.md","content":"test"}}'
local hook_output=$(echo "$hook_input" | HOME="$TEST_HOME" DOTFILES_DIR="$TEST_DOTFILES" bash "$HOOK_DIR/skill-auto-share.sh" 2>&1)
assert_file_exists "$PROFILES_DIR/default/skills/shared/hook-test-skill/SKILL.md"
# Hook creates cross-tmpdir relative symlinks; verify the link exists and resolves to a valid SKILL.md
if [[ -L "$TEST_HOME/.claude/skills/hook-test-skill" && -f "$TEST_HOME/.claude/skills/hook-test-skill/SKILL.md" ]]; then pass; else fail "symlink not created or does not resolve"; fi
assert_contains "$hook_output" "Auto-shared skill"

_TEST_NAME="hook: ignores non-SKILL.md writes"
local hook_input='{"tool_name":"Write","tool_input":{"file_path":"'$TEST_HOME'/some/other/file.md","content":"test"}}'
local hook_output=$(echo "$hook_input" | HOME="$TEST_HOME" DOTFILES_DIR="$TEST_DOTFILES" bash "$HOOK_DIR/skill-auto-share.sh" 2>&1)
assert_eq "" "$hook_output" "should produce no output for non-skill writes"

_TEST_NAME="hook: ignores writes to already-symlinked skill dirs"
# Create a symlinked skill dir (already managed)
mkdir -p "$TEST_HOME/.claude/skills"
mkdir -p "$PROFILES_DIR/default/skills/shared/managed-skill"
echo "---\nname: managed-skill\n---" > "$PROFILES_DIR/default/skills/shared/managed-skill/SKILL.md"
ln -sfn "$PROFILES_DIR/default/skills/shared/managed-skill" "$TEST_HOME/.claude/skills/managed-skill"
local hook_input='{"tool_name":"Write","tool_input":{"file_path":"'$TEST_HOME'/.claude/skills/managed-skill/SKILL.md","content":"test"}}'
local hook_output=$(echo "$hook_input" | HOME="$TEST_HOME" DOTFILES_DIR="$TEST_DOTFILES" bash "$HOOK_DIR/skill-auto-share.sh" 2>&1)
assert_eq "" "$hook_output" "should produce no output for managed skill"

# --- Codex hook script tests ---

_TEST_NAME="codex hook: ingests orphan skills at session end"
rm -rf "$TEST_HOME/.codex/skills/codex-session-skill" "$PROFILES_DIR/default/skills/shared/codex-session-skill"
create_orphan_skill codex codex-session-skill "Created in Codex session"
local hook_output=$(HOME="$TEST_HOME" DOTFILES_DIR="$TEST_DOTFILES" bash "$CODEX_HOOK_DIR/skill-auto-share.sh" 2>&1)
assert_file_exists "$PROFILES_DIR/default/skills/shared/codex-session-skill/SKILL.md"
if [[ -L "$TEST_HOME/.codex/skills/codex-session-skill" && -f "$TEST_HOME/.codex/skills/codex-session-skill/SKILL.md" ]]; then pass; else fail "symlink not created or does not resolve"; fi
assert_contains "$hook_output" "Auto-shared 1 skill"

_test_summary
