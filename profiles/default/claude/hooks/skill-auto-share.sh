#!/bin/bash
# PostToolUse hook: auto-ingest newly created skills to shared profile.
# Fires on Write tool. Detects SKILL.md writes to agent-native skill dirs
# (~/.claude/skills/, ~/.codex/skills/) and moves them to
# profiles/default/skills/shared/ with a symlink back.
#
# Input: JSON via stdin with tool_input.file_path

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')

[ -z "$FILE_PATH" ] && exit 0

# Only care about SKILL.md files
[[ "${FILE_PATH##*/}" == "SKILL.md" ]] || exit 0

# Resolve to absolute path
[[ "$FILE_PATH" == /* ]] || FILE_PATH="$PWD/$FILE_PATH"

# Match agent-native skill directories
AGENT_NAME=""
SKILL_DIR=""
case "$FILE_PATH" in
    "$HOME/.claude/skills/"*/SKILL.md)
        AGENT_NAME="claude"
        SKILL_DIR="${FILE_PATH%/SKILL.md}"
        ;;
    "$HOME/.codex/skills/"*/SKILL.md)
        AGENT_NAME="codex"
        SKILL_DIR="${FILE_PATH%/SKILL.md}"
        ;;
    *)
        exit 0  # Not in an agent skill directory
        ;;
esac

SKILL_NAME="${SKILL_DIR##*/}"

# Skip if the skill directory is already a symlink (managed by profile system)
[ -L "$SKILL_DIR" ] && exit 0

# Skip .system directory
[ "$SKILL_NAME" = ".system" ] && exit 0

# Source profile system for ingestion
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/projects/skooch}"
PROFILES_DIR="$DOTFILES_DIR/profiles"

# shellcheck source=../../../../lib/skill-frontmatter.sh
source "$DOTFILES_DIR/lib/skill-frontmatter.sh"

# Check if skill already exists in a profile
for profile_dir in "$PROFILES_DIR"/*/; do
    [ -d "${profile_dir}skills/shared/$SKILL_NAME" ] && exit 0
    [ -d "${profile_dir}skills/claude/$SKILL_NAME" ] && exit 0
    [ -d "${profile_dir}skills/codex/$SKILL_NAME" ] && exit 0
done

# Ingest: move to shared profile, scaffold openai.yaml, symlink back
TARGET="$PROFILES_DIR/default/skills/shared/$SKILL_NAME"
mkdir -p "$PROFILES_DIR/default/skills/shared"
mv "$SKILL_DIR" "$TARGET"

# Scaffold agents/openai.yaml if missing
if [ ! -f "$TARGET/agents/openai.yaml" ]; then
    DISPLAY_NAME=""
    SHORT_DESC=""
    if head -1 "$TARGET/SKILL.md" | grep -q '^---'; then
        DISPLAY_NAME=$(skill_frontmatter_name "$TARGET/SKILL.md")
        SHORT_DESC=$(skill_frontmatter_desc "$TARGET/SKILL.md")
    fi
    [ -z "$DISPLAY_NAME" ] && DISPLAY_NAME="$SKILL_NAME"
    [ -z "$SHORT_DESC" ] && SHORT_DESC="$SKILL_NAME skill"

    mkdir -p "$TARGET/agents"
    cat > "$TARGET/agents/openai.yaml" <<YAML
interface:
  display_name: "$DISPLAY_NAME"
  short_description: "$SHORT_DESC"
  default_prompt: "Use \$$SKILL_NAME to run the $DISPLAY_NAME workflow."
YAML
fi

# Create relative symlink back to agent skill dir
PARENT_DIR="${SKILL_DIR%/*}"
mkdir -p "$PARENT_DIR"
# Compute relative path without python3 (avoids sandbox restrictions)
_relpath() {
    local target="$1" base="$2"
    # Resolve to canonical paths
    target=$(cd "$target" 2>/dev/null && pwd -P) || target="$1"
    base=$(cd "$base" 2>/dev/null && pwd -P) || base="$2"
    local common="$base"
    local result=""
    while [[ "${target#"$common"/}" == "$target" ]]; do
        common="${common%/*}"
        result="../$result"
    done
    echo "${result}${target#"$common"/}"
}
REL_PATH=$(_relpath "$TARGET" "$PARENT_DIR")
ln -sfn "$REL_PATH" "$SKILL_DIR"

# Inform Claude via additionalContext
cat <<EOF
{"additionalContext": "Auto-shared skill '$SKILL_NAME' from $AGENT_NAME to profiles/default/skills/shared/. It is now available to all agents. The original location is now a symlink. To make this skill agent-specific instead, move it from shared/ to the appropriate agent audience directory (e.g. profiles/default/skills/claude/$SKILL_NAME)."}
EOF
exit 0
