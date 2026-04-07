# Profile system - detection helpers, readers, and utilities

# --- Claude "last profile wins" file list ---
# Relative paths under profiles/*/claude/ that use "last profile wins" symlink strategy.
# To add a new file: add an entry here. Apply, sync, diff, target_paths, and snapshots
# all derive from this list automatically.
_CLAUDE_LAST_WINS_PATHS=(
    CLAUDE.md
    system-prompt.md
    statusline.sh
    sync-plugins.sh
    read-once/hook.sh
)

# --- Codex "last profile wins" file list ---

_CODEX_LAST_WINS_PATHS=(
    rules/default.rules
)

# --- Relative symlink helpers ---

_profile_relpath() {
    # Compute relative path from directory $2 to file/dir $1.
    # Both arguments should be absolute paths. $2 must be an existing directory.
    local source="$1" from_dir="$2"

    # Normalize to absolute paths without following symlinks.
    # Using :a (not :A) avoids resolving symlinks, which is critical in
    # sandboxed environments (e.g. macOS app containers) where pwd -P
    # resolves target dirs to /private/var/... container paths while
    # source dirs stay at /Users/..., breaking relative path computation.
    local source_abs from_abs
    source_abs="${source:a}"
    from_abs="${from_dir:a}"

    # Split into path components
    local -a src_parts=(${(s:/:)source_abs})
    local -a from_parts=(${(s:/:)from_abs})

    # Find common prefix length
    local i=1
    while (( i <= $#src_parts && i <= $#from_parts )) && [[ "${src_parts[$i]}" == "${from_parts[$i]}" ]]; do
        (( i++ ))
    done

    # Build relative path: ../ for each remaining from_parts component, then src_parts remainder
    local result=""
    local j
    for (( j=i; j <= $#from_parts; j++ )); do
        result+="../"
    done
    for (( j=i; j <= $#src_parts; j++ )); do
        result+="${src_parts[$j]}"
        (( j < $#src_parts )) && result+="/"
    done

    echo "${result:-.}"
}

_profile_is_temp_path() {
    # Return 0 if the path is under a known temporary directory.
    local abs="${1:a}"
    case "$abs" in
        /var/folders/*/T/*|/tmp/*|/private/tmp/*) return 0 ;;
    esac
    [[ -n "${TMPDIR:-}" && "$abs" == "${TMPDIR:a}"/* ]] && return 0
    return 1
}

_profile_ln_s() {
    # Create a relative file symlink (ln -sf equivalent).
    # Usage: _profile_ln_s <source_absolute> <target>
    local source="$1" target="$2"
    if _profile_is_temp_path "$source" && ! _profile_is_temp_path "$target"; then
        echo "Warning: refusing to symlink to temp path: $source" >&2
        return 1
    fi
    local rel
    rel=$(_profile_relpath "$source" "$(dirname "$target")")
    ln -sf "$rel" "$target"
}

_profile_ln_sn() {
    # Create a relative directory symlink (ln -sfn equivalent).
    # Usage: _profile_ln_sn <source_absolute> <target>
    local source="$1" target="$2"
    if _profile_is_temp_path "$source" && ! _profile_is_temp_path "$target"; then
        echo "Warning: refusing to symlink to temp path: $source" >&2
        return 1
    fi
    local rel
    rel=$(_profile_relpath "$source" "$(dirname "$target")")
    ln -sfn "$rel" "$target"
}

_profile_symlink_matches() {
    # Check whether symlink at $1 ultimately points to the same file as $2.
    # Handles both absolute and relative symlink targets.
    # Uses :a to normalize without following symlinks (sandbox-safe).
    local symlink="$1" expected_source="$2"
    [[ -L "$symlink" ]] || return 1

    local link_target
    link_target=$(readlink "$symlink")

    # Resolve link target to normalized absolute path
    if [[ "$link_target" != /* ]]; then
        link_target="$(dirname "$symlink")/$link_target"
    fi
    link_target="${link_target:a}"

    # Resolve expected source to normalized absolute path
    local expected_abs="${expected_source:a}"

    [[ "$link_target" == "$expected_abs" ]]
}

# --- Shared profile-tree helpers ---

_profile_collect_domain_dirs() {
    local profiles="$1" domain="$2"
    local -a dirs=()

    [[ -d "$PROFILES_DIR/default/$domain" ]] && dirs+=("$PROFILES_DIR/default/$domain")
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        [[ -d "$PROFILES_DIR/$p/$domain" ]] && dirs+=("$PROFILES_DIR/$p/$domain")
    done

    printf '%s\n' "${dirs[@]}"
}

_profile_collect_domain_file_sources() {
    local profiles="$1" domain="$2" relative_path="$3"
    local domain_dir
    while IFS= read -r domain_dir; do
        [[ -n "$domain_dir" && -f "$domain_dir/$relative_path" ]] && echo "$domain_dir/$relative_path"
    done < <(_profile_collect_domain_dirs "$profiles" "$domain")
}

_profile_profile_source_label() {
    local profiles="$1" domain="$2" relative_path="$3"
    local -a labels=()
    local label=""

    [[ -f "$PROFILES_DIR/default/$domain/$relative_path" ]] && labels+=("default")
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        [[ -f "$PROFILES_DIR/$p/$domain/$relative_path" ]] && labels+=("$p")
    done

    for p in "${labels[@]}"; do
        if [[ -n "$label" ]]; then
            label+=" + $p"
        else
            label="$p"
        fi
    done

    [[ -n "$label" ]] && echo "$label"
}

_profile_resolve_last_wins_source() {
    local profiles="$1" domain="$2" relative_path="$3"
    local source=""
    local candidate=""
    while IFS= read -r candidate; do
        [[ -n "$candidate" ]] && source="$candidate"
    done < <(_profile_collect_domain_file_sources "$profiles" "$domain" "$relative_path")
    [[ -n "$source" ]] && echo "$source"
}

_profile_merge_json_files() {
    local output_file="$1"
    shift
    local -a source_files=("$@")

    [[ ${#source_files[@]} -eq 0 ]] && return 1
    if [[ ${#source_files[@]} -eq 1 ]]; then
        cp "${source_files[1]}" "$output_file"
    else
        jq -s 'reduce .[] as $item ({}; . * $item)' "${source_files[@]}" > "$output_file"
    fi
}

_profile_python_bin() {
    if typeset -f _skooch_python3_bin >/dev/null 2>&1; then
        _skooch_python3_bin
        return $?
    fi

    local python_helpers="$HOME/projects/skooch/lib/shell/python.sh"
    if [[ -f "$python_helpers" ]]; then
        source "$python_helpers"
        if typeset -f _skooch_python3_bin >/dev/null 2>&1; then
            _skooch_python3_bin
            return $?
        fi
    fi

    if [[ -n "${SKOOCH_PYTHON3_BIN:-}" && -x "${SKOOCH_PYTHON3_BIN}" ]]; then
        printf '%s' "$SKOOCH_PYTHON3_BIN"
        return 0
    fi

    command -v python3 2>/dev/null
}

_profile_merge_toml_files() {
    local output_file="$1"
    shift
    local -a source_files=("$@")
    local python_bin=""

    [[ ${#source_files[@]} -eq 0 ]] && return 1
    if [[ ${#source_files[@]} -eq 1 ]]; then
        cp "${source_files[1]}" "$output_file"
    else
        python_bin="$(_profile_python_bin 2>/dev/null)" || python_bin=""
        [[ -n "$python_bin" ]] || python_bin="${SKOOCH_PYTHON3_BIN:-python3}"
        "$python_bin" "$_PROFILE_LIB_DIR/toml_merge.py" "$output_file" "${source_files[@]}"
    fi
}

_profile_merge_structured_files() {
    local format="$1" output_file="$2"
    shift 2

    case "$format" in
        json) _profile_merge_json_files "$output_file" "$@" ;;
        toml) _profile_merge_toml_files "$output_file" "$@" ;;
        *)
            echo "Unsupported structured config format: $format" >&2
            return 1
            ;;
    esac
}

_profile_replace_file() {
    local source_file="$1" target_file="$2"
    local tmpfile
    tmpfile=$(mktemp)
    mkdir -p "$(dirname "$target_file")"
    cp "$source_file" "$tmpfile"
    mv "$tmpfile" "$target_file"
}

_profile_apply_structured_profile_config() {
    local label="$1" profiles="$2" domain="$3" relative_path="$4" target_root="$5" format="$6"
    local -a source_files=()
    local source_file=""

    while IFS= read -r source_file; do
        [[ -n "$source_file" ]] && source_files+=("$source_file")
    done < <(_profile_collect_domain_file_sources "$profiles" "$domain" "$relative_path")
    [[ ${#source_files[@]} -eq 0 ]] && return 0

    local target_file="$target_root/$relative_path"
    mkdir -p "$(dirname "$target_file")"

    if [[ ${#source_files[@]} -eq 1 ]]; then
        _profile_ln_s "${source_files[1]}" "$target_file"
    else
        local merged_file
        merged_file=$(mktemp)
        _profile_merge_structured_files "$format" "$merged_file" "${source_files[@]}" || {
            rm -f "$merged_file"
            return 1
        }
        mv "$merged_file" "$target_file"
    fi

    local source_label=$(_profile_profile_source_label "$profiles" "$domain" "$relative_path")
    echo "Applying $label: $source_label"
}

_profile_sync_structured_profile_config() {
    local label="$1" profiles="$2" domain="$3" relative_path="$4" target_root="$5" format="$6"
    local -a source_files=()
    local source_file=""

    while IFS= read -r source_file; do
        [[ -n "$source_file" ]] && source_files+=("$source_file")
    done < <(_profile_collect_domain_file_sources "$profiles" "$domain" "$relative_path")
    [[ ${#source_files[@]} -eq 0 ]] && return 0

    local target_file="$target_root/$relative_path"
    mkdir -p "$(dirname "$target_file")"

    if [[ ${#source_files[@]} -eq 1 ]]; then
        if [[ ! -e "$target_file" && ! -L "$target_file" ]]; then
            _profile_ln_s "${source_files[1]}" "$target_file"
            echo "  $label: symlinked -> ${source_files[1]:t}"
            return 0
        fi
        if _profile_symlink_matches "$target_file" "${source_files[1]}"; then
            echo "  $label: in sync (symlinked)"
        elif [[ -L "$target_file" ]]; then
            _profile_ln_s "${source_files[1]}" "$target_file"
            echo "  $label: symlinked -> ${source_files[1]:t}"
        else
            _profile_sync_config "$label" "$target_file" "${source_files[1]}" "${source_files[1]}"
            return $?
        fi
        return 0
    fi

    local expected_file
    expected_file=$(mktemp)
    _profile_merge_structured_files "$format" "$expected_file" "${source_files[@]}" || {
        rm -f "$expected_file"
        return 1
    }
    _profile_sync_config "$label" "$target_file" "$expected_file" "${source_files[@]}"
    local result=$?
    rm -f "$expected_file"
    return $result
}

_profile_collect_union_file_sources() {
    local profiles="$1" domain="$2" relative_dir="$3" glob_pattern="$4"
    local -A source_map=()
    local domain_dir=""
    local matched_file=""

    while IFS= read -r domain_dir; do
        [[ -z "$domain_dir" ]] && continue
        for matched_file in "$domain_dir/$relative_dir"/$~glob_pattern(N-.); do
            source_map[${matched_file:t}]="$matched_file"
        done
    done < <(_profile_collect_domain_dirs "$profiles" "$domain")

    local basename=""
    for basename in ${(ok)source_map}; do
        printf '%s\t%s\n' "$basename" "$source_map[$basename]"
    done
}

_profile_collect_union_dir_sources() {
    local profiles="$1" domain="$2" relative_dir="$3"
    local -A source_map=()
    local domain_dir=""
    local matched_dir=""

    while IFS= read -r domain_dir; do
        [[ -z "$domain_dir" ]] && continue
        for matched_dir in "$domain_dir/$relative_dir"/*(N/); do
            source_map[${matched_dir:t}]="$matched_dir"
        done
    done < <(_profile_collect_domain_dirs "$profiles" "$domain")

    local dirname=""
    for dirname in ${(ok)source_map}; do
        printf '%s\t%s\n' "$dirname" "$source_map[$dirname]"
    done
}

_profile_link_last_wins_paths() {
    local profiles="$1" domain="$2" target_root="$3" mode="${4:-apply}"
    shift 4

    local relative_path=""
    for relative_path in "$@"; do
        local source=$(_profile_resolve_last_wins_source "$profiles" "$domain" "$relative_path")
        [[ -z "$source" ]] && continue

        local target_file="$target_root/$relative_path"
        mkdir -p "$(dirname "$target_file")"
        if [[ "$mode" == "sync" ]] && _profile_symlink_matches "$target_file" "$source"; then
            echo "  $relative_path: in sync (symlinked)"
        else
            _profile_ln_s "$source" "$target_file"
            echo "  $relative_path: symlinked"
        fi
    done
}

_profile_link_union_file_collection() {
    local profiles="$1" domain="$2" relative_dir="$3" glob_pattern="$4" target_root="$5" mode="${6:-apply}" label="$7"
    local -a linked_names=()
    local collection_changed=false
    local basename="" source_file=""

    while IFS=$'\t' read -r basename source_file; do
        [[ -z "$basename" || -z "$source_file" ]] && continue
        linked_names+=("$basename")
        local target_file="$target_root/$relative_dir/$basename"
        mkdir -p "$(dirname "$target_file")"
        if [[ "$mode" == "sync" ]] && _profile_symlink_matches "$target_file" "$source_file"; then
            continue
        fi
        _profile_ln_s "$source_file" "$target_file"
        collection_changed=true
    done < <(_profile_collect_union_file_sources "$profiles" "$domain" "$relative_dir" "$glob_pattern")

    [[ ${#linked_names[@]} -eq 0 ]] && return 0
    if [[ "$mode" == "sync" ]]; then
        if [[ "$collection_changed" == true ]]; then
            echo "  $label: updated (${(j:, :)linked_names})"
        else
            echo "  $label: in sync (${(j:, :)linked_names})"
        fi
    else
        echo "  $label: ${(j:, :)linked_names}"
    fi
}

_profile_link_union_dir_collection() {
    local profiles="$1" domain="$2" relative_dir="$3" target_root="$4" mode="${5:-apply}" label="$6"
    local -a linked_names=()
    local -a skipped_names=()
    local collection_changed=false
    local dirname="" source_dir=""

    while IFS=$'\t' read -r dirname source_dir; do
        [[ -z "$dirname" || -z "$source_dir" ]] && continue
        linked_names+=("$dirname")
        local target_dir="$target_root/$relative_dir/$dirname"
        mkdir -p "$(dirname "$target_dir")"
        if [[ -d "$target_dir" && ! -L "$target_dir" ]]; then
            if ! rmdir "$target_dir" 2>/dev/null; then
                skipped_names+=("$dirname")
                continue
            fi
        fi
        if [[ "$mode" == "sync" ]] && _profile_symlink_matches "$target_dir" "$source_dir"; then
            continue
        fi
        _profile_ln_sn "$source_dir" "$target_dir"
        collection_changed=true
    done < <(_profile_collect_union_dir_sources "$profiles" "$domain" "$relative_dir")

    [[ ${#linked_names[@]} -eq 0 && ${#skipped_names[@]} -eq 0 ]] && return 0
    if [[ "$mode" == "sync" ]]; then
        if [[ "$collection_changed" == true ]]; then
            echo "  $label: updated (${(j:, :)linked_names})"
        else
            echo "  $label: in sync (${(j:, :)linked_names})"
        fi
    else
        echo "  $label: ${(j:, :)linked_names}"
    fi
    if [[ ${#skipped_names[@]} -gt 0 ]]; then
        echo "  $label: skipped conflicting directories (${(j:, :)skipped_names})"
    fi
}

_profile_ensure_derived_symlink() {
    local label="$1" source_path="$2" target_path="$3" mode="${4:-apply}"

    [[ ! -e "$source_path" && ! -L "$source_path" ]] && return 0

    mkdir -p "$(dirname "$target_path")"
    if [[ "$mode" == "sync" ]] && _profile_symlink_matches "$target_path" "$source_path"; then
        echo "  $label: in sync (symlinked)"
        return 0
    fi

    if [[ -d "$target_path" && ! -L "$target_path" ]]; then
        if ! rmdir "$target_path" 2>/dev/null; then
            echo "  $label: skipped conflicting directory"
            return 0
        fi
    fi

    _profile_ln_sn "$source_path" "$target_path"
    echo "  $label: symlinked"
}

# Resolve "last profile wins" source for a claude path.
# Prints the winning source path, or nothing if no profile has the file.
_profile_claude_resolve_source() {
    local profiles="$1" relative_path="$2"
    _profile_resolve_last_wins_source "$profiles" "claude" "$relative_path"
}

_profile_codex_resolve_source() {
    local profiles="$1" relative_path="$2"
    _profile_resolve_last_wins_source "$profiles" "codex" "$relative_path"
}

# Symlink all "last profile wins" claude paths.
# In sync mode, skips files already correctly symlinked and reports status.
_profile_claude_link_files() {
    local profiles="$1" mode="${2:-apply}"
    _profile_link_last_wins_paths "$profiles" "claude" "$HOME/.claude" "$mode" "${_CLAUDE_LAST_WINS_PATHS[@]}"
}

# --- Detection helpers ---

_profile_vscode_instances() {
    # Outputs "label|user_dir|cli" for each found VS Code installation
    local -a dirs labels cli_cmds cli_apps

    if [[ "$IS_MACOS" == true ]]; then
        dirs=("$HOME/Library/Application Support/Code - Insiders/User"
              "$HOME/Library/Application Support/Code/User")
        cli_apps=("/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/bin/code"
                  "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code")
    else
        dirs=("$HOME/.config/Code - Insiders/User"
              "$HOME/.config/Code/User")
        cli_apps=("" "")
    fi
    labels=("Code Insiders" "Code")
    cli_cmds=(code-insiders code)

    for i in 1 2; do
        if [[ -d "${dirs[$i]}" ]]; then
            local cli=""
            if command -v "${cli_cmds[$i]}" &>/dev/null; then
                cli="${cli_cmds[$i]}"
            elif [[ -n "${cli_apps[$i]}" && -x "${cli_apps[$i]}" ]]; then
                cli="${cli_apps[$i]}"
            fi
            [[ -n "$cli" ]] && echo "${labels[$i]}|${dirs[$i]}|${cli}"
        fi
    done
}

_profile_find_vscode() {
    local first
    first=$(_profile_vscode_instances | head -1)
    [[ -z "$first" ]] && return 1
    echo "$first" | cut -d'|' -f2
}

_profile_find_vscode_cli() {
    local first
    first=$(_profile_vscode_instances | head -1)
    [[ -z "$first" ]] && return 1
    echo "$first" | cut -d'|' -f3
}

_profile_active() {
    if [[ -f "$PROFILE_ACTIVE_FILE" ]]; then
        cat "$PROFILE_ACTIVE_FILE"
    fi
}

# --- Read expected packages/extensions from profile Brewfiles/extensions.txt ---

_profile_read_brew_packages() {
    local -a files=("$@")
    for f in "${files[@]}"; do
        [[ -f "$f" ]] || continue
        local skip=false
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%%#*}"  # strip comments
            # Track OS-conditional blocks
            if [[ "$line" =~ ^[[:space:]]*if\ +OS\.mac\? ]]; then
                [[ "$IS_MACOS" != true ]] && skip=true
                continue
            elif [[ "$line" =~ ^[[:space:]]*if\ +OS\.linux\? ]]; then
                [[ "$IS_LINUX" != true ]] && skip=true
                continue
            elif [[ "$line" =~ ^[[:space:]]*end[[:space:]]*$ ]]; then
                skip=false
                continue
            fi
            [[ "$skip" == true ]] && continue
            if [[ "$line" =~ ^[[:space:]]*brew\ +\"([^\"]+)\" ]]; then
                echo "brew:${match[1]}"
            elif [[ "$line" =~ ^[[:space:]]*cask\ +\"([^\"]+)\" ]]; then
                echo "cask:${match[1]}"
            elif [[ "$line" =~ ^[[:space:]]*tap\ +\"([^\"]+)\" ]]; then
                echo "tap:${match[1]}"
            fi
        done < "$f"
    done | sort -u
}

_profile_read_all_brew_packages() {
    local -a all_brewfiles=()
    for dir in "$PROFILES_DIR"/*/; do
        [[ -f "$dir/Brewfile" ]] && all_brewfiles+=("$dir/Brewfile")
    done
    _profile_read_brew_packages "${all_brewfiles[@]}"
}

_profile_read_extensions() {
    local -a files=("$@")
    for f in "${files[@]}"; do
        [[ -f "$f" ]] || continue
        while IFS= read -r ext || [[ -n "$ext" ]]; do
            ext="${ext%%#*}"
            ext="${ext// /}"
            [[ -n "$ext" ]] && echo "$ext"
        done < "$f"
    done | sort -u
}

# --- Collect profile dirs for active profiles ---

_profile_collect_dirs() {
    local profiles="$1"
    echo "$PROFILES_DIR/default"
    for p in ${=profiles}; do
        [[ "$p" != "default" ]] && echo "$PROFILES_DIR/$p"
    done
}

# --- File list for snapshots ---

_profile_snapshot_files() {
    # Used by snapshot, drift check, and no-op detection
    local dir="$1"
    for f in "$dir/Brewfile" "$dir/vscode/extensions.txt" \
             "$dir/vscode/settings.json" "$dir/vscode/keybindings.json" \
             "$dir/iterm/profile.json" \
             "$dir/git/config" "$dir/mise/config.toml" \
             "$dir/claude/settings.json" \
             "$dir/codex/config.toml" "$dir/codex/hooks.json" \
             "$dir/tmux/tmux.conf"; do
        echo "$f"
    done
    # Claude "last profile wins" paths
    for relative_path in "${_CLAUDE_LAST_WINS_PATHS[@]}"; do
        echo "$dir/claude/$relative_path"
    done
    # Codex "last profile wins" paths
    for relative_path in "${_CODEX_LAST_WINS_PATHS[@]}"; do
        echo "$dir/codex/$relative_path"
    done
    # Claude hooks (*.sh scripts only)
    for f in "$dir"/claude/hooks/*.sh(N); do
        echo "$f"
    done
    # Skills (audience-routed: skills/{shared,claude,codex,...}/<skill>/SKILL.md)
    for f in "$dir"/skills/*/*/SKILL.md(N); do
        echo "$f"
    done
    # Claude commands (*.md files)
    for f in "$dir"/claude/commands/*.md(N); do
        echo "$f"
    done
    # Codex hooks (durable file union)
    for f in "$dir"/codex/hooks/*(N-.); do
        echo "$f"
    done
    # Codex agents (*.toml files)
    for f in "$dir"/codex/agents/*.toml(N); do
        echo "$f"
    done
}

# --- Managed files tracking ---

_profile_is_managed() {
    local managed_path="$1"
    [[ -f "$PROFILE_MANAGED_FILE" ]] && grep -qFx "$managed_path" "$PROFILE_MANAGED_FILE" 2>/dev/null
}

_profile_write_managed() {
    # Args: list of absolute paths that were written by profile switch
    mkdir -p "$PROFILE_STATE_DIR"
    printf '%s\n' "$@" > "$PROFILE_MANAGED_FILE"
}

# --- Collect target paths that a switch would write ---

_profile_target_paths() {
    local profiles="$1"
    local -a paths=()

    # Git
    local has_git=false
    [[ -f "$PROFILES_DIR/default/git/config" ]] && has_git=true
    for p in ${=profiles}; do
        [[ -f "$PROFILES_DIR/$p/git/config" ]] && has_git=true
    done
    [[ "$has_git" == "true" ]] && paths+=("$HOME/.gitconfig")

    # Mise
    local has_mise=false
    [[ -f "$PROFILES_DIR/default/mise/config.toml" ]] && has_mise=true
    for p in ${=profiles}; do
        [[ -f "$PROFILES_DIR/$p/mise/config.toml" ]] && has_mise=true
    done
    [[ "$has_mise" == "true" ]] && paths+=("$HOME/.config/mise/config.toml")

    # VSCode
    local has_vscode=false
    [[ -d "$PROFILES_DIR/default/vscode" ]] && has_vscode=true
    for p in ${=profiles}; do
        [[ -d "$PROFILES_DIR/$p/vscode" ]] && has_vscode=true
    done
    if [[ "$has_vscode" == "true" ]]; then
        while IFS='|' read -r _label vscode_user_dir _cli; do
            [[ -z "$_label" ]] && continue
            paths+=("$vscode_user_dir/settings.json")
            paths+=("$vscode_user_dir/keybindings.json")
        done < <(_profile_vscode_instances 2>/dev/null)
    fi

    # Claude Code
    local has_claude=false
    [[ -f "$PROFILES_DIR/default/claude/settings.json" ]] && has_claude=true
    for p in ${=profiles}; do
        [[ -f "$PROFILES_DIR/$p/claude/settings.json" ]] && has_claude=true
    done
    [[ "$has_claude" == "true" ]] && paths+=("$HOME/.claude/settings.json")

    # Claude "last profile wins" paths (CLAUDE.md, system-prompt.md, statusline.sh, etc.)
    for relative_path in "${_CLAUDE_LAST_WINS_PATHS[@]}"; do
        local source=$(_profile_claude_resolve_source "$profiles" "$relative_path")
        [[ -n "$source" ]] && paths+=("$HOME/.claude/$relative_path")
    done

    # Claude hooks (union of *.sh scripts across profiles)
    local basename="" source_file=""
    while IFS=$'\t' read -r basename source_file; do
        [[ -n "$basename" ]] && paths+=("$HOME/.claude/hooks/$basename")
    done < <(_profile_collect_union_file_sources "$profiles" "claude" "hooks" "*.sh")

    # Skills (audience-routed across agents)
    local -A _tp_agent_roots=([claude]="$HOME/.claude" [codex]="$HOME/.codex")
    local -a _tp_all_agents=(${(k)_tp_agent_roots})
    local _tp_profile=""
    for _tp_profile in default ${=profiles}; do
        local _tp_skills_dir="$PROFILES_DIR/$_tp_profile/skills"
        [[ -d "$_tp_skills_dir" ]] || continue
        local _tp_audience_dir=""
        for _tp_audience_dir in "$_tp_skills_dir"/*(N/); do
            local _tp_audience="${_tp_audience_dir:t}"
            local -a _tp_targets=()
            if [[ "$_tp_audience" == "shared" ]]; then
                _tp_targets=("${_tp_all_agents[@]}")
            elif (( ${+_tp_agent_roots[$_tp_audience]} )); then
                _tp_targets=("$_tp_audience")
            else
                continue
            fi
            local _tp_skill_dir=""
            for _tp_skill_dir in "$_tp_audience_dir"/*(N/); do
                local _tp_skill_name="${_tp_skill_dir:t}"
                [[ "$_tp_skill_name" == .system ]] && continue
                local _tp_target_agent=""
                for _tp_target_agent in "${_tp_targets[@]}"; do
                    paths+=("${_tp_agent_roots[$_tp_target_agent]}/skills/$_tp_skill_name")
                done
            done
        done
    done

    # Claude commands (union of *.md files across profiles)
    while IFS=$'\t' read -r basename source_file; do
        [[ -n "$basename" ]] && paths+=("$HOME/.claude/commands/$basename")
    done < <(_profile_collect_union_file_sources "$profiles" "claude" "commands" "*.md")

    # Codex config
    local has_codex_config=false
    [[ -f "$PROFILES_DIR/default/codex/config.toml" ]] && has_codex_config=true
    for p in ${=profiles}; do
        [[ -f "$PROFILES_DIR/$p/codex/config.toml" ]] && has_codex_config=true
    done
    [[ "$has_codex_config" == "true" ]] && paths+=("$HOME/.codex/config.toml")

    local has_codex_hooks_json=false
    [[ -f "$PROFILES_DIR/default/codex/hooks.json" ]] && has_codex_hooks_json=true
    for p in ${=profiles}; do
        [[ -f "$PROFILES_DIR/$p/codex/hooks.json" ]] && has_codex_hooks_json=true
    done
    [[ "$has_codex_hooks_json" == "true" ]] && paths+=("$HOME/.codex/hooks.json")

    for relative_path in "${_CODEX_LAST_WINS_PATHS[@]}"; do
        local source=$(_profile_codex_resolve_source "$profiles" "$relative_path")
        [[ -n "$source" ]] && paths+=("$HOME/.codex/$relative_path")
    done

    while IFS=$'\t' read -r basename source_file; do
        [[ -n "$basename" ]] && paths+=("$HOME/.codex/hooks/$basename")
    done < <(_profile_collect_union_file_sources "$profiles" "codex" "hooks" "*")

    while IFS=$'\t' read -r basename source_file; do
        [[ -n "$basename" ]] && paths+=("$HOME/.codex/agents/$basename")
    done < <(_profile_collect_union_file_sources "$profiles" "codex" "agents" "*.toml")

    if [[ -n "$(_profile_claude_resolve_source "$profiles" "CLAUDE.md")" ]]; then
        paths+=("$HOME/.codex/AGENTS.md")
    fi

    # Tmux
    local has_tmux=false
    [[ -f "$PROFILES_DIR/default/tmux/tmux.conf" ]] && has_tmux=true
    for p in ${=profiles}; do
        [[ -f "$PROFILES_DIR/$p/tmux/tmux.conf" ]] && has_tmux=true
    done
    [[ "$has_tmux" == "true" ]] && paths+=("$HOME/.tmux.conf")

    # iTerm (macOS only)
    if [[ "$IS_MACOS" == true ]]; then
        local dynamic_dir="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
        local has_iterm=false
        [[ -f "$PROFILES_DIR/default/iterm/profile.json" ]] && has_iterm=true
        for p in ${=profiles}; do
            [[ -f "$PROFILES_DIR/$p/iterm/profile.json" ]] && has_iterm=true
        done
        [[ "$has_iterm" == "true" && -d "$HOME/Library/Application Support/iTerm2" ]] && \
            paths+=("$dynamic_dir/dotfiles.json")
    fi

    printf '%s\n' "${paths[@]}"
}

# --- Overwrite detection ---

_profile_check_overwrite() {
    local profiles="$1"
    local -a warnings=()

    local -a targets=()
    while IFS= read -r target_path; do
        [[ -n "$target_path" ]] && targets+=("$target_path")
    done < <(_profile_target_paths "$profiles")

    for target in "${targets[@]}"; do
        if [[ -f "$target" ]] && ! _profile_is_managed "$target"; then
            warnings+=("$target")
        fi
    done

    if [[ ${#warnings[@]} -gt 0 ]]; then
        echo ""
        echo "The following unmanaged files will be overwritten:"
        for w in "${warnings[@]}"; do
            echo "  - $w"
        done
        printf "Continue? [y/N] "
        local answer
        read -r answer
        if [[ "$answer" != [yY] && "$answer" != [yY][eE][sS] ]]; then
            echo "Aborted."
            return 1
        fi
    fi
    return 0
}

# --- Dedup auto-added lines in shell dotfiles ---

_profile_dedup_dotfiles() {
    local -a files=(
        "$DOTFILES_DIR/.zshenv"
        "$DOTFILES_DIR/.zshrc"
        "$DOTFILES_DIR/.zprofile"
    )

    for file in "${files[@]}"; do
        [[ -f "$file" ]] || continue

        local -A seen=()
        local -a output=()
        local removed=0

        while IFS= read -r line; do
            # Always keep blank lines and comments
            if [[ -z "$line" || "$line" =~ '^[[:space:]]*(#|$)' ]]; then
                output+=("$line")
                continue
            fi

            # Always keep indented lines and shell structure keywords
            if [[ "$line" =~ '^[[:space:]]' || "$line" =~ '^(if|elif|else|fi|for|while|until|do|done|case|esac|then|\{|\})([[:space:]]|$)' ]]; then
                output+=("$line")
                continue
            fi

            # Skip exact duplicate non-trivial lines
            if [[ -n "${seen[$line]+x}" ]]; then
                (( removed++ )) || true
                continue
            fi

            seen[$line]=1
            output+=("$line")
        done < "$file"

        if [[ $removed -gt 0 ]]; then
            printf '%s\n' "${output[@]}" > "$file"
            echo "Removed $removed duplicate line(s) from $(basename "$file")"
        fi
    done
}

# --- VSCode conflict detection ---

_profile_detect_vscode_conflicts() {
    local profiles="$1"
    local -a settings_files=()
    local -a profile_names=()

    local default_settings="$PROFILES_DIR/default/vscode/settings.json"
    if [[ -f "$default_settings" ]]; then
        settings_files+=("$default_settings")
        profile_names+=("default")
    fi

    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        local pf="$PROFILES_DIR/$p/vscode/settings.json"
        if [[ -f "$pf" ]]; then
            settings_files+=("$pf")
            profile_names+=("$p")
        fi
    done

    [[ ${#settings_files[@]} -lt 2 ]] && return 0

    local i j
    for (( i=0; i < ${#settings_files[@]}; i++ )); do
        for (( j=i+1; j < ${#settings_files[@]}; j++ )); do
            local file_a="${settings_files[$((i+1))]}"
            local file_b="${settings_files[$((j+1))]}"
            local name_a="${profile_names[$((i+1))]}"
            local name_b="${profile_names[$((j+1))]}"

            local common_keys
            common_keys=$(jq -r 'keys[]' "$file_a" "$file_b" 2>/dev/null | sort | uniq -d)

            for key in ${(f)common_keys}; do
                [[ -z "$key" ]] && continue
                local val_a val_b
                val_a=$(jq -c --arg k "$key" '.[$k]' "$file_a" 2>/dev/null)
                val_b=$(jq -c --arg k "$key" '.[$k]' "$file_b" 2>/dev/null)
                if [[ "$val_a" != "$val_b" ]]; then
                    echo "  VSCode conflict: \"$key\" set by both $name_a ($val_a) and $name_b ($val_b) -- $name_b wins"
                fi
            done
        done
    done
}

# --- Per-item sync prompt ---

_profile_sync_skip_key() {
    local scope="$1" item="$2"
    printf '%s\t%s\n' "$scope" "$item"
}

_profile_sync_skip_contains() {
    local scope="$1" item="$2"
    [[ -f "$PROFILE_SYNC_SKIPS_FILE" ]] || return 1

    local key=$(_profile_sync_skip_key "$scope" "$item")
    local line=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" == "$key" ]] && return 0
    done < "$PROFILE_SYNC_SKIPS_FILE"
    return 1
}

_profile_sync_skip_remember() {
    local scope="$1" item="$2"
    _profile_sync_skip_contains "$scope" "$item" && return 0

    mkdir -p "$PROFILE_STATE_DIR"
    _profile_sync_skip_key "$scope" "$item" >> "$PROFILE_SYNC_SKIPS_FILE"
}

_profile_sync_skip_forget() {
    local scope="$1" item="$2"
    [[ -f "$PROFILE_SYNC_SKIPS_FILE" ]] || return 0

    local key=$(_profile_sync_skip_key "$scope" "$item")
    local tmpfile
    tmpfile=$(mktemp)

    local line=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" == "$key" ]] && continue
        echo "$line"
    done < "$PROFILE_SYNC_SKIPS_FILE" > "$tmpfile"

    mv "$tmpfile" "$PROFILE_SYNC_SKIPS_FILE"
}

_profile_prompt_item() {
    local scope="" label="" direction=""
    if [[ $# -ge 3 ]]; then
        scope="$1"
        label="$2"
        direction="$3"
    else
        label="$1"
        direction="$2"
    fi

    if [[ "$direction" == "not_installed" ]]; then
        echo "  $label — not installed" >&2
        while true; do
            printf "    [I]nstall / [R]emove from profile / [S]kip? [I] " >&2
            local answer
            read -r answer
            case "${answer:-I}" in
                [iI]) echo "install"; return ;;
                [rR]) echo "remove"; return ;;
                [sS]) echo "skip"; return ;;
                *)    echo "    Invalid input, try again." >&2 ;;
            esac
        done
    elif [[ "$direction" == "not_in_profile" ]]; then
        if [[ -n "$scope" ]] && _profile_sync_skip_contains "$scope" "$label"; then
            echo "skip"
            return
        fi
        echo "  $label — not in profile" >&2
        while true; do
            printf "    [A]dd to profile / [U]ninstall / [S]kip? [A] " >&2
            local answer
            read -r answer
            case "${answer:-A}" in
                [aA])
                    [[ -n "$scope" ]] && _profile_sync_skip_forget "$scope" "$label"
                    echo "add"
                    return
                    ;;
                [uU])
                    [[ -n "$scope" ]] && _profile_sync_skip_forget "$scope" "$label"
                    echo "uninstall"
                    return
                    ;;
                [sS])
                    [[ -n "$scope" ]] && _profile_sync_skip_remember "$scope" "$label"
                    echo "skip"
                    return
                    ;;
                *)    echo "    Invalid input, try again." >&2 ;;
            esac
        done
    fi
}

# --- Line removal helpers ---

_profile_remove_line() {
    local file="$1" pattern="$2"
    local tmpfile=$(mktemp)
    local removed=false
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$removed" == false ]] && [[ "$line" =~ $pattern ]]; then
            removed=true
            continue
        fi
        echo "$line"
    done < "$file" > "$tmpfile"
    mv "$tmpfile" "$file"
}

_profile_escape_regex() {
    local str="$1"
    # Escape POSIX ERE metacharacters for use in zsh =~ patterns
    str="${str//\\/\\\\}"
    str="${str//./\\.}"
    str="${str//\*/\\*}"
    str="${str//+/\\+}"
    str="${str//\?/\\?}"
    str="${str//\^/\\^}"
    str="${str//\$/\\$}"
    str="${str//\(/\\(}"
    str="${str//\)/\\)}"
    str="${str//\[/\\[}"
    str="${str//\]/\\]}"
    local lbrace='{' rbrace='}'
    str="${str//$lbrace/\\$lbrace}"
    str="${str//$rbrace/\\$rbrace}"
    str="${str//|/\\|}"
    echo "$str"
}

_profile_remove_brew_line() {
    local file="$1" type="$2" name="$3"
    local escaped_name=$(_profile_escape_regex "$name")
    local pattern="^[[:space:]]*${type}[[:space:]]+\"${escaped_name}\""

    # Remove the matching line
    _profile_remove_line "$file" "$pattern"

    # Clean up empty if/end blocks
    _profile_clean_empty_blocks "$file"
}

_profile_clean_empty_blocks() {
    local file="$1"
    local -a lines=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        lines+=("$line")
    done < "$file"

    local -a output=()
    local i=1
    while [[ $i -le ${#lines[@]} ]]; do
        local line="${lines[$i]}"
        if [[ "$line" =~ ^[[:space:]]*'if '[Oo] ]]; then
            # Found an if block — scan for end
            local has_content=false
            local j=$((i + 1))
            while [[ $j -le ${#lines[@]} ]]; do
                local inner="${lines[$j]}"
                if [[ "$inner" =~ ^[[:space:]]*end[[:space:]]*$ ]]; then
                    break
                fi
                # Check if line has non-blank, non-comment content
                local stripped="${inner%%#*}"
                stripped="${stripped// /}"
                stripped="${stripped//	/}"
                if [[ -n "$stripped" ]]; then
                    has_content=true
                fi
                (( j++ ))
            done
            if [[ "$has_content" == false && $j -le ${#lines[@]} ]]; then
                # Skip the entire empty block (if line through end line)
                i=$((j + 1))
                continue
            fi
        fi
        output+=("$line")
        (( i++ ))
    done

    printf '%s\n' "${output[@]}" > "$file"
}

# --- Source-tracking readers (emit "item\tfile" pairs) ---

_profile_read_brew_packages_sourced() {
    local -a files=("$@")
    for f in "${files[@]}"; do
        [[ -f "$f" ]] || continue
        local skip=false
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%%#*}"
            if [[ "$line" =~ ^[[:space:]]*if\ +OS\.mac\? ]]; then
                [[ "$IS_MACOS" != true ]] && skip=true
                continue
            elif [[ "$line" =~ ^[[:space:]]*if\ +OS\.linux\? ]]; then
                [[ "$IS_LINUX" != true ]] && skip=true
                continue
            elif [[ "$line" =~ ^[[:space:]]*end[[:space:]]*$ ]]; then
                skip=false
                continue
            fi
            [[ "$skip" == true ]] && continue
            if [[ "$line" =~ ^[[:space:]]*brew\ +\"([^\"]+)\" ]]; then
                printf 'brew:%s\t%s\n' "${match[1]}" "$f"
            elif [[ "$line" =~ ^[[:space:]]*cask\ +\"([^\"]+)\" ]]; then
                printf 'cask:%s\t%s\n' "${match[1]}" "$f"
            fi
        done < "$f"
    done
}

_profile_read_extensions_sourced() {
    local -a files=("$@")
    for f in "${files[@]}"; do
        [[ -f "$f" ]] || continue
        while IFS= read -r ext || [[ -n "$ext" ]]; do
            ext="${ext%%#*}"
            ext="${ext// /}"
            [[ -n "$ext" ]] && printf '%s\t%s\n' "$ext" "$f"
        done < "$f"
    done
}

# --- Mise TOML splitting ---

_profile_mise_split_tools() {
    local input="$1" tools_out="$2" rest_out="$3"
    local in_tools=false

    : > "$tools_out"
    : > "$rest_out"

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "[tools]" ]]; then
            in_tools=true
            continue
        elif [[ "$line" == \[* ]]; then
            in_tools=false
        fi

        if [[ "$in_tools" == true ]]; then
            echo "$line" >> "$tools_out"
        else
            echo "$line" >> "$rest_out"
        fi
    done < "$input"
}

_profile_read_mise_tools_sourced() {
    local -a files=("$@")
    for f in "${files[@]}"; do
        [[ -f "$f" ]] || continue
        local in_tools=false
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" == "[tools]" ]]; then
                in_tools=true
                continue
            elif [[ "$line" == \[* ]]; then
                in_tools=false
                continue
            fi
            [[ "$in_tools" == false ]] && continue
            [[ -z "$line" ]] && continue
            # Extract tool name (everything before = sign), trim whitespace
            local tool_name="${line%%=*}"
            tool_name="${tool_name## }"
            tool_name="${tool_name%% }"
            [[ -n "$tool_name" ]] && printf '%s\t%s\n' "$tool_name" "$f"
        done < "$f"
    done
}
