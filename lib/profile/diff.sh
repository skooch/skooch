# Profile system - diff/preview (what switch would change)

_profile_diff_structured_profile_config() {
    local profiles="$1" domain="$2" relative_path="$3" target_root="$4" format="$5" header="$6" diff_cmd="$7"
    local -a source_files=()
    local source_file=""

    while IFS= read -r source_file; do
        [[ -n "$source_file" ]] && source_files+=("$source_file")
    done < <(_profile_collect_domain_file_sources "$profiles" "$domain" "$relative_path")
    [[ ${#source_files[@]} -eq 0 ]] && return 1

    local target_file="$target_root/$relative_path"
    local expected_file=""
    local cleanup_expected=false

    if [[ ${#source_files[@]} -eq 1 ]]; then
        expected_file="${source_files[1]}"
    else
        expected_file=$(mktemp)
        cleanup_expected=true
        _profile_merge_structured_files "$format" "$expected_file" "${source_files[@]}" || {
            rm -f "$expected_file"
            return 1
        }
    fi

    if [[ -f "$target_file" || -L "$target_file" ]]; then
        local result=$($diff_cmd "$target_file" "$expected_file" 2>/dev/null)
        if [[ -n "$result" ]]; then
            echo "=== $header ==="
            echo "$result"
            echo ""
            [[ "$cleanup_expected" == true ]] && rm -f "$expected_file"
            return 0
        fi
    else
        echo "=== $header ==="
        echo "  (new file would be created)"
        echo ""
        [[ "$cleanup_expected" == true ]] && rm -f "$expected_file"
        return 0
    fi

    [[ "$cleanup_expected" == true ]] && rm -f "$expected_file"
    return 1
}

_profile_diff_last_wins_paths() {
    local profiles="$1" domain="$2" target_root="$3" label_prefix="$4" diff_cmd="$5"
    shift 5

    local diff_found=false
    local relative_path=""
    for relative_path in "$@"; do
        local source_file=$(_profile_resolve_last_wins_source "$profiles" "$domain" "$relative_path")
        [[ -z "$source_file" ]] && continue

        local target_file="$target_root/$relative_path"
        if [[ -f "$target_file" || -L "$target_file" ]]; then
            local real_target="$target_file"
            [[ -L "$target_file" ]] && real_target=$(readlink "$target_file")
            if [[ "$real_target" != "$source_file" ]]; then
                local result=$($diff_cmd "$target_file" "$source_file" 2>/dev/null)
                if [[ -n "$result" ]]; then
                    echo "=== $label_prefix/$relative_path ($target_file) ==="
                    echo "$result"
                    echo ""
                    diff_found=true
                fi
            fi
        else
            echo "=== $label_prefix/$relative_path ($target_file) ==="
            echo "  (new file would be created)"
            echo ""
            diff_found=true
        fi
    done

    [[ "$diff_found" == true ]]
}

_profile_diff_union_file_collection() {
    local profiles="$1" domain="$2" relative_dir="$3" glob_pattern="$4" target_root="$5" label_prefix="$6" diff_cmd="$7"
    local diff_found=false
    local basename="" source_file=""

    while IFS=$'\t' read -r basename source_file; do
        [[ -z "$basename" || -z "$source_file" ]] && continue
        local target_file="$target_root/$relative_dir/$basename"
        if [[ -f "$target_file" || -L "$target_file" ]]; then
            local real_target="$target_file"
            [[ -L "$target_file" ]] && real_target=$(readlink "$target_file")
            if [[ "$real_target" != "$source_file" ]]; then
                local result=$($diff_cmd "$target_file" "$source_file" 2>/dev/null)
                if [[ -n "$result" ]]; then
                    echo "=== $label_prefix/$basename ==="
                    echo "$result"
                    echo ""
                    diff_found=true
                fi
            fi
        else
            echo "=== $label_prefix/$basename ==="
            echo "  (new file would be created)"
            echo ""
            diff_found=true
        fi
    done < <(_profile_collect_union_file_sources "$profiles" "$domain" "$relative_dir" "$glob_pattern")

    [[ "$diff_found" == true ]]
}

_profile_diff_union_dir_collection() {
    local profiles="$1" domain="$2" relative_dir="$3" target_root="$4" label_prefix="$5"
    local diff_found=false
    local dirname="" source_dir=""

    while IFS=$'\t' read -r dirname source_dir; do
        [[ -z "$dirname" || -z "$source_dir" ]] && continue
        local target_dir="$target_root/$relative_dir/$dirname"
        if [[ -d "$target_dir" || -L "$target_dir" ]]; then
            local real_target="$target_dir"
            [[ -L "$target_dir" ]] && real_target=$(readlink "$target_dir")
            if [[ "$real_target" != "$source_dir" ]]; then
                echo "=== $label_prefix/$dirname ==="
                echo "  symlink target differs: $real_target -> $source_dir"
                echo ""
                diff_found=true
            fi
        else
            echo "=== $label_prefix/$dirname ==="
            echo "  (new directory would be linked)"
            echo ""
            diff_found=true
        fi
    done < <(_profile_collect_union_dir_sources "$profiles" "$domain" "$relative_dir")

    [[ "$diff_found" == true ]]
}

_profile_diff_derived_symlink() {
    local header="$1" source_file="$2" target_file="$3"

    [[ ! -e "$source_file" && ! -L "$source_file" ]] && return 1

    if [[ -L "$target_file" && "$(readlink "$target_file")" == "$source_file" ]]; then
        return 1
    fi

    echo "=== $header ==="
    if [[ -L "$target_file" ]]; then
        echo "  symlink target differs: $(readlink "$target_file") -> $source_file"
    else
        echo "  (new file would be linked)"
    fi
    echo ""
    return 0
}

_profile_diff() {
    local profiles="$1"
    local has_diff=false
    local diff_cmd="diff"
    local result=""
    diff --color /dev/null /dev/null 2>/dev/null && diff_cmd="diff --color"

    # Git
    local has_git=false
    [[ -f "$PROFILES_DIR/default/git/config" ]] && has_git=true
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        [[ -f "$PROFILES_DIR/$p/git/config" ]] && has_git=true
    done
    if [[ "$has_git" == "true" ]]; then
        local target="$HOME/.gitconfig"
        local tmpfile=$(mktemp)
        local content=""
        if [[ -f "$PROFILES_DIR/default/git/config" ]]; then
            content+="[include]"$'\n'
            content+="	path = $PROFILES_DIR/default/git/config"$'\n'
        fi
        for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
            if [[ -f "$PROFILES_DIR/$p/git/config" ]]; then
                content+="[include]"$'\n'
                content+="	path = $PROFILES_DIR/$p/git/config"$'\n'
            fi
        done
        printf '%s' "$content" > "$tmpfile"
        result=$($diff_cmd "$target" "$tmpfile" 2>/dev/null)
        if [[ -n "$result" ]]; then
            echo "=== git (~/.gitconfig) ==="
            echo "$result"
            echo ""
            has_diff=true
        fi
        rm -f "$tmpfile"
    fi

    # Mise
    local has_mise=false
    [[ -f "$PROFILES_DIR/default/mise/config.toml" ]] && has_mise=true
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        [[ -f "$PROFILES_DIR/$p/mise/config.toml" ]] && has_mise=true
    done
    if [[ "$has_mise" == "true" ]]; then
        local target="$HOME/.config/mise/config.toml"
        local tmpfile=$(mktemp)
        local -a diff_mise_files=()
        [[ -f "$PROFILES_DIR/default/mise/config.toml" ]] && diff_mise_files+=("$PROFILES_DIR/default/mise/config.toml")
        for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
            local pf="$PROFILES_DIR/$p/mise/config.toml"
            [[ -f "$pf" ]] && diff_mise_files+=("$pf")
        done
        local -A diff_sections
        local diff_current_section="_top"
        for f in "${diff_mise_files[@]}"; do
            while IFS= read -r line || [[ -n "$line" ]]; do
                if [[ "$line" =~ '^\[' ]]; then
                    diff_current_section="$line"
                elif [[ -n "$line" ]]; then
                    diff_sections[$diff_current_section]+="$line"$'\n'
                fi
            done < "$f"
        done
        {
            for section in "${(@k)diff_sections}"; do
                [[ "$section" != "_top" ]] && echo "$section"
                local -A diff_seen_keys=()
                local -a diff_ordered_lines=()
                while IFS= read -r line; do
                    [[ -z "$line" ]] && continue
                    local key="${line%%=*}"
                    key="${key%% }"
                    if [[ -n "${diff_seen_keys[$key]+x}" ]]; then
                        local idx="${diff_seen_keys[$key]}"
                        diff_ordered_lines[$idx]="$line"
                    else
                        diff_ordered_lines+=("$line")
                        diff_seen_keys[$key]="${#diff_ordered_lines}"
                    fi
                done <<< "${diff_sections[$section]}"
                printf '%s\n' "${diff_ordered_lines[@]}"
                echo ""
            done
        } > "$tmpfile"
        result=$($diff_cmd "$target" "$tmpfile" 2>/dev/null)
        if [[ -n "$result" ]]; then
            echo "=== mise (~/.config/mise/config.toml) ==="
            echo "$result"
            echo ""
            has_diff=true
        fi
        rm -f "$tmpfile"
    fi

    if _profile_diff_structured_profile_config "$profiles" "claude" "settings.json" "$HOME/.claude" "json" "claude (~/.claude/settings.json)" "$diff_cmd"; then
        has_diff=true
    fi
    if _profile_diff_last_wins_paths "$profiles" "claude" "$HOME/.claude" "claude" "$diff_cmd" "${_CLAUDE_LAST_WINS_PATHS[@]}"; then
        has_diff=true
    fi
    if _profile_diff_union_file_collection "$profiles" "claude" "hooks" "*.sh" "$HOME/.claude" "claude/hooks" "$diff_cmd"; then
        has_diff=true
    fi
    if _profile_diff_union_dir_collection "$profiles" "claude" "skills" "$HOME/.claude" "claude/skills"; then
        has_diff=true
    fi
    if _profile_diff_union_file_collection "$profiles" "claude" "commands" "*.md" "$HOME/.claude" "claude/commands" "$diff_cmd"; then
        has_diff=true
    fi

    if _profile_diff_structured_profile_config "$profiles" "codex" "config.toml" "$HOME/.codex" "toml" "codex (~/.codex/config.toml)" "$diff_cmd"; then
        has_diff=true
    fi
    if _profile_diff_structured_profile_config "$profiles" "codex" "hooks.json" "$HOME/.codex" "json" "codex (~/.codex/hooks.json)" "$diff_cmd"; then
        has_diff=true
    fi
    if _profile_diff_last_wins_paths "$profiles" "codex" "$HOME/.codex" "codex" "$diff_cmd" "${_CODEX_LAST_WINS_PATHS[@]}"; then
        has_diff=true
    fi
    if _profile_diff_union_file_collection "$profiles" "codex" "hooks" "*" "$HOME/.codex" "codex/hooks" "$diff_cmd"; then
        has_diff=true
    fi
    if _profile_diff_union_file_collection "$profiles" "codex" "agents" "*.toml" "$HOME/.codex" "codex/agents" "$diff_cmd"; then
        has_diff=true
    fi
    if _profile_diff_union_dir_collection "$profiles" "claude" "skills" "$HOME/.codex" "codex/skills"; then
        has_diff=true
    fi
    if _profile_diff_derived_symlink "codex/AGENTS.md (~/.codex/AGENTS.md)" "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md"; then
        has_diff=true
    fi

    # Tmux
    local tmux_source=""
    [[ -f "$PROFILES_DIR/default/tmux/tmux.conf" ]] && tmux_source="$PROFILES_DIR/default/tmux/tmux.conf"
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        [[ -f "$PROFILES_DIR/$p/tmux/tmux.conf" ]] && tmux_source="$PROFILES_DIR/$p/tmux/tmux.conf"
    done
    if [[ -n "$tmux_source" ]]; then
        local target="$HOME/.tmux.conf"
        if [[ -f "$target" ]]; then
            result=$($diff_cmd "$target" "$tmux_source" 2>/dev/null)
            if [[ -n "$result" ]]; then
                echo "=== tmux (~/.tmux.conf) ==="
                echo "$result"
                echo ""
                has_diff=true
            fi
        else
            echo "=== tmux (~/.tmux.conf) ==="
            echo "  (new file would be created)"
            echo ""
            has_diff=true
        fi
    fi

    # VSCode settings
    local default_dir="$PROFILES_DIR/default/vscode"

    # Settings files (shared across instances)
    local -a settings_files=()
    [[ -f "$default_dir/settings.json" ]] && settings_files+=("$default_dir/settings.json")
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        local pf="$PROFILES_DIR/$p/vscode/settings.json"
        [[ -f "$pf" ]] && settings_files+=("$pf")
    done

    # Keybindings: last profile wins
    local kb_source=""
    [[ -f "$default_dir/keybindings.json" ]] && kb_source="$default_dir/keybindings.json"
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        [[ -f "$PROFILES_DIR/$p/vscode/keybindings.json" ]] && kb_source="$PROFILES_DIR/$p/vscode/keybindings.json"
    done

    # Extensions
    local -a ext_files=()
    [[ -f "$default_dir/extensions.txt" ]] && ext_files+=("$default_dir/extensions.txt")
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        local ef="$PROFILES_DIR/$p/vscode/extensions.txt"
        [[ -f "$ef" ]] && ext_files+=("$ef")
    done

    while IFS='|' read -r inst_label vscode_user_dir vscode_cli; do
        [[ -z "$inst_label" ]] && continue

        if [[ ${#settings_files[@]} -gt 0 ]]; then
            local tmpfile=$(mktemp)
            if [[ ${#settings_files[@]} -eq 1 ]]; then
                cp "${settings_files[1]}" "$tmpfile"
            else
                jq -s 'reduce .[] as $item ({}; . * $item)' "${settings_files[@]}" > "$tmpfile"
            fi
            result=$($diff_cmd "$vscode_user_dir/settings.json" "$tmpfile" 2>/dev/null)
            if [[ -n "$result" ]]; then
                echo "=== vscode/settings ($inst_label) ==="
                echo "$result"
                echo ""
                has_diff=true
            fi
            rm -f "$tmpfile"
        fi

        if [[ -n "$kb_source" && -f "$vscode_user_dir/keybindings.json" ]]; then
            result=$($diff_cmd "$vscode_user_dir/keybindings.json" "$kb_source" 2>/dev/null)
            if [[ -n "$result" ]]; then
                echo "=== vscode/keybindings ($inst_label) ==="
                echo "$result"
                echo ""
                has_diff=true
            fi
        fi

        if [[ ${#ext_files[@]} -gt 0 && -n "$vscode_cli" ]]; then
            local installed
            installed=$("$vscode_cli" --list-extensions 2>/dev/null | sort)
            local desired
            desired=$(_profile_read_extensions "${ext_files[@]}")
            local missing=$(comm -23 <(echo "$desired") <(echo "$installed"))
            local extra=$(comm -13 <(echo "$desired") <(echo "$installed"))
            if [[ -n "$missing" || -n "$extra" ]]; then
                echo "=== vscode/extensions ($inst_label) ==="
                [[ -n "$missing" ]] && echo "$missing" | sed 's/^/  + /'
                [[ -n "$extra" ]] && echo "$extra" | sed 's/^/  - /'
                echo ""
                has_diff=true
            fi
        fi
    done < <(_profile_vscode_instances 2>/dev/null)

    # Brew
    local default_brewfile="$PROFILES_DIR/default/Brewfile"
    if [[ -f "$default_brewfile" ]]; then
        local -a brewfiles=("$default_brewfile")
        for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
            local pf="$PROFILES_DIR/$p/Brewfile"
            [[ -f "$pf" ]] && brewfiles+=("$pf")
        done
        local all_expected=$(_profile_read_brew_packages "${brewfiles[@]}")
        local current_formulae=$(brew leaves 2>/dev/null | sort)
        local current_casks=$(brew list --cask 2>/dev/null | sort)
        local current_set=$( (echo "$current_formulae" | sed 's/^/brew:/'; echo "$current_casks" | sed 's/^/cask:/') | sort -u)
        local brew_missing=$(comm -23 <(echo "$all_expected" | grep -v "^tap:") <(echo "$current_set"))
        local all_known=$(_profile_read_all_brew_packages)
        local all_known_no_tap=$(echo "$all_known" | grep -v "^tap:")
        local brew_extra=$(comm -23 <(echo "$current_set") <(echo "$all_known_no_tap") | grep -v '^$')
        if [[ -n "$brew_missing" || -n "$brew_extra" ]]; then
            echo "=== brew ==="
            [[ -n "$brew_missing" ]] && echo "$brew_missing" | sed 's/^/  + /'
            [[ -n "$brew_extra" ]] && echo "$brew_extra" | sed 's/^/  - /'
            echo ""
            has_diff=true
        fi
    fi

    # iTerm (macOS only)
    local default_iterm="$PROFILES_DIR/default/iterm/profile.json"
    local dynamic_dir="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
    if [[ "$IS_MACOS" == true && -d "$HOME/Library/Application Support/iTerm2" ]]; then
        local -a iterm_files=()
        [[ -f "$default_iterm" ]] && iterm_files+=("$default_iterm")
        for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
            local pf="$PROFILES_DIR/$p/iterm/profile.json"
            [[ -f "$pf" ]] && iterm_files+=("$pf")
        done
        if [[ ${#iterm_files[@]} -gt 0 ]]; then
            local tmpfile=$(mktemp)
            if [[ ${#iterm_files[@]} -eq 1 ]]; then
                cp "${iterm_files[1]}" "$tmpfile"
            else
                jq -s 'reduce .[] as $item ({}; {"Profiles": [(.Profiles[0] // {}) * ($item.Profiles[0] // {})]})' \
                    "${iterm_files[@]}" > "$tmpfile"
            fi
            if [[ -f "$dynamic_dir/dotfiles.json" ]]; then
                result=$($diff_cmd "$dynamic_dir/dotfiles.json" "$tmpfile" 2>/dev/null)
                if [[ -n "$result" ]]; then
                    echo "=== iterm ==="
                    echo "$result"
                    echo ""
                    has_diff=true
                fi
            else
                echo "=== iterm ==="
                echo "  (new file would be created)"
                echo ""
                has_diff=true
            fi
            rm -f "$tmpfile"
        fi
    fi

    if [[ "$has_diff" == "false" ]]; then
        echo "No changes needed."
    fi
}
