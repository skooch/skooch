# Profile system - bidirectional sync (three-way merge)

# --- Three-way sync helper ---

_PROFILE_SYNC_STATE=""
_PROFILE_SYNC_EXPECTED_HASH=""
_PROFILE_SYNC_LOCAL_HASH=""
_PROFILE_SYNC_SNAP_HASH=""
_PROFILE_SYNC_PROFILE_CHANGED=false
_PROFILE_SYNC_LOCAL_CHANGED=false

_profile_sync_merge_status() {
    local current="${1:-0}" next="${2:-0}"
    if (( next > current )); then
        echo "$next"
    else
        echo "$current"
    fi
}

_profile_prune_stale_managed_targets() {
    local profiles="$1"
    local overall=0
    local stale_path=""

    while IFS= read -r stale_path; do
        [[ -n "$stale_path" ]] || continue

        if [[ -L "$stale_path" ]]; then
            rm -f "$stale_path"
            echo "  Removed stale managed link: $(_profile_display_managed_path "$stale_path")"
            overall=$(_profile_sync_merge_status "$overall" 1)
            continue
        fi

        if [[ -d "$stale_path" && ! -L "$stale_path" ]]; then
            if _profile_dir_is_empty "$stale_path"; then
                rmdir "$stale_path"
                echo "  Removed stale managed directory: $(_profile_display_managed_path "$stale_path")"
                overall=$(_profile_sync_merge_status "$overall" 1)
            else
                echo "  Stale managed target requires review: $(_profile_display_managed_path "$stale_path")"
                overall=$(_profile_sync_merge_status "$overall" 2)
            fi
            continue
        fi

        if [[ -e "$stale_path" ]]; then
            echo "  Stale managed target requires review: $(_profile_display_managed_path "$stale_path")"
            overall=$(_profile_sync_merge_status "$overall" 2)
        fi
    done < <(_profile_stale_managed_paths "$profiles")

    return "$overall"
}

_profile_analyze_config_sync() {
    local policy="$1" local_file="$2" expected_file="$3"
    shift 3
    local -a profile_sources=("$@")

    _PROFILE_SYNC_STATE=""
    _PROFILE_SYNC_EXPECTED_HASH=$(_platform_md5 "$expected_file")
    _PROFILE_SYNC_LOCAL_HASH=""
    _PROFILE_SYNC_SNAP_HASH=$(_profile_local_snap_hash "$local_file")
    _PROFILE_SYNC_PROFILE_CHANGED=false
    _PROFILE_SYNC_LOCAL_CHANGED=false

    if [[ -f "$local_file" ]]; then
        local real="$local_file"
        [[ -L "$local_file" ]] && real=$(_profile_resolve_link_target "$local_file")
        _PROFILE_SYNC_LOCAL_HASH=$(_platform_md5 "$real")
    fi

    if [[ "$_PROFILE_SYNC_LOCAL_HASH" == "$_PROFILE_SYNC_EXPECTED_HASH" ]]; then
        _PROFILE_SYNC_STATE="in_sync"
        return 0
    fi

    if [[ ! -e "$local_file" && ! -L "$local_file" ]]; then
        _PROFILE_SYNC_STATE="missing_local"
        return 0
    fi

    if [[ -z "$_PROFILE_SYNC_SNAP_HASH" ]]; then
        _PROFILE_SYNC_PROFILE_CHANGED=true
    else
        [[ "$_PROFILE_SYNC_EXPECTED_HASH" != "$_PROFILE_SYNC_SNAP_HASH" ]] && _PROFILE_SYNC_PROFILE_CHANGED=true
        [[ "$_PROFILE_SYNC_LOCAL_HASH" != "$_PROFILE_SYNC_SNAP_HASH" ]] && _PROFILE_SYNC_LOCAL_CHANGED=true
    fi

    if [[ "$policy" == "merged_output_no_sync_back" ]]; then
        if [[ "$_PROFILE_SYNC_PROFILE_CHANGED" == true && "$_PROFILE_SYNC_LOCAL_CHANGED" == false ]]; then
            _PROFILE_SYNC_STATE="profile_to_local"
        elif [[ "$_PROFILE_SYNC_PROFILE_CHANGED" == false && "$_PROFILE_SYNC_LOCAL_CHANGED" == true ]]; then
            _PROFILE_SYNC_STATE="blocked_local_output"
        elif [[ "$_PROFILE_SYNC_PROFILE_CHANGED" == true && "$_PROFILE_SYNC_LOCAL_CHANGED" == true ]]; then
            _PROFILE_SYNC_STATE="blocked_conflict"
        else
            _PROFILE_SYNC_STATE="in_sync"
        fi
        return 0
    fi

    if [[ "$_PROFILE_SYNC_PROFILE_CHANGED" == true && "$_PROFILE_SYNC_LOCAL_CHANGED" == false ]]; then
        _PROFILE_SYNC_STATE="profile_to_local"
    elif [[ "$_PROFILE_SYNC_PROFILE_CHANGED" == false && "$_PROFILE_SYNC_LOCAL_CHANGED" == true ]]; then
        _PROFILE_SYNC_STATE="local_to_profile"
    elif [[ "$_PROFILE_SYNC_PROFILE_CHANGED" == true && "$_PROFILE_SYNC_LOCAL_CHANGED" == true ]]; then
        _PROFILE_SYNC_STATE="conflict"
    else
        _PROFILE_SYNC_STATE="in_sync"
    fi
}

_profile_apply_sync_target() {
    local policy="$1" local_file="$2" expected_file="$3" canonical_source="${4:-}"

    if [[ "$policy" == "canonical_symlink" && -n "$canonical_source" ]]; then
        mkdir -p "$(dirname "$local_file")"
        _profile_ln_s "$canonical_source" "$local_file"
        return 0
    fi

    _profile_replace_file "$expected_file" "$local_file"
}

