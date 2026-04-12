# Profile system - snapshot, hashing, and drift detection

typeset -ga _PROFILE_RECONCILE_LINES=()
typeset -g _PROFILE_RECONCILE_SAFE_COUNT=0
typeset -g _PROFILE_RECONCILE_BLOCKED_COUNT=0
typeset -g _PROFILE_RECONCILE_CONFLICT_COUNT=0
typeset -g _PROFILE_REMOTE_STATE=""
typeset -g _PROFILE_REMOTE_AHEAD=0
typeset -g _PROFILE_REMOTE_BEHIND=0
typeset -g _PROFILE_REMOTE_MESSAGE=""

_profile_take_snapshot() {
    local profiles="$1"
    mkdir -p "$PROFILE_STATE_DIR"
    # Use the same hash function so no-op detection stays in sync
    _profile_compute_hash "$profiles" > "$PROFILE_SNAPSHOT_FILE"
    cp "$PROFILE_SNAPSHOT_FILE" "$PROFILE_CHECKPOINT_FILE"

    # Local target file hashes (for three-way sync direction detection)
    local snap_local="$PROFILE_STATE_DIR/snapshot-local"
    : > "$snap_local"
    while IFS= read -r target_path; do
        if [[ -n "$target_path" && -f "$target_path" ]]; then
            local real_path="$target_path"
            [[ -L "$target_path" ]] && real_path=$(_profile_resolve_link_target "$target_path")
            printf '%s\t%s\n' "$target_path" "$(_platform_md5 "$real_path")" >> "$snap_local"
        fi
    done < <(_profile_tracked_target_paths "$profiles" | sort -u)
}

_profile_checkpoint_hash() {
    [[ -f "$PROFILE_CHECKPOINT_FILE" ]] || return 1
    cat "$PROFILE_CHECKPOINT_FILE" 2>/dev/null
}

_profile_checkpoint_stale() {
    local profiles="$1"
    [[ -f "$PROFILE_CHECKPOINT_FILE" ]] || return 1

    local current_hash stored_hash
    current_hash=$(_profile_compute_hash "$profiles")
    stored_hash=$(_profile_checkpoint_hash)
    [[ "$current_hash" != "$stored_hash" ]]
}

_profile_compute_hash() {
    local profiles="$1"
    local hash=""
    # Source profile files
    for dir in $(_profile_collect_dirs "$profiles"); do
        for f in $(_profile_snapshot_files "$dir"); do
            [[ -f "$f" ]] && hash+=$(_platform_md5 "$f" 2>/dev/null)
        done
    done
    # Target files - detect overwrites, broken symlinks, regular-file-vs-symlink
    while IFS= read -r target_path; do
        if [[ -n "$target_path" ]]; then
            if [[ -L "$target_path" ]]; then
                hash+="L:$(readlink "$target_path")"
            elif [[ -f "$target_path" ]]; then
                hash+=$(_platform_md5 "$target_path" 2>/dev/null)
            else
                hash+="missing"
            fi
        fi
    done < <(_profile_tracked_target_paths "$profiles" | sort -u)
    echo "$hash"
}

# Retrieve snapshot hash for a local target file
_profile_local_snap_hash() {
    local target_path="$1"
    local snap_file="$PROFILE_STATE_DIR/snapshot-local"
    [[ -f "$snap_file" ]] || return
    local snap_path snap_hash
    while IFS=$'\t' read -r snap_path snap_hash <&3; do
        [[ "$snap_path" == "$target_path" ]] && { echo "$snap_hash"; return; }
    done 3< "$snap_file"
}

