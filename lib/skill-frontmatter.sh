# Skill frontmatter extractors. Shell-agnostic (bash + zsh).
# Uses awk rather than sed: BSD sed rejects one-line `{ ... }` blocks,
# so awk keeps a single implementation portable across macOS and Linux.

skill_frontmatter_name() {
    awk '
        /^---$/ { in_fm = !in_fm; next }
        in_fm && /^name:/ {
            sub(/^name:[[:space:]]*/, "")
            print
            exit
        }
    ' "$1"
}

skill_frontmatter_desc() {
    awk '
        /^---$/ { in_fm = !in_fm; next }
        in_fm && /^description:/ {
            sub(/^description:[[:space:]]*>?[[:space:]]*/, "")
            if (length($0) > 0) { print; exit }
            if ((getline) > 0) {
                sub(/^[[:space:]]*/, "")
                print
            }
            exit
        }
    ' "$1"
}