_profile_sync_local_to_owner() {
    local policy="$1" local_file="$2" owner_source="$3"

    cp "$local_file" "$owner_source"
    if [[ "$policy" == "canonical_symlink" ]]; then
        _profile_ln_s "$owner_source" "$local_file"
    fi
}

# Syncs a config file bidirectionally between profile sources and local target.
# Uses snapshot to detect which side changed. Newer change wins on conflict.
# Returns 0 if no changes, 1 if changes were applied, 2 if user action is still required.
_profile_sync_config_policy() {
    local policy="$1" label="$2" local_file="$3" expected_file="$4"
    shift 4
    local -a profile_sources=("$@")

    local diff_cmd="diff"
    diff --color /dev/null /dev/null 2>/dev/null && diff_cmd="diff --color"

    _profile_analyze_config_sync "$policy" "$local_file" "$expected_file" "${profile_sources[@]}"

    case "$_PROFILE_SYNC_STATE" in
        in_sync)
            return 0
            ;;
        missing_local)
            _profile_apply_sync_target "$policy" "$local_file" "$expected_file" "${profile_sources[1]:-}"
            echo "  $label: created"
            return 1
            ;;
        profile_to_local)
            echo "  $label: profile -> local (auto)"
            { $diff_cmd "$local_file" "$expected_file" 2>/dev/null || true; } | head -30
            _profile_apply_sync_target "$policy" "$local_file" "$expected_file" "${profile_sources[1]:-}"
            return 1
            ;;
        local_to_profile)
            if [[ ${#profile_sources[@]} -eq 1 ]]; then
                echo "  $label: local -> profile (auto)"
                { $diff_cmd "$expected_file" "$local_file" 2>/dev/null || true; } | head -30
                _profile_sync_local_to_owner "$policy" "$local_file" "${profile_sources[1]}"
                echo "  Profile updated"
                return 1
            fi
            echo "  $label: local changes detected, but ownership is ambiguous:"
            printf '    %s\n' "${profile_sources[@]}"
            return 2
            ;;
        blocked_local_output)
            echo "  $label: local changes detected on a merged multi-profile output"
            echo "  Edit the owning profile sources directly, then run 'profile checkpoint' after review."
            return 2
            ;;
        blocked_conflict)
            echo "  $label: CONFLICT — merged profile output changed and local output was also edited"
            { $diff_cmd "$local_file" "$expected_file" 2>/dev/null || true; } | head -60
            echo ""
            echo "    1) Apply merged profile version"
            echo "    2) Open local output in \$EDITOR"
            echo "    3) Skip for now"
            printf "  Choice [3]: "
            local choice answer=""
            if answer=$(_profile_prompt_read); then
                choice="${answer:-3}"
            else
                choice="3"
            fi
            case "$choice" in
                1)
                    _profile_apply_sync_target "$policy" "$local_file" "$expected_file" "${profile_sources[1]:-}"
                    echo "  Applied merged profile version"
                    return 1
                    ;;
                2)
                    ${EDITOR:-vim} "$local_file"
                    echo "  Edited locally"
                    return 2
                    ;;
                *)
                    echo "  Skipped"
                    return 2
                    ;;
            esac
            ;;
        conflict)
            echo "  $label: CONFLICT — both sides changed"
            { $diff_cmd "$local_file" "$expected_file" 2>/dev/null || true; } | head -60
            echo ""

            _sync_mtime() {
                local mtime
                if [[ "$IS_MACOS" == true ]]; then
                    mtime=$(/usr/bin/stat -f %m "$1" 2>/dev/null)
                else
                    mtime=$(stat -c %Y "$1" 2>/dev/null)
                fi
                [[ "$mtime" =~ ^[0-9]+$ ]] && echo "$mtime" || echo 0
            }
            local local_mtime=$(_sync_mtime "$local_file")
            local src_mtime=0
            local src=""
            for src in "${profile_sources[@]}"; do
                local t=$(_sync_mtime "$src")
                [[ $t -gt $src_mtime ]] && src_mtime=$t
            done

            local default_choice=1
            [[ $src_mtime -gt $local_mtime ]] && default_choice=2

            local tag_local="" tag_profile=""
            [[ $local_mtime -ge $src_mtime ]] && tag_local=" (newer)"
            [[ $src_mtime -gt $local_mtime ]] && tag_profile=" (newer)"

            echo "    1) Keep local$tag_local"
            echo "    2) Apply profile$tag_profile"
            echo "    3) Open in \$EDITOR"
            printf "  Choice [%d]: " "$default_choice"
            local choice answer=""
            if answer=$(_profile_prompt_read); then
                choice="${answer:-$default_choice}"
            else
                choice="3"
            fi

            case "$choice" in
                1)
                    if [[ ${#profile_sources[@]} -eq 1 ]]; then
                        _profile_sync_local_to_owner "$policy" "$local_file" "${profile_sources[1]}"
                        echo "  Kept local, updated profile"
                        return 1
                    fi
                    echo "  Kept local (update profile sources manually)"
                    return 2
                    ;;
                2)
                    _profile_apply_sync_target "$policy" "$local_file" "$expected_file" "${profile_sources[1]:-}"
                    echo "  Applied profile version"
                    return 1
                    ;;
                3)
                    ${EDITOR:-vim} "$local_file"
                    echo "  Edited locally"
                    return 2
                    ;;
            esac
            ;;
    esac

    return 0
}

# Syncs a config file bidirectionally between profile sources and local target.
# Uses snapshot to detect which side changed. Newer change wins on conflict.
# Returns 0 if no changes, 1 if changes were applied.
_profile_sync_config() {
    local label="$1" local_file="$2" expected_file="$3"
    shift 3
    _profile_sync_config_policy "single_owner_sync_back" "$label" "$local_file" "$expected_file" "$@"
}