_profile_record_reconcile_state() {
    local label="$1" policy="$2"

    case "$_PROFILE_SYNC_STATE" in
        in_sync)
            ;;
        missing_local|profile_to_local)
            (( _PROFILE_RECONCILE_SAFE_COUNT++ )) || true
            _PROFILE_RECONCILE_LINES+=("$label: profile changes can be applied automatically ($(_profile_policy_description "$policy"))")
            ;;
        local_to_profile)
            (( _PROFILE_RECONCILE_SAFE_COUNT++ )) || true
            _PROFILE_RECONCILE_LINES+=("$label: local changes can be synced back automatically ($(_profile_policy_description "$policy"))")
            ;;
        blocked_local_output)
            (( _PROFILE_RECONCILE_BLOCKED_COUNT++ )) || true
            _PROFILE_RECONCILE_LINES+=("$label: local edits are on a merged multi-profile output; update the source profiles directly")
            ;;
        blocked_conflict|conflict)
            (( _PROFILE_RECONCILE_CONFLICT_COUNT++ )) || true
            _PROFILE_RECONCILE_LINES+=("$label: conflict requires user review")
            ;;
    esac
}

_profile_record_reconcile_review() {
    local label="$1" detail="$2"
    (( _PROFILE_RECONCILE_CONFLICT_COUNT++ )) || true
    _PROFILE_RECONCILE_LINES+=("$label: $detail")
}

_profile_record_reconcile_safe() {
    local label="$1" detail="$2"
    (( _PROFILE_RECONCILE_SAFE_COUNT++ )) || true
    _PROFILE_RECONCILE_LINES+=("$label: $detail")
}

_profile_record_reconcile_blocked() {
    local label="$1" detail="$2"
    (( _PROFILE_RECONCILE_BLOCKED_COUNT++ )) || true
    _PROFILE_RECONCILE_LINES+=("$label: $detail")
}

_profile_record_link_reconcile_state() {
    local label="$1" target_path="$2" expected_source="$3" safe_detail="$4" blocked_detail="$5"
    local link_state=$(_profile_link_target_state "$target_path" "$expected_source")

    case "$link_state" in
        in_sync)
            ;;
        blocked_directory)
            _profile_record_reconcile_blocked "$label" "$blocked_detail"
            ;;
        *)
            _profile_record_reconcile_safe "$label" "$safe_detail"
            ;;
    esac
}

