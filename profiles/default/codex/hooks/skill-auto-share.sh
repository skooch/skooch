#!/bin/bash
# Codex Stop hook: scan agent skill directories for orphan skills and
# ingest them into profiles/default/skills/shared/.
# Runs at session end since Codex lacks PostToolUse hooks.

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/projects/skooch}"
PROFILES_DIR="$DOTFILES_DIR/profiles"

# shellcheck source=../../../../lib/skill-frontmatter.sh
source "$DOTFILES_DIR/lib/skill-frontmatter.sh"

skill_exists_in_profile() {
    local skill_name="$1"
    for profile_dir in "$PROFILES_DIR"/*/; do
        [ -d "${profile_dir}skills/shared/$skill_name" ] && return 0
        [ -d "${profile_dir}skills/claude/$skill_name" ] && return 0
        [ -d "${profile_dir}skills/codex/$skill_name" ] && return 0
    done
    return 1
}

scaffold_openai_yaml() {
    local target="$1" skill_name="$2"
    [ -f "$target/agents/openai.yaml" ] && return 0

    local display_name="" short_desc=""
    if head -1 "$target/SKILL.md" | grep -q '^---'; then
        display_name=$(skill_frontmatter_name "$target/SKILL.md")
        short_desc=$(skill_frontmatter_desc "$target/SKILL.md")
    fi
    [ -z "$display_name" ] && display_name="$skill_name"
    [ -z "$short_desc" ] && short_desc="$skill_name skill"

    mkdir -p "$target/agents"
    cat > "$target/agents/openai.yaml" <<YAML
interface:
  display_name: "$display_name"
  short_description: "$short_desc"
  default_prompt: "Use \$$skill_name to run the $display_name workflow."
YAML
}

ingest_count=0

for agent_name in claude codex; do
    skills_dir="$HOME/.$agent_name/skills"
    [ -d "$skills_dir" ] || continue

    for entry in "$skills_dir"/*/; do
        [ -d "$entry" ] || continue
        [ -L "${entry%/}" ] && continue  # already a symlink

        skill_name=$(basename "$entry")
        [ "$skill_name" = ".system" ] && continue
        [ -f "$entry/SKILL.md" ] || continue

        skill_exists_in_profile "$skill_name" && continue

        # Ingest
        target="$PROFILES_DIR/default/skills/shared/$skill_name"
        mkdir -p "$PROFILES_DIR/default/skills/shared"
        mv "${entry%/}" "$target"

        scaffold_openai_yaml "$target" "$skill_name"

        # Symlink back (pure bash relpath to avoid sandbox restrictions)
        _relpath() {
            local t="$1" b="$2"
            t=$(cd "$t" 2>/dev/null && pwd -P) || t="$1"
            b=$(cd "$b" 2>/dev/null && pwd -P) || b="$2"
            local c="$b" r=""
            while [[ "${t#"$c"/}" == "$t" ]]; do
                c="${c%/*}"
                r="../$r"
            done
            echo "${r}${t#"$c"/}"
        }
        rel_path=$(_relpath "$target" "$skills_dir")
        ln -sfn "$rel_path" "$skills_dir/$skill_name"

        ingest_count=$((ingest_count + 1))
    done
done

if [ "$ingest_count" -gt 0 ]; then
    echo "Auto-shared $ingest_count skill(s) to profiles/default/skills/shared/"
fi

exit 0