# --- Update helpers ---

_profile_pick_target() {
    local profiles="$1"
    local label="$2"
    local -a candidates=("default")

    for p in ${=profiles}; do
        [[ "$p" != "default" ]] && candidates+=("$p")
    done

    if [[ ${#candidates[@]} -le 1 ]]; then
        echo "${candidates[1]}"
        return 0
    fi

    echo "" >&2
    echo "  Add new ${label} entries to which profile?" >&2
    local i
    for (( i=1; i <= ${#candidates[@]}; i++ )); do
        echo "    $i) ${candidates[$i]}" >&2
    done
    printf "  Choice [%d]: " "${#candidates[@]}" >&2
    local choice
    read -r choice
    [[ -z "$choice" ]] && choice="${#candidates[@]}"

    if [[ "$choice" -ge 1 && "$choice" -le ${#candidates[@]} ]] 2>/dev/null; then
        echo "${candidates[$choice]}"
    else
        echo "  Invalid choice, using ${candidates[${#candidates[@]}]}" >&2
        echo "${candidates[${#candidates[@]}]}"
    fi
}

# --- Sync functions (bidirectional reconciliation) ---

_profile_sync_brew() {
    local profiles="$1"
    local default_brewfile="$PROFILES_DIR/default/Brewfile"
    [[ -f "$default_brewfile" ]] || return 0

    local -a brewfiles=("$default_brewfile")
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        local pf="$PROFILES_DIR/$p/Brewfile"
        [[ -f "$pf" ]] && brewfiles+=("$pf")
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

    if [[ -z "$to_install" && -z "$to_add" ]]; then
        echo "  Brew: in sync"
        return 0
    fi

    echo "  Brew changes:"

    local -a items_to_install=()
    local -a items_to_remove=()
    local -a items_to_add=()
    local -a items_to_uninstall=()
    local had_action=false
    local needs_review=false

    if [[ -n "$to_install" ]]; then
        for pkg in ${(f)to_install}; do
            [[ -z "$pkg" ]] && continue
            local action=$(_profile_prompt_item "$pkg" "not_installed")
            case "$action" in
                install)   items_to_install+=("$pkg"); had_action=true ;;
                remove)    items_to_remove+=("$pkg"); had_action=true ;;
                skip)      needs_review=true ;;
            esac
        done
    fi

    if [[ -n "$to_add" ]]; then
        for pkg in ${(f)to_add}; do
            [[ -z "$pkg" ]] && continue
            local action=$(_profile_prompt_item "brew" "$pkg" "not_in_profile")
            case "$action" in
                add)       items_to_add+=("$pkg"); had_action=true ;;
                uninstall) items_to_uninstall+=("$pkg"); had_action=true ;;
                skip)      ;;
            esac
        done
    fi

    if [[ "$had_action" == false ]]; then
        if [[ "$needs_review" == true ]]; then
            echo "  Review still required."
            return 2
        fi
        echo "  No changes applied."
        return 0
    fi

    if [[ ${#items_to_install[@]} -gt 0 ]]; then
        local tmpfile=$(mktemp)
        local taps=$(echo "$expected" | grep "^tap:" | sed 's/^tap://')
        for t in ${(f)taps}; do
            [[ -n "$t" ]] && echo "tap \"$t\"" >> "$tmpfile"
        done
        for pkg in "${items_to_install[@]}"; do
            local type="${pkg%%:*}" name="${pkg#*:}"
            echo "$type \"$name\"" >> "$tmpfile"
        done
        brew bundle --file="$tmpfile"
        rm -f "$tmpfile"
    fi

    for pkg in "${items_to_remove[@]}"; do
        local type="${pkg%%:*}" name="${pkg#*:}"
        echo "$sourced" | while IFS=$'\t' read -r entry file; do
            [[ "$entry" == "$pkg" && -n "$file" ]] && _profile_remove_brew_line "$file" "$type" "$name"
        done
        echo "  Removed $pkg from profile"
    done

    if [[ ${#items_to_add[@]} -gt 0 ]]; then
        local target_profile=$(_profile_pick_target "$profiles" "Brewfile")
        local target_brewfile="$PROFILES_DIR/$target_profile/Brewfile"
        [[ "$target_profile" == "default" ]] && target_brewfile="$default_brewfile"
        for pkg in "${items_to_add[@]}"; do
            local type="${pkg%%:*}" name="${pkg#*:}"
            echo "$type \"$name\"" >> "$target_brewfile"
        done
        echo "  Added ${#items_to_add[@]} package(s) to $(basename "$(dirname "$target_brewfile")")/Brewfile"
    fi

    for pkg in "${items_to_uninstall[@]}"; do
        local type="${pkg%%:*}" name="${pkg#*:}"
        if [[ "$type" == "cask" ]]; then
            brew uninstall --cask "$name"
        else
            brew uninstall "$name"
        fi
        echo "  Uninstalled $pkg"
    done

    if [[ ${#items_to_install[@]} -gt 0 || ${#items_to_uninstall[@]} -gt 0 ]]; then
        _profile_post_brew
    fi

    if [[ "$needs_review" == true ]]; then
        echo "  Review still required."
        return 2
    fi

    return 1
}

_profile_sync_vscode() {
    local profiles="$1"
    local default_dir="$PROFILES_DIR/default/vscode"
    local overall=0
    local -a instance_rows=("${(@f)$(_profile_vscode_instances)}")

    # --- Extensions (per-item sync) ---
    local default_ext="$default_dir/extensions.txt"
    if [[ ${#instance_rows[@]} -gt 0 ]]; then
        local -a ext_files=()
        [[ -f "$default_ext" ]] && ext_files+=("$default_ext")
        for p in ${=profiles}; do
            [[ "$p" == "default" ]] && continue
            local ef="$PROFILES_DIR/$p/vscode/extensions.txt"
            [[ -f "$ef" ]] && ext_files+=("$ef")
        done

        if [[ ${#ext_files[@]} -gt 0 ]]; then
            local sourced=$(_profile_read_extensions_sourced "${ext_files[@]}")
            local expected=$(echo "$sourced" | cut -f1 | sort -u)

            local instance_row=""
            for instance_row in "${instance_rows[@]}"; do
                local parts=(${(s:|:)instance_row})
                local inst_label="${parts[1]:-}"
                local vscode_user_dir="${parts[2]:-}"
                local cli="${parts[3]:-}"
                [[ -z "$inst_label" || -z "$cli" ]] && continue

                local installed=$("$cli" --list-extensions 2>/dev/null | sort -u)
                local to_install=$(comm -23 <(echo "$expected") <(echo "$installed") | grep -v '^$')
                local to_add=$(comm -23 <(echo "$installed") <(echo "$expected") | grep -v '^$')

                if [[ -n "$to_install" || -n "$to_add" ]]; then
                    echo "  VSCode extension changes ($inst_label):"

                    local -a exts_to_install=()
                    local -a exts_to_remove=()
                    local -a exts_to_add=()
                    local -a exts_to_uninstall=()
                    local had_action=false
                    local needs_review=false
                    local scope="vscode:$inst_label"

                    if [[ -n "$to_install" ]]; then
                        for ext in ${(f)to_install}; do
                            [[ -z "$ext" ]] && continue
                            local action=$(_profile_prompt_item "$ext ($inst_label)" "not_installed")
                            case "$action" in
                                install)   exts_to_install+=("$ext"); had_action=true ;;
                                remove)    exts_to_remove+=("$ext"); had_action=true ;;
                                skip)      needs_review=true ;;
                            esac
                        done
                    fi

                    if [[ -n "$to_add" ]]; then
                        for ext in ${(f)to_add}; do
                            [[ -z "$ext" ]] && continue
                            _profile_sync_skip_contains_any "$ext" "$scope" "vscode" && continue
                            local action=$(_profile_prompt_item "$scope" "$ext" "not_in_profile")
                            case "$action" in
                                add)       exts_to_add+=("$ext"); had_action=true ;;
                                uninstall) exts_to_uninstall+=("$ext"); had_action=true ;;
                                skip)      ;;
                            esac
                        done
                    fi

                    if [[ "$had_action" == false ]]; then
                        if [[ "$needs_review" == true ]]; then
                            echo "  Review still required."
                            overall=$(_profile_sync_merge_status "$overall" 2)
                        else
                            echo "  No changes applied."
                        fi
                    else
                        if [[ ${#exts_to_install[@]} -gt 0 ]]; then
                            for ext in "${exts_to_install[@]}"; do
                                "$cli" --install-extension "$ext" --force 2>/dev/null
                            done
                        fi

                        for ext in "${exts_to_remove[@]}"; do
                            echo "$sourced" | while IFS=$'\t' read -r entry file; do
                                [[ "$entry" == "$ext" && -n "$file" ]] && _profile_remove_line "$file" "^${ext}$"
                            done
                            echo "  Removed $ext from profile"
                        done

                        if [[ ${#exts_to_add[@]} -gt 0 ]]; then
                            local target_profile=$(_profile_pick_target "$profiles" "extensions")
                            local target_ext="$PROFILES_DIR/$target_profile/vscode/extensions.txt"
                            [[ "$target_profile" == "default" || ! -d "$(dirname "$target_ext")" ]] && target_ext="$default_ext"
                            for ext in "${exts_to_add[@]}"; do
                                echo "$ext" >> "$target_ext"
                            done
                        fi

                        for ext in "${exts_to_uninstall[@]}"; do
                            "$cli" --uninstall-extension "$ext" 2>/dev/null || true
                            echo "  Uninstalled $ext"
                        done

                        if [[ "$needs_review" == true ]]; then
                            echo "  Review still required."
                            overall=$(_profile_sync_merge_status "$overall" 2)
                        else
                            overall=$(_profile_sync_merge_status "$overall" 1)
                        fi
                    fi
                else
                    echo "  VSCode extensions ($inst_label): in sync"
                fi
            done
        fi
    fi

    # --- Settings (three-way sync) ---
    local -a settings_files=()
    [[ -f "$default_dir/settings.json" ]] && settings_files+=("$default_dir/settings.json")
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        local pf="$PROFILES_DIR/$p/vscode/settings.json"
        [[ -f "$pf" ]] && settings_files+=("$pf")
    done

    if [[ ${#settings_files[@]} -gt 0 ]]; then
        local expected=$(mktemp)
        if [[ ${#settings_files[@]} -eq 1 ]]; then
            cp "${settings_files[1]}" "$expected"
        else
            jq -s 'reduce .[] as $item ({}; . * $item)' "${settings_files[@]}" > "$expected"
        fi
        local instance_row=""
        for instance_row in "${instance_rows[@]}"; do
            local parts=(${(s:|:)instance_row})
            local inst_label="${parts[1]:-}"
            local vscode_user_dir="${parts[2]:-}"
            [[ -z "$inst_label" ]] && continue
            _profile_sync_config_policy \
                "$(_profile_config_policy structured_copy ${#settings_files[@]})" \
                "VSCode settings ($inst_label)" "$vscode_user_dir/settings.json" "$expected" "${settings_files[@]}"
            overall=$(_profile_sync_merge_status "$overall" "$?")
        done
        rm -f "$expected"
    fi

    # --- Keybindings (three-way sync) ---
    local kb_source=""
    [[ -f "$default_dir/keybindings.json" ]] && kb_source="$default_dir/keybindings.json"
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        [[ -f "$PROFILES_DIR/$p/vscode/keybindings.json" ]] && kb_source="$PROFILES_DIR/$p/vscode/keybindings.json"
    done
    if [[ -n "$kb_source" ]]; then
        local kb_expected=$(mktemp)
        cp "$kb_source" "$kb_expected"
        local instance_row=""
        for instance_row in "${instance_rows[@]}"; do
            local parts=(${(s:|:)instance_row})
            local inst_label="${parts[1]:-}"
            local vscode_user_dir="${parts[2]:-}"
            [[ -z "$inst_label" ]] && continue
            _profile_sync_config_policy \
                "$(_profile_config_policy last_wins 1)" \
                "VSCode keybindings ($inst_label)" "$vscode_user_dir/keybindings.json" "$kb_expected" "$kb_source"
            overall=$(_profile_sync_merge_status "$overall" "$?")
        done
        rm -f "$kb_expected"
    fi

    return "$overall"
}

_profile_sync_mise() {
    local profiles="$1"
    local target="$HOME/.config/mise/config.toml"
    local overall=0

    local -a mise_files=()
    [[ -f "$PROFILES_DIR/default/mise/config.toml" ]] && mise_files+=("$PROFILES_DIR/default/mise/config.toml")
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        local pf="$PROFILES_DIR/$p/mise/config.toml"
        [[ -f "$pf" ]] && mise_files+=("$pf")
    done
    [[ ${#mise_files[@]} -eq 0 ]] && return 0

    # --- Pass 1: Tools section (list-based per-item sync) ---
    local sourced=$(_profile_read_mise_tools_sourced "${mise_files[@]}")
    local expected_tools=$(echo "$sourced" | cut -f1 | sort -u)

    local installed_tools=""
    if command -v mise &>/dev/null; then
        installed_tools=$(mise ls --installed --json 2>/dev/null | jq -r 'keys[]' 2>/dev/null | sort -u)
    fi

    local to_install=$(comm -23 <(echo "$expected_tools") <(echo "$installed_tools") | grep -v '^$')
    local to_add=$(comm -23 <(echo "$installed_tools") <(echo "$expected_tools") | grep -v '^$')

    local tools_changed=false

    if [[ -n "$to_install" || -n "$to_add" ]]; then
        echo "  Mise tool changes:"

        local -a tools_to_install=()
        local -a tools_to_remove=()
        local -a tools_to_add=()
        local -a tools_to_uninstall=()
        local had_action=false
        local needs_review=false

        if [[ -n "$to_install" ]]; then
            for tool in ${(f)to_install}; do
                [[ -z "$tool" ]] && continue
                local action=$(_profile_prompt_item "$tool" "not_installed")
                case "$action" in
                    install)   tools_to_install+=("$tool"); had_action=true ;;
                    remove)    tools_to_remove+=("$tool"); had_action=true ;;
                    skip)      needs_review=true ;;
                esac
            done
        fi

        if [[ -n "$to_add" ]]; then
            for tool in ${(f)to_add}; do
                [[ -z "$tool" ]] && continue
                local action=$(_profile_prompt_item "mise" "$tool" "not_in_profile")
                case "$action" in
                    add)       tools_to_add+=("$tool"); had_action=true ;;
                    uninstall) tools_to_uninstall+=("$tool"); had_action=true ;;
                    skip)      ;;
                esac
            done
        fi

        if [[ "$had_action" == false ]]; then
            if [[ "$needs_review" == true ]]; then
                echo "  Review still required."
                overall=$(_profile_sync_merge_status "$overall" 2)
            else
                echo "  No changes applied."
            fi
        else
            tools_changed=true

            # Remove from profile
            for tool in "${tools_to_remove[@]}"; do
                local escaped=$(_profile_escape_regex "$tool")
                echo "$sourced" | while IFS=$'\t' read -r entry file; do
                    [[ "$entry" == "$tool" && -n "$file" ]] && \
                        _profile_remove_line "$file" "^[[:space:]]*${escaped}[[:space:]]*="
                done
                echo "  Removed $tool from profile"
            done

            # Add to profile
            if [[ ${#tools_to_add[@]} -gt 0 ]]; then
                local target_profile=$(_profile_pick_target "$profiles" "mise tools")
                local target_mise="$PROFILES_DIR/$target_profile/mise/config.toml"
                [[ "$target_profile" == "default" ]] && target_mise="$PROFILES_DIR/default/mise/config.toml"
                # Ensure [tools] section exists
                if ! grep -q '^\[tools\]' "$target_mise" 2>/dev/null; then
                    echo "" >> "$target_mise"
                    echo "[tools]" >> "$target_mise"
                fi
                for tool in "${tools_to_add[@]}"; do
                    echo "$tool = \"latest\"" >> "$target_mise"
                done
            fi

            # Uninstall
            for tool in "${tools_to_uninstall[@]}"; do
                mise uninstall "$tool" 2>/dev/null || true
                echo "  Uninstalled $tool"
            done

            if [[ "$needs_review" == true ]]; then
                echo "  Review still required."
                overall=$(_profile_sync_merge_status "$overall" 2)
            else
                overall=$(_profile_sync_merge_status "$overall" 1)
            fi
        fi
    else
        echo "  Mise tools: in sync"
    fi

    if [[ ${#mise_files[@]} -eq 1 ]]; then
        local source_file="${mise_files[1]}"
        mkdir -p "$(dirname "$target")"

        if [[ ! -e "$target" && ! -L "$target" ]]; then
            _profile_ln_s "$source_file" "$target"
            echo "  Mise config: symlinked -> ${source_file:t}"
        elif _profile_symlink_matches "$target" "$source_file"; then
            echo "  Mise config: in sync (symlinked)"
        elif [[ -L "$target" ]]; then
            _profile_ln_s "$source_file" "$target"
            echo "  Mise config: symlinked -> ${source_file:t}"
        else
            _profile_sync_config_policy \
                "$(_profile_config_policy structured_canonical 1)" \
                "Mise config" "$target" "$source_file" "$source_file"
            overall=$(_profile_sync_merge_status "$overall" "$?")

            if [[ "$(_platform_md5 "$target")" == "$(_platform_md5 "$source_file")" ]]; then
                _profile_ln_s "$source_file" "$target"
                echo "  Mise config: symlinked -> ${source_file:t}"
            else
                echo "  Mise config: kept local file"
            fi
        fi

        if [[ "$tools_changed" == true ]] && command -v mise &>/dev/null; then
            echo "  Running mise install..."
            mise install
        fi
        return "$overall"
    fi

    # --- Pass 2: Non-tools sections (three-way merge) ---
    local expected_rest=$(mktemp)
    local -A sections
    local -a section_order=()
    local current_section="_top"
    for f in "${mise_files[@]}"; do
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" == \[* ]]; then
                current_section="$line"
                if [[ "$current_section" != "[tools]" ]]; then
                    local found=false
                    for s in "${section_order[@]}"; do
                        [[ "$s" == "$current_section" ]] && found=true && break
                    done
                    [[ "$found" == false ]] && section_order+=("$current_section")
                fi
            elif [[ -n "$line" && "$current_section" != "[tools]" ]]; then
                sections[$current_section]+="$line"$'\n'
            fi
        done < "$f"
    done

    if [[ ${#section_order[@]} -gt 0 || -n "${sections[_top]:-}" ]]; then
        {
            [[ -n "${sections[_top]:-}" ]] && printf '%s' "${sections[_top]}"
            for section in "${section_order[@]}"; do
                echo "$section"
                local -A seen_keys=()
                local -a ordered_lines=()
                while IFS= read -r line; do
                    [[ -z "$line" ]] && continue
                    local key="${line%%=*}"
                    key="${key%% }"
                    if [[ -n "${seen_keys[$key]+x}" ]]; then
                        ordered_lines[${seen_keys[$key]}]="$line"
                    else
                        ordered_lines+=("$line")
                        seen_keys[$key]="${#ordered_lines}"
                    fi
                done <<< "${sections[$section]}"
                printf '%s\n' "${ordered_lines[@]}"
                echo ""
            done
        } > "$expected_rest"

        local target_rest=$(mktemp)
        if [[ -f "$target" ]]; then
            local dummy_tools=$(mktemp)
            _profile_mise_split_tools "$target" "$dummy_tools" "$target_rest"
            rm -f "$dummy_tools"
        else
            : > "$target_rest"
        fi

        local -a rest_sources=()
        for f in "${mise_files[@]}"; do
            local src_tools_tmp=$(mktemp)
            local src_rest_tmp=$(mktemp)
            _profile_mise_split_tools "$f" "$src_tools_tmp" "$src_rest_tmp"
            rest_sources+=("$src_rest_tmp")
            rm -f "$src_tools_tmp"
        done

        mkdir -p "$(dirname "$target")"
        _profile_sync_config_policy \
            "$(_profile_config_policy structured_copy ${#rest_sources[@]})" \
            "Mise settings" "$target_rest" "$expected_rest" "${rest_sources[@]}"
        local result=$?
        overall=$(_profile_sync_merge_status "$overall" "$result")

        if [[ $result -ne 0 ]]; then
            for (( idx=1; idx <= ${#mise_files[@]}; idx++ )); do
                local orig="${mise_files[$idx]}"
                local rest_src="${rest_sources[$idx]}"
                local orig_tools=$(mktemp)
                local orig_rest=$(mktemp)
                _profile_mise_split_tools "$orig" "$orig_tools" "$orig_rest"
                { [[ -s "$rest_src" ]] && cat "$rest_src"; echo "[tools]"; cat "$orig_tools"; } > "$orig"
                rm -f "$orig_tools" "$orig_rest" "$rest_src"
            done
        else
            rm -f "${rest_sources[@]}"
        fi

        # Reassemble full target
        {
            cat "$target_rest"
            echo "[tools]"
            for f in "${mise_files[@]}"; do
                local tools_tmp=$(mktemp)
                local rest_tmp=$(mktemp)
                _profile_mise_split_tools "$f" "$tools_tmp" "$rest_tmp"
                cat "$tools_tmp"
                rm -f "$tools_tmp" "$rest_tmp"
            done
        } > "$target"

        rm -f "$expected_rest" "$target_rest"
    else
        mkdir -p "$(dirname "$target")"
        {
            echo "[tools]"
            for f in "${mise_files[@]}"; do
                local tools_tmp=$(mktemp)
                local rest_tmp=$(mktemp)
                _profile_mise_split_tools "$f" "$tools_tmp" "$rest_tmp"
                cat "$tools_tmp"
                rm -f "$tools_tmp" "$rest_tmp"
            done
        } > "$target"
    fi

    # Run mise install if tools changed
    if [[ "$tools_changed" == true ]] && command -v mise &>/dev/null; then
        echo "  Running mise install..."
        mise install
    fi

    return "$overall"
}

_profile_sync_claude() {
    local profiles="$1"
    local overall=0

    mkdir -p "$HOME/.claude"
    _profile_sync_structured_profile_config \
        "Claude" "$profiles" "claude" "settings.json" "$HOME/.claude" "json"
    overall=$(_profile_sync_merge_status "$overall" "$?")
    _profile_claude_link_files "$profiles" sync
    overall=$(_profile_sync_merge_status "$overall" "$?")
    _profile_link_union_file_collection "$profiles" "claude" "hooks" "*" "$HOME/.claude" "sync" "Hooks"
    overall=$(_profile_sync_merge_status "$overall" "$?")
    _profile_link_union_file_collection "$profiles" "claude" "commands" "*.md" "$HOME/.claude" "sync" "Commands"
    overall=$(_profile_sync_merge_status "$overall" "$?")
    return "$overall"
}

_profile_sync_codex() {
    local profiles="$1"
    local overall=0

    mkdir -p "$HOME/.codex"

    _profile_sync_structured_profile_config \
        "Codex config" "$profiles" "codex" "config.toml" "$HOME/.codex" "toml"
    overall=$(_profile_sync_merge_status "$overall" "$?")
    _profile_sync_structured_profile_config \
        "Codex hooks" "$profiles" "codex" "hooks.json" "$HOME/.codex" "json"
    overall=$(_profile_sync_merge_status "$overall" "$?")

    local rules_source=$(_profile_codex_resolve_source "$profiles" "rules/default.rules")
    if [[ -n "$rules_source" ]]; then
        mkdir -p "$HOME/.codex/rules"
        _profile_sync_config_policy \
            "$(_profile_config_policy last_wins 1)" \
            "Codex rules" "$HOME/.codex/rules/default.rules" "$rules_source" "$rules_source"
        overall=$(_profile_sync_merge_status "$overall" "$?")
    fi

    _profile_link_union_file_collection "$profiles" "codex" "hooks" "*" "$HOME/.codex" "sync" "Hooks"
    overall=$(_profile_sync_merge_status "$overall" "$?")
    _profile_link_union_file_collection "$profiles" "codex" "agents" "*.toml" "$HOME/.codex" "sync" "Agents"
    overall=$(_profile_sync_merge_status "$overall" "$?")
    _profile_ensure_derived_symlink "AGENTS.md" "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md" "sync"
    overall=$(_profile_sync_merge_status "$overall" "$?")
    return "$overall"
}

# --- Skills (cross-agent routing) ---

# Ingest a single orphan skill directory into profiles/default/skills/shared/.
# Moves the directory, scaffolds agents/openai.yaml, and creates a symlink back.
# Usage: _profile_ingest_single_skill <skill_dir> [agent_name]
# Returns 0 on success, 1 if skipped.
_profile_ingest_single_skill() {
    local skill_dir="$1"
    local agent_name="${2:-unknown}"
    local skill_name="${skill_dir:t}"

    # Validate: must be a real directory with SKILL.md
    [[ -d "$skill_dir" && ! -L "$skill_dir" ]] || return 1
    [[ "$skill_name" == .system ]] && return 1
    [[ -f "$skill_dir/SKILL.md" ]] || return 1

    # Already exists in a profile — do not overwrite
    local profile_dir=""
    for profile_dir in "$PROFILES_DIR"/*(N/); do
        if [[ -d "$profile_dir/skills/shared/$skill_name" || -d "$profile_dir/skills/claude/$skill_name" || -d "$profile_dir/skills/codex/$skill_name" ]]; then
            return 1
        fi
    done

    # Ingest: move to profiles/default/skills/shared/
    local target="$PROFILES_DIR/default/skills/shared/$skill_name"
    mkdir -p "$PROFILES_DIR/default/skills/shared"
    mv "$skill_dir" "$target"

    # Scaffold agents/openai.yaml if missing
    if [[ ! -f "$target/agents/openai.yaml" ]]; then
        local display_name="" short_desc=""
        # Extract from SKILL.md frontmatter
        if head -1 "$target/SKILL.md" | grep -q '^---'; then
            display_name=$(sed -n '/^---$/,/^---$/{ /^name:/{ s/^name:[[:space:]]*//; p; q; } }' "$target/SKILL.md")
            short_desc=$(sed -n '/^---$/,/^---$/{
                /^description:/{
                    s/^description:[[:space:]]*>\{0,1\}[[:space:]]*//
                    /./{ p; q; }
                    n
                    s/^[[:space:]]*//
                    p; q
                }
            }' "$target/SKILL.md")
        fi
        # Fallback to skill name
        [[ -z "$display_name" ]] && display_name="$skill_name"
        [[ -z "$short_desc" ]] && short_desc="$skill_name skill"
        # Titlecase the display name (foo-bar -> Foo Bar)
        display_name="${display_name//-/ }"
        display_name="${(C)display_name}"

        mkdir -p "$target/agents"
        cat > "$target/agents/openai.yaml" <<YAML
interface:
  display_name: "$display_name"
  short_description: "$short_desc"
  default_prompt: "Use \$$skill_name to run the $display_name workflow."
YAML
    fi

    # Symlink back so the agent can still find it at the original location
    local parent_dir="${skill_dir:h}"
    mkdir -p "$parent_dir"
    _profile_ln_sn "$target" "$skill_dir"

    echo "  Skills: ingested $skill_name from $agent_name -> shared"
    return 0
}

# Ingest orphan skills: non-symlink directories in agent skill roots that are not
# yet tracked by any profile. Moves them into profiles/default/skills/shared/ and
# scaffolds agents/openai.yaml so all agents can use them.
_profile_ingest_orphan_skills() {
    local -A agent_roots=(
        [claude]="$HOME/.claude"
        [codex]="$HOME/.codex"
    )
    local -A seen_orphans=()  # skill_name -> agent that claimed it

    local agent_name=""
    for agent_name in claude codex; do
        local skills_dir="${agent_roots[$agent_name]}/skills"
        [[ -d "$skills_dir" ]] || continue

        local entry=""
        for entry in "$skills_dir"/*(N/); do
            [[ -L "$entry" ]] && continue  # already a symlink, skip
            local skill_name="${entry:t}"
            [[ "$skill_name" == .system ]] && continue

            # Already claimed by another agent root this pass
            if (( ${+seen_orphans[$skill_name]} )); then
                echo "  Skills: skipped orphan $skill_name in $agent_name (already ingested from ${seen_orphans[$skill_name]})"
                continue
            fi

            if _profile_ingest_single_skill "$entry" "$agent_name"; then
                seen_orphans[$skill_name]="$agent_name"
            fi
        done
    done
}

_profile_skills_link() {
    local profiles="$1" mode="$2"
    # Known agent roots for skill routing. Add new agents here.
    local -A agent_roots=(
        [claude]="$HOME/.claude"
        [codex]="$HOME/.codex"
    )
    local -a all_agents=(${(k)agent_roots})
    local -a linked_skills=()
    local -a skipped_skills=()
    local collection_changed=false
    local collection_blocked=false

    # Migrate: if any agent skills dir is a symlink (old derived-symlink model), replace with real dir
    local agent_name=""
    for agent_name in "${all_agents[@]}"; do
        local agent_skills="${agent_roots[$agent_name]}/skills"
        if [[ -L "$agent_skills" ]]; then
            rm "$agent_skills"
            mkdir -p "$agent_skills"
            collection_changed=true
        else
            mkdir -p "$agent_skills"
        fi
    done

    # Collect all audience dirs across profiles
    local -A audience_sources=()  # audience/skill_name -> source_path (last profile wins)
    local profile_name=""
    local -a profile_list=(default)
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
                local skill_key="${audience}/${skill_name}"
                audience_sources[$skill_key]="$skill_dir"
            done
        done
    done

    [[ ${#audience_sources} -eq 0 ]] && return 0

    # Route each skill to target agents
    local key=""
    for key in ${(ok)audience_sources}; do
        local audience="${key%%/*}"
        local skill_name="${key#*/}"
        local source_dir="${audience_sources[$key]}"

        # Determine target agents
        local -a targets=()
        if [[ "$audience" == "shared" ]]; then
            targets=("${all_agents[@]}")
        elif (( ${+agent_roots[$audience]} )); then
            targets=("$audience")
        else
            echo "  Skills: warning: unknown audience '$audience', skipping $skill_name"
            continue
        fi

        linked_skills+=("$skill_name:$audience")

        local target_agent=""
        for target_agent in "${targets[@]}"; do
            local target_dir="${agent_roots[$target_agent]}/skills/$skill_name"
            if [[ "$mode" == "sync" ]] && _profile_symlink_matches "$target_dir" "$source_dir"; then
                continue
            fi
            if ! _profile_prepare_link_target "$target_dir"; then
                echo "  Skills: skipped $skill_name -> $target_agent (conflicting directory)"
                skipped_skills+=("$skill_name:$target_agent")
                collection_blocked=true
                continue
            fi
            _profile_ln_sn "$source_dir" "$target_dir"
            collection_changed=true
        done
    done

    if [[ ${#linked_skills[@]} -eq 0 ]]; then
        return 0
    fi

    if [[ "$mode" == "sync" ]]; then
        if [[ "$collection_changed" == true ]]; then
            echo "  Skills: updated (${(j:, :)linked_skills})"
        else
            echo "  Skills: in sync (${(j:, :)linked_skills})"
        fi
    else
        echo "  Skills: ${(j:, :)linked_skills}"
    fi
    if [[ ${#skipped_skills[@]} -gt 0 ]]; then
        echo "  Skills: skipped conflicting directories (${(j:, :)skipped_skills})"
    fi
    if [[ "$collection_blocked" == true ]]; then
        return 2
    fi
    if [[ "$collection_changed" == true ]]; then
        return 1
    fi
    return 0
}

_profile_sync_skills() {
    _profile_ingest_orphan_skills
    _profile_skills_link "$1" "sync"
    return $?
}

_profile_apply_skills() {
    _profile_ingest_orphan_skills
    _profile_skills_link "$1" "apply"
}

_profile_sync_tmux() {
    local profiles="$1"
    local target="$HOME/.tmux.conf"

    # Last profile wins
    local source=""
    [[ -f "$PROFILES_DIR/default/tmux/tmux.conf" ]] && source="$PROFILES_DIR/default/tmux/tmux.conf"
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        [[ -f "$PROFILES_DIR/$p/tmux/tmux.conf" ]] && source="$PROFILES_DIR/$p/tmux/tmux.conf"
    done
    [[ -z "$source" ]] && return 0

    _profile_sync_config_policy \
        "$(_profile_config_policy last_wins 1)" \
        "Tmux" "$target" "$source" "$source"
    return $?
}

_profile_sync_iterm() {
    local profiles="$1"
    local dynamic_dir="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
    local target="$dynamic_dir/dotfiles.json"

    [[ -d "$HOME/Library/Application Support/iTerm2" ]] || return 0

    local -a iterm_files=()
    [[ -f "$PROFILES_DIR/default/iterm/profile.json" ]] && iterm_files+=("$PROFILES_DIR/default/iterm/profile.json")
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        local pf="$PROFILES_DIR/$p/iterm/profile.json"
        [[ -f "$pf" ]] && iterm_files+=("$pf")
    done
    [[ ${#iterm_files[@]} -eq 0 ]] && return 0

    mkdir -p "$dynamic_dir"
    local expected=$(mktemp)
    if [[ ${#iterm_files[@]} -eq 1 ]]; then
        cp "${iterm_files[1]}" "$expected"
    else
        jq -s 'reduce .[] as $item ({}; {"Profiles": [(.Profiles[0] // {}) * ($item.Profiles[0] // {})]})' \
            "${iterm_files[@]}" > "$expected"
    fi

    _profile_sync_config_policy \
        "$(_profile_config_policy structured_copy ${#iterm_files[@]})" \
        "iTerm" "$target" "$expected" "${iterm_files[@]}"
    local result=$?
    rm -f "$expected"
    return $result
}