_profile_scan_structured_profile_target() {
    local label="$1" kind="$2" profiles="$3" domain="$4" relative_path="$5" target_root="$6" format="$7"
    local -a source_files=()
    local source_file=""

    while IFS= read -r source_file; do
        [[ -n "$source_file" ]] && source_files+=("$source_file")
    done < <(_profile_collect_domain_file_sources "$profiles" "$domain" "$relative_path")
    [[ ${#source_files[@]} -eq 0 ]] && return 0

    local target_file="$target_root/$relative_path"
    local policy=$(_profile_config_policy "$kind" ${#source_files[@]})
    local expected_file=""

    if [[ ${#source_files[@]} -eq 1 ]]; then
        expected_file="${source_files[1]}"
    else
        expected_file=$(mktemp)
        _profile_merge_structured_files "$format" "$expected_file" "${source_files[@]}" || {
            rm -f "$expected_file"
            return 1
        }
    fi

    _profile_analyze_config_sync "$policy" "$target_file" "$expected_file" "${source_files[@]}"
    _profile_record_reconcile_state "$label" "$policy"

    if [[ ${#source_files[@]} -gt 1 ]]; then
        rm -f "$expected_file"
    fi
}

_profile_scan_last_wins_target() {
    local label="$1" profiles="$2" domain="$3" relative_path="$4" target_file="$5"
    local source=$(_profile_resolve_last_wins_source "$profiles" "$domain" "$relative_path")
    [[ -n "$source" ]] || return 0

    local policy=$(_profile_config_policy last_wins 1)
    _profile_analyze_config_sync "$policy" "$target_file" "$source" "$source"
    _profile_record_reconcile_state "$label" "$policy"
}

_profile_scan_union_file_collection_target() {
    local label="$1" profiles="$2" domain="$3" relative_dir="$4" glob_pattern="$5" target_root="$6"
    local basename="" source_file=""

    while IFS=$'\t' read -r basename source_file; do
        [[ -n "$basename" && -n "$source_file" ]] || continue
        local target_file="$target_root/$relative_dir/$basename"
        _profile_record_link_reconcile_state \
            "$label ($basename)" \
            "$target_file" \
            "$source_file" \
            "profile links can be applied automatically (union collection)" \
            "conflicting directory blocks automatic link repair"
    done < <(_profile_collect_union_file_sources "$profiles" "$domain" "$relative_dir" "$glob_pattern")
}

_profile_scan_skills_targets() {
    local profiles="$1"
    local -A agent_roots=(
        [claude]="$HOME/.claude"
        [codex]="$HOME/.codex"
    )
    local -a all_agents=(${(k)agent_roots})
    local -A audience_sources=()
    local -a profile_list=(default)
    local profile_name=""
    for profile_name in ${=profiles}; do
        [[ "$profile_name" == "default" ]] && continue
        profile_list+=("$profile_name")
    done

    for profile_name in "${profile_list[@]}"; do
        local skills_dir="$PROFILES_DIR/$profile_name/skills"
        [[ -d "$skills_dir" ]] || continue
        local audience_dir=""
        for audience_dir in "$skills_dir"/*(N/); do
            local audience="${audience_dir:t}"
            local skill_dir=""
            for skill_dir in "$audience_dir"/*(N/); do
                local skill_name="${skill_dir:t}"
                [[ "$skill_name" == .system ]] && continue
                audience_sources["$audience/$skill_name"]="$skill_dir"
            done
        done
    done

    local key=""
    for key in ${(ok)audience_sources}; do
        local audience="${key%%/*}"
        local skill_name="${key#*/}"
        local source_dir="${audience_sources[$key]}"
        local -a targets=()
        if [[ "$audience" == "shared" ]]; then
            targets=("${all_agents[@]}")
        elif (( ${+agent_roots[$audience]} )); then
            targets=("$audience")
        else
            continue
        fi

        local target_agent=""
        for target_agent in "${targets[@]}"; do
            local target_dir="${agent_roots[$target_agent]}/skills/$skill_name"
            _profile_record_link_reconcile_state \
                "Skills ($target_agent:$skill_name)" \
                "$target_dir" \
                "$source_dir" \
                "profile links can be applied automatically (union collection)" \
                "conflicting directory blocks automatic link repair"
        done
    done
}

_profile_scan_derived_symlink_target() {
    local label="$1" source_path="$2" target_path="$3"
    [[ ! -e "$source_path" && ! -L "$source_path" ]] && return 0
    _profile_record_link_reconcile_state \
        "$label" \
        "$target_path" \
        "$source_path" \
        "derived symlink can be restored automatically" \
        "conflicting directory blocks automatic link repair"
}

_profile_display_managed_path() {
    local managed_path="$1"
    if [[ "$managed_path" == "$HOME/"* ]]; then
        echo "${managed_path/#$HOME/~}"
    else
        echo "$managed_path"
    fi
}

_profile_scan_stale_managed_targets() {
    local profiles="$1"
    local stale_path=""

    while IFS= read -r stale_path; do
        [[ -n "$stale_path" ]] || continue

        if [[ -L "$stale_path" ]]; then
            _profile_record_reconcile_safe \
                "Stale managed target ($(_profile_display_managed_path "$stale_path"))" \
                "obsolete managed symlink can be removed automatically"
            continue
        fi

        if [[ -d "$stale_path" && ! -L "$stale_path" ]]; then
            if _profile_dir_is_empty "$stale_path"; then
                _profile_record_reconcile_safe \
                    "Stale managed target ($(_profile_display_managed_path "$stale_path"))" \
                    "obsolete empty managed directory can be removed automatically"
            else
                _profile_record_reconcile_blocked \
                    "Stale managed target ($(_profile_display_managed_path "$stale_path"))" \
                    "managed target is no longer expected but a local directory still exists"
            fi
            continue
        fi

        if [[ -e "$stale_path" ]]; then
            _profile_record_reconcile_blocked \
                "Stale managed target ($(_profile_display_managed_path "$stale_path"))" \
                "managed target is no longer expected but a local file still exists"
        fi
    done < <(_profile_stale_managed_paths "$profiles")
}

_profile_scan_brew_state() {
    local profiles="$1"
    local default_brewfile="$PROFILES_DIR/default/Brewfile"
    [[ -f "$default_brewfile" ]] || return 0
    command -v brew >/dev/null 2>&1 || return 0

    local -a brewfiles=("$default_brewfile")
    local p=""
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        [[ -f "$PROFILES_DIR/$p/Brewfile" ]] && brewfiles+=("$PROFILES_DIR/$p/Brewfile")
    done

    local sourced=$(_profile_read_brew_packages_sourced "${brewfiles[@]}")
    local expected=$(echo "$sourced" | cut -f1 | grep -v "^$" | sort -u)
    local expected_no_tap=$(echo "$expected" | grep -v "^tap:")
    local all_profile_packages=$(_profile_read_all_brew_packages)
    local all_profile_no_tap=$(echo "$all_profile_packages" | grep -v "^tap:")
    local current_formulae=$(brew leaves 2>/dev/null | sort)
    local current_casks=$(brew list --cask 2>/dev/null | sort)
    local installed=$( (echo "$current_formulae" | sed '/^$/d' | sed 's/^/brew:/'; echo "$current_casks" | sed '/^$/d' | sed 's/^/cask:/') | sort -u)

    local to_install=$(comm -23 <(echo "$expected_no_tap") <(echo "$installed") | grep -v '^$')
    local to_add=$(comm -23 <(echo "$installed") <(echo "$all_profile_no_tap") | grep -v '^$')
    local review_to_add=""
    local pkg=""
    for pkg in ${(f)to_add}; do
        [[ -z "$pkg" ]] && continue
        _profile_sync_skip_contains "brew" "$pkg" && continue
        review_to_add+="$pkg"$'\n'
    done

    [[ -n "$to_install" ]] && _profile_record_reconcile_review "Brew packages" "profile expects packages that are not installed; review install vs removing them from the profile"
    [[ -n "$review_to_add" ]] && _profile_record_reconcile_review "Brew packages" "packages are installed locally but not tracked by the active profiles; review add vs uninstall"
}

_profile_scan_vscode_extensions_state() {
    local profiles="$1"
    local default_ext="$PROFILES_DIR/default/vscode/extensions.txt"
    local instances=$(_profile_vscode_instances 2>/dev/null)
    [[ -n "$instances" ]] || return 0

    local -a ext_files=()
    [[ -f "$default_ext" ]] && ext_files+=("$default_ext")
    local p=""
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        [[ -f "$PROFILES_DIR/$p/vscode/extensions.txt" ]] && ext_files+=("$PROFILES_DIR/$p/vscode/extensions.txt")
    done
    [[ ${#ext_files[@]} -gt 0 ]] || return 0

    local expected=$(_profile_read_extensions "${ext_files[@]}")
    local inst_label="" vscode_user_dir="" cli=""
    while IFS='|' read -r inst_label vscode_user_dir cli; do
        [[ -z "$inst_label" || -z "$cli" ]] && continue
        local installed=$("$cli" --list-extensions 2>/dev/null | sort -u)
        local to_install=$(comm -23 <(echo "$expected") <(echo "$installed") | grep -v '^$')
        local to_add=$(comm -23 <(echo "$installed") <(echo "$expected") | grep -v '^$')
        local review_to_add=""
        local ext=""
        for ext in ${(f)to_add}; do
            [[ -z "$ext" ]] && continue
            _profile_sync_skip_contains_any "$ext" "vscode:$inst_label" "vscode" && continue
            review_to_add+="$ext"$'\n'
        done

        [[ -n "$to_install" ]] && _profile_record_reconcile_review "VSCode extensions ($inst_label)" "profile expects extensions that are not installed; review install vs removing them from the profile"
        [[ -n "$review_to_add" ]] && _profile_record_reconcile_review "VSCode extensions ($inst_label)" "extensions are installed locally but not tracked by the active profiles; review add vs uninstall"
    done <<< "$instances"
}

_profile_scan_mise_tools_state() {
    local profiles="$1"
    command -v mise >/dev/null 2>&1 || return 0

    local -a mise_files=()
    [[ -f "$PROFILES_DIR/default/mise/config.toml" ]] && mise_files+=("$PROFILES_DIR/default/mise/config.toml")
    local p=""
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        [[ -f "$PROFILES_DIR/$p/mise/config.toml" ]] && mise_files+=("$PROFILES_DIR/$p/mise/config.toml")
    done
    [[ ${#mise_files[@]} -gt 0 ]] || return 0

    local sourced=$(_profile_read_mise_tools_sourced "${mise_files[@]}")
    local expected_tools=$(echo "$sourced" | cut -f1 | sort -u)
    local installed_tools=$(mise ls --installed --json 2>/dev/null | jq -r 'keys[]' 2>/dev/null | sort -u)
    local to_install=$(comm -23 <(echo "$expected_tools") <(echo "$installed_tools") | grep -v '^$')
    local to_add=$(comm -23 <(echo "$installed_tools") <(echo "$expected_tools") | grep -v '^$')
    local review_to_add=""
    local tool=""
    for tool in ${(f)to_add}; do
        [[ -z "$tool" ]] && continue
        _profile_sync_skip_contains "mise" "$tool" && continue
        review_to_add+="$tool"$'\n'
    done

    [[ -n "$to_install" ]] && _profile_record_reconcile_review "Mise tools" "profile expects tools that are not installed; review install vs removing them from the profile"
    [[ -n "$review_to_add" ]] && _profile_record_reconcile_review "Mise tools" "tools are installed locally but not tracked by the active profiles; review add vs uninstall"
}

_profile_collect_reconcile_status() {
    local profiles="$1"
    _PROFILE_RECONCILE_LINES=()
    _PROFILE_RECONCILE_SAFE_COUNT=0
    _PROFILE_RECONCILE_BLOCKED_COUNT=0
    _PROFILE_RECONCILE_CONFLICT_COUNT=0

    _profile_scan_structured_profile_target "Claude settings" "structured_canonical" "$profiles" "claude" "settings.json" "$HOME/.claude" "json"
    _profile_scan_structured_profile_target "Codex config" "structured_canonical" "$profiles" "codex" "config.toml" "$HOME/.codex" "toml"
    _profile_scan_structured_profile_target "Codex hooks" "structured_canonical" "$profiles" "codex" "hooks.json" "$HOME/.codex" "json"

    local relative_path=""
    for relative_path in "${_CLAUDE_LAST_WINS_PATHS[@]}"; do
        _profile_scan_last_wins_target "Claude $relative_path" "$profiles" "claude" "$relative_path" "$HOME/.claude/$relative_path"
    done

    _profile_scan_last_wins_target "Codex rules" "$profiles" "codex" "rules/default.rules" "$HOME/.codex/rules/default.rules"
    _profile_scan_last_wins_target "Tmux" "$profiles" "tmux" "tmux.conf" "$HOME/.tmux.conf"
    _profile_scan_union_file_collection_target "Claude hooks" "$profiles" "claude" "hooks" "*" "$HOME/.claude"
    _profile_scan_union_file_collection_target "Claude commands" "$profiles" "claude" "commands" "*.md" "$HOME/.claude"
    _profile_scan_union_file_collection_target "Codex hooks" "$profiles" "codex" "hooks" "*" "$HOME/.codex"
    _profile_scan_union_file_collection_target "Codex agents" "$profiles" "codex" "agents" "*.toml" "$HOME/.codex"
    _profile_scan_skills_targets "$profiles"
    _profile_scan_derived_symlink_target "AGENTS.md bridge" "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md"
    _profile_scan_stale_managed_targets "$profiles"
    _profile_scan_brew_state "$profiles"
    _profile_scan_vscode_extensions_state "$profiles"
    _profile_scan_mise_tools_state "$profiles"

    local -a settings_files=()
    [[ -f "$PROFILES_DIR/default/vscode/settings.json" ]] && settings_files+=("$PROFILES_DIR/default/vscode/settings.json")
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        [[ -f "$PROFILES_DIR/$p/vscode/settings.json" ]] && settings_files+=("$PROFILES_DIR/$p/vscode/settings.json")
    done
    if [[ ${#settings_files[@]} -gt 0 ]]; then
        local expected_settings=$(mktemp)
        if [[ ${#settings_files[@]} -eq 1 ]]; then
            cp "${settings_files[1]}" "$expected_settings"
        else
            jq -s 'reduce .[] as $item ({}; . * $item)' "${settings_files[@]}" > "$expected_settings"
        fi
        while IFS='|' read -r inst_label vscode_user_dir _cli; do
            [[ -z "$inst_label" ]] && continue
            local policy=$(_profile_config_policy structured_copy ${#settings_files[@]})
            _profile_analyze_config_sync "$policy" "$vscode_user_dir/settings.json" "$expected_settings" "${settings_files[@]}"
            _profile_record_reconcile_state "VSCode settings ($inst_label)" "$policy"
        done < <(_profile_vscode_instances 2>/dev/null)
        rm -f "$expected_settings"
    fi

    local kb_source=""
    [[ -f "$PROFILES_DIR/default/vscode/keybindings.json" ]] && kb_source="$PROFILES_DIR/default/vscode/keybindings.json"
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        [[ -f "$PROFILES_DIR/$p/vscode/keybindings.json" ]] && kb_source="$PROFILES_DIR/$p/vscode/keybindings.json"
    done
    if [[ -n "$kb_source" ]]; then
        while IFS='|' read -r inst_label vscode_user_dir _cli; do
            [[ -z "$inst_label" ]] && continue
            local policy=$(_profile_config_policy last_wins 1)
            _profile_analyze_config_sync "$policy" "$vscode_user_dir/keybindings.json" "$kb_source" "$kb_source"
            _profile_record_reconcile_state "VSCode keybindings ($inst_label)" "$policy"
        done < <(_profile_vscode_instances 2>/dev/null)
    fi

    local -a mise_files=()
    [[ -f "$PROFILES_DIR/default/mise/config.toml" ]] && mise_files+=("$PROFILES_DIR/default/mise/config.toml")
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        [[ -f "$PROFILES_DIR/$p/mise/config.toml" ]] && mise_files+=("$PROFILES_DIR/$p/mise/config.toml")
    done
    if [[ ${#mise_files[@]} -gt 0 ]]; then
        local policy=$(_profile_config_policy structured_canonical ${#mise_files[@]})
        local expected_mise=""
        if [[ ${#mise_files[@]} -eq 1 ]]; then
            expected_mise="${mise_files[1]}"
        else
            expected_mise=$(mktemp)
            _profile_merge_toml_files "$expected_mise" "${mise_files[@]}" || {
                rm -f "$expected_mise"
                expected_mise=""
            }
        fi
        if [[ -n "$expected_mise" ]]; then
            _profile_analyze_config_sync "$policy" "$HOME/.config/mise/config.toml" "$expected_mise" "${mise_files[@]}"
            _profile_record_reconcile_state "Mise config" "$policy"
        fi
        [[ ${#mise_files[@]} -gt 1 && -n "$expected_mise" ]] && rm -f "$expected_mise"
    fi

    local -a iterm_files=()
    [[ -f "$PROFILES_DIR/default/iterm/profile.json" ]] && iterm_files+=("$PROFILES_DIR/default/iterm/profile.json")
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        [[ -f "$PROFILES_DIR/$p/iterm/profile.json" ]] && iterm_files+=("$PROFILES_DIR/$p/iterm/profile.json")
    done
    if [[ ${#iterm_files[@]} -gt 0 && -d "$HOME/Library/Application Support/iTerm2" ]]; then
        local expected_iterm=$(mktemp)
        if [[ ${#iterm_files[@]} -eq 1 ]]; then
            cp "${iterm_files[1]}" "$expected_iterm"
        else
            jq -s 'reduce .[] as $item ({}; {"Profiles": [(.Profiles[0] // {}) * ($item.Profiles[0] // {})]})' \
                "${iterm_files[@]}" > "$expected_iterm"
        fi
        local policy=$(_profile_config_policy structured_copy ${#iterm_files[@]})
        _profile_analyze_config_sync "$policy" "$HOME/Library/Application Support/iTerm2/DynamicProfiles/dotfiles.json" "$expected_iterm" "${iterm_files[@]}"
        _profile_record_reconcile_state "iTerm" "$policy"
        rm -f "$expected_iterm"
    fi
}

# --- Drift check ---

_profile_check_drift() {
    _profile_dedup_dotfiles

    local active=$(_profile_active)
    [[ -z "$active" ]] && return 0
    [[ ! -f "$PROFILE_CHECKPOINT_FILE" ]] && return 0

    local checkpoint_stale=false
    if _profile_checkpoint_stale "$active"; then
        checkpoint_stale=true
    fi
    _profile_collect_reconcile_status "$active"

    if [[ "$checkpoint_stale" == false && $_PROFILE_RECONCILE_SAFE_COUNT -eq 0 && $_PROFILE_RECONCILE_BLOCKED_COUNT -eq 0 && $_PROFILE_RECONCILE_CONFLICT_COUNT -eq 0 ]]; then
        return 0
    fi

    if (( _PROFILE_RECONCILE_CONFLICT_COUNT > 0 || _PROFILE_RECONCILE_BLOCKED_COUNT > 0 )); then
        local display="${active// /, }"
        echo "Profile(s) '$display' need review. Run 'profile status' to inspect before syncing."
        return 0
    fi

    if (( _PROFILE_RECONCILE_SAFE_COUNT > 0 )); then
        local display="${active// /, }"
        echo "Profile(s) '$display' have safe changes ready to sync. Run 'profile sync' to apply them."
        return 0
    fi

    local display="${active// /, }"
    echo "Profile(s) '$display' changed since the last checkpoint, but live targets already match."
    echo "Run 'profile status' to review remote state before checkpointing."
}

# --- Remote check ---

_profile_remote_refresh_needed() {
    local fetch_head="$DOTFILES_DIR/.git/FETCH_HEAD"
    [[ -f "$fetch_head" ]] || return 0

    local mtime
    mtime=$(stat -c %Y "$fetch_head" 2>/dev/null || stat -f %m "$fetch_head" 2>/dev/null)
    [[ "$mtime" =~ ^[0-9]+$ ]] || return 0
    local fetch_age=$(( $(date +%s) - mtime ))
    (( fetch_age > 3600 ))
}

_profile_git_worktree_dirty() {
    local changes
    changes=$(git -C "$DOTFILES_DIR" status --porcelain 2>/dev/null)
    [[ -n "$changes" ]]
}

_profile_check_remote() {
    local refresh="${1:-false}"
    _PROFILE_REMOTE_STATE="unavailable"
    _PROFILE_REMOTE_AHEAD=0
    _PROFILE_REMOTE_BEHIND=0
    _PROFILE_REMOTE_MESSAGE="Dotfiles repo has no git metadata available."
    [[ ! -d "$DOTFILES_DIR/.git" ]] && return 0

    git -C "$DOTFILES_DIR" rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1 || {
        _PROFILE_REMOTE_STATE="no_upstream"
        _PROFILE_REMOTE_MESSAGE="No upstream configured for the dotfiles repo."
        return 0
    }

    if [[ "$refresh" == "true" ]] && _profile_remote_refresh_needed; then
        if ! git -C "$DOTFILES_DIR" fetch --quiet --prune >/dev/null 2>&1; then
            _PROFILE_REMOTE_STATE="refresh_failed"
            _PROFILE_REMOTE_MESSAGE="Could not refresh remote metadata for the dotfiles repo."
            return 1
        fi
    elif _profile_remote_refresh_needed; then
        _PROFILE_REMOTE_STATE="stale"
        _PROFILE_REMOTE_MESSAGE="Remote metadata is older than one hour."
        return 0
    fi

    local counts
    counts=$(git -C "$DOTFILES_DIR" rev-list --left-right --count HEAD...@{u} 2>/dev/null) || {
        _PROFILE_REMOTE_STATE="unknown"
        _PROFILE_REMOTE_MESSAGE="Could not compare the dotfiles repo with its upstream."
        return 1
    }
    _PROFILE_REMOTE_AHEAD=${counts%%$'\t'*}
    _PROFILE_REMOTE_BEHIND=${counts#*$'\t'}

    if [[ "$_PROFILE_REMOTE_AHEAD" -gt 0 && "$_PROFILE_REMOTE_BEHIND" -gt 0 ]]; then
        _PROFILE_REMOTE_STATE="diverged"
        _PROFILE_REMOTE_MESSAGE="Dotfiles repo has diverged from upstream."
    elif [[ "$_PROFILE_REMOTE_BEHIND" -gt 0 ]]; then
        _PROFILE_REMOTE_STATE="behind"
        _PROFILE_REMOTE_MESSAGE="Dotfiles repo is ${_PROFILE_REMOTE_BEHIND} commit(s) behind upstream."
    elif [[ "$_PROFILE_REMOTE_AHEAD" -gt 0 ]]; then
        _PROFILE_REMOTE_STATE="ahead"
        _PROFILE_REMOTE_MESSAGE="Dotfiles repo is ${_PROFILE_REMOTE_AHEAD} commit(s) ahead of upstream."
    else
        _PROFILE_REMOTE_STATE="current"
        _PROFILE_REMOTE_MESSAGE="Dotfiles repo is up to date with upstream."
    fi
}

_profile_sync_preflight() {
    _profile_check_remote true || return 1

    case "$_PROFILE_REMOTE_STATE" in
        current|ahead|no_upstream|unavailable)
            return 0
            ;;
        behind)
            if _profile_git_worktree_dirty; then
                echo "$_PROFILE_REMOTE_MESSAGE"
                echo "Pull the upstream changes before syncing because the dotfiles worktree is dirty."
                return 1
            fi
            if ! git -C "$DOTFILES_DIR" pull --ff-only --quiet >/dev/null 2>&1; then
                echo "Could not fast-forward the dotfiles repo before syncing."
                return 1
            fi
            _PROFILE_REMOTE_STATE="current"
            _PROFILE_REMOTE_MESSAGE="Dotfiles repo was fast-forwarded before syncing."
            return 0
            ;;
        diverged)
            echo "$_PROFILE_REMOTE_MESSAGE"
            echo "Resolve the divergence before running 'profile sync'."
            return 1
            ;;
        stale|refresh_failed|unknown)
            echo "$_PROFILE_REMOTE_MESSAGE"
            echo "Unable to make a safe sync decision with stale or unknown remote state."
            return 1
            ;;
    esac
}
