# Profile system - bidirectional sync (three-way merge)

# --- Three-way sync helper ---

# Syncs a config file bidirectionally between profile sources and local target.
# Uses snapshot to detect which side changed. Newer change wins on conflict.
# Returns 0 if no changes, 1 if changes were applied.
_profile_sync_config() {
    local label="$1" local_file="$2" expected_file="$3"
    shift 3
    local -a profile_sources=("$@")

    local diff_cmd="diff"
    diff --color /dev/null /dev/null 2>/dev/null && diff_cmd="diff --color"

    local expected_hash=$(_platform_md5 "$expected_file")
    local local_hash=""
    if [[ -f "$local_file" ]]; then
        local real="$local_file"
        [[ -L "$local_file" ]] && real=$(readlink "$local_file")
        local_hash=$(_platform_md5 "$real")
    fi

    # Already in sync
    [[ "$local_hash" == "$expected_hash" ]] && return 0

    # No local file yet — just apply
    if [[ ! -f "$local_file" ]]; then
        mkdir -p "$(dirname "$local_file")"
        cp "$expected_file" "$local_file"
        echo "  $label: created"
        return 1
    fi

    local snap_hash=$(_profile_local_snap_hash "$local_file")
    local profile_changed=false local_changed=false

    if [[ -z "$snap_hash" ]]; then
        # No snapshot yet — default to profile->local (like first use)
        profile_changed=true
    else
        [[ "$expected_hash" != "$snap_hash" ]] && profile_changed=true
        [[ "$local_hash" != "$snap_hash" ]] && local_changed=true
    fi

    if [[ "$profile_changed" == true && "$local_changed" == false ]]; then
        echo "  $label: profile -> local"
        { $diff_cmd "$local_file" "$expected_file" 2>/dev/null || true; } | head -50
        printf "  Apply? [Y/n] "
        local answer; read -r answer
        [[ "$answer" == [nN]* ]] && return 0
        cp "$expected_file" "$local_file"
        return 1

    elif [[ "$profile_changed" == false && "$local_changed" == true ]]; then
        echo "  $label: local -> profile"
        { $diff_cmd "$expected_file" "$local_file" 2>/dev/null || true; } | head -50
        if [[ ${#profile_sources[@]} -eq 1 ]]; then
            printf "  Update profile? [Y/n] "
            local answer; read -r answer
            [[ "$answer" == [nN]* ]] && return 0
            cp "$local_file" "${profile_sources[1]}"
            echo "  Profile updated"
        else
            echo "  Multiple profile sources — edit directly:"
            printf '    %s\n' "${profile_sources[@]}"
        fi
        return 1

    elif [[ "$profile_changed" == true && "$local_changed" == true ]]; then
        echo "  $label: CONFLICT — both sides changed"
        { $diff_cmd "$local_file" "$expected_file" 2>/dev/null || true; } | head -60
        echo ""

        # Determine newer by mtime (handle both GNU and BSD stat)
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
        local choice; read -r choice
        choice="${choice:-$default_choice}"

        case "$choice" in
            1)
                if [[ ${#profile_sources[@]} -eq 1 ]]; then
                    cp "$local_file" "${profile_sources[1]}"
                    echo "  Kept local, updated profile"
                else
                    echo "  Kept local (update profile sources manually)"
                fi
                ;;
            2) cp "$expected_file" "$local_file"; echo "  Applied profile version" ;;
            3) ${EDITOR:-vim} "$local_file"; echo "  Edited locally" ;;
        esac
        return 1
    fi

    return 0
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
    local expected=$(_profile_read_brew_packages "${brewfiles[@]}")
    local expected_no_tap=$(echo "$expected" | grep -v "^tap:")

    local current_formulae=$(brew leaves 2>/dev/null | sort)
    local current_casks=$(brew list --cask 2>/dev/null | sort)
    local installed=$( (echo "$current_formulae" | sed '/^$/d' | sed 's/^/brew:/'; echo "$current_casks" | sed '/^$/d' | sed 's/^/cask:/') | sort -u)

    # New in profile but not installed -> install
    local to_install=$(comm -23 <(echo "$expected_no_tap") <(echo "$installed") | grep -v '^$')
    # Installed but not in profile -> add to profile
    local to_add=$(comm -23 <(echo "$installed") <(echo "$expected_no_tap") | grep -v '^$')

    if [[ -z "$to_install" && -z "$to_add" ]]; then
        echo "  Brew: in sync"
        return 0
    fi

    echo "  Brew changes:"
    [[ -n "$to_install" ]] && echo "$to_install" | sed 's/^/    install: /'
    [[ -n "$to_add" ]] && echo "$to_add" | sed 's/^/    add to profile: /'
    printf "  Apply? [Y/n] "
    local answer; read -r answer
    [[ "$answer" == [nN]* ]] && return 0

    if [[ -n "$to_install" ]]; then
        local tmpfile=$(mktemp)
        cat "$default_brewfile" > "$tmpfile"
        for p in ${=profiles}; do
            [[ "$p" == "default" ]] && continue
            local pf="$PROFILES_DIR/$p/Brewfile"
            [[ -f "$pf" ]] && { echo ""; cat "$pf"; } >> "$tmpfile"
        done
        brew bundle --file="$tmpfile"
        rm -f "$tmpfile"
    fi

    if [[ -n "$to_add" ]]; then
        local target_profile=$(_profile_pick_target "$profiles" "Brewfile")
        local target_brewfile="$PROFILES_DIR/$target_profile/Brewfile"
        [[ "$target_profile" == "default" ]] && target_brewfile="$default_brewfile"
        for pkg in ${(f)to_add}; do
            local type="${pkg%%:*}" name="${pkg#*:}"
            echo "$type \"$name\"" >> "$target_brewfile"
        done
        echo "  Added to $(basename "$(dirname "$target_brewfile")")/Brewfile"
    fi

    _profile_post_brew
}

_profile_sync_vscode() {
    local profiles="$1"
    local default_dir="$PROFILES_DIR/default/vscode"

    # --- Extensions (bidirectional merge) ---
    local default_ext="$default_dir/extensions.txt"
    local instances=$(_profile_vscode_instances)

    if [[ -n "$instances" ]]; then
        local -a ext_files=()
        [[ -f "$default_ext" ]] && ext_files+=("$default_ext")
        for p in ${=profiles}; do
            [[ "$p" == "default" ]] && continue
            local ef="$PROFILES_DIR/$p/vscode/extensions.txt"
            [[ -f "$ef" ]] && ext_files+=("$ef")
        done

        if [[ ${#ext_files[@]} -gt 0 ]]; then
            local expected=$(_profile_read_extensions "${ext_files[@]}")

            local -a all_installed=()
            while IFS='|' read -r _label _dir cli; do
                [[ -z "$_label" ]] && continue
                while IFS= read -r ext; do
                    [[ -n "$ext" ]] && all_installed+=("$ext")
                done < <("$cli" --list-extensions 2>/dev/null)
            done <<< "$instances"
            local installed=$(printf '%s\n' "${all_installed[@]}" | sort -u)

            local to_install=$(comm -23 <(echo "$expected") <(echo "$installed") | grep -v '^$')
            local to_add=$(comm -23 <(echo "$installed") <(echo "$expected") | grep -v '^$')

            if [[ -n "$to_install" || -n "$to_add" ]]; then
                echo "  VSCode extension changes:"
                [[ -n "$to_install" ]] && echo "$to_install" | sed 's/^/    install: /'
                [[ -n "$to_add" ]] && echo "$to_add" | sed 's/^/    add to profile: /'
                printf "  Apply? [Y/n] "
                local answer; read -r answer
                if [[ "$answer" != [nN]* ]]; then
                    if [[ -n "$to_install" ]]; then
                        while IFS='|' read -r _label _dir cli; do
                            [[ -z "$_label" ]] && continue
                            for ext in ${(f)to_install}; do
                                "$cli" --install-extension "$ext" --force 2>/dev/null
                            done
                        done <<< "$instances"
                    fi
                    if [[ -n "$to_add" ]]; then
                        local target_profile=$(_profile_pick_target "$profiles" "extensions")
                        local target_ext="$PROFILES_DIR/$target_profile/vscode/extensions.txt"
                        [[ "$target_profile" == "default" || ! -d "$(dirname "$target_ext")" ]] && target_ext="$default_ext"
                        for ext in ${(f)to_add}; do
                            echo "$ext" >> "$target_ext"
                        done
                    fi
                fi
            else
                echo "  VSCode extensions: in sync"
            fi
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
        while IFS='|' read -r inst_label vscode_user_dir _cli; do
            [[ -z "$inst_label" ]] && continue
            _profile_sync_config "VSCode settings ($inst_label)" "$vscode_user_dir/settings.json" "$expected" "${settings_files[@]}"
        done <<< "$instances"
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
        while IFS='|' read -r inst_label vscode_user_dir _cli; do
            [[ -z "$inst_label" ]] && continue
            _profile_sync_config "VSCode keybindings ($inst_label)" "$vscode_user_dir/keybindings.json" "$kb_expected" "$kb_source"
        done <<< "$instances"
        rm -f "$kb_expected"
    fi
}

_profile_sync_mise() {
    local profiles="$1"
    local target="$HOME/.config/mise/config.toml"

    local -a mise_files=()
    [[ -f "$PROFILES_DIR/default/mise/config.toml" ]] && mise_files+=("$PROFILES_DIR/default/mise/config.toml")
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        local pf="$PROFILES_DIR/$p/mise/config.toml"
        [[ -f "$pf" ]] && mise_files+=("$pf")
    done
    [[ ${#mise_files[@]} -eq 0 ]] && return 0

    # Generate expected merged TOML
    local expected=$(mktemp)
    local -A sections
    local current_section="_top"
    for f in "${mise_files[@]}"; do
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" =~ '^\[' ]]; then
                current_section="$line"
            elif [[ -n "$line" ]]; then
                sections[$current_section]+="$line"$'\n'
            fi
        done < "$f"
    done
    {
        for section in "${(@k)sections}"; do
            [[ "$section" != "_top" ]] && echo "$section"
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
    } > "$expected"

    mkdir -p "$(dirname "$target")"
    _profile_sync_config "Mise" "$target" "$expected" "${mise_files[@]}"
    local result=$?
    rm -f "$expected"

    if [[ $result -ne 0 ]] && command -v mise &>/dev/null; then
        echo "  Running mise install..."
        mise install
    fi
}

_profile_sync_claude() {
    local profiles="$1"
    local target="$HOME/.claude/settings.json"

    local -a settings_files=()
    [[ -f "$PROFILES_DIR/default/claude/settings.json" ]] && settings_files+=("$PROFILES_DIR/default/claude/settings.json")
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        local pf="$PROFILES_DIR/$p/claude/settings.json"
        [[ -f "$pf" ]] && settings_files+=("$pf")
    done
    [[ ${#settings_files[@]} -eq 0 ]] && return 0

    mkdir -p "$HOME/.claude"

    if [[ ${#settings_files[@]} -eq 1 ]]; then
        # Single source: symlink keeps it in sync automatically
        if [[ -L "$target" && "$(readlink "$target")" == "${settings_files[1]}" ]]; then
            echo "  Claude: in sync (symlinked)"
        else
            ln -sf "${settings_files[1]}" "$target"
            echo "  Claude: symlinked -> ${settings_files[1]##*/}"
        fi
    else
        local expected=$(mktemp)
        jq -s 'reduce .[] as $item ({}; . * $item)' "${settings_files[@]}" > "$expected"
        _profile_sync_config "Claude" "$target" "$expected" "${settings_files[@]}"
        rm -f "$expected"
    fi
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

    _profile_sync_config "iTerm" "$target" "$expected" "${iterm_files[@]}"
    rm -f "$expected"
}
