# Profile system - diff/preview (what switch would change)

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

    # Claude Code
    local has_claude=false
    [[ -f "$PROFILES_DIR/default/claude/settings.json" ]] && has_claude=true
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        [[ -f "$PROFILES_DIR/$p/claude/settings.json" ]] && has_claude=true
    done
    if [[ "$has_claude" == "true" ]]; then
        local target="$HOME/.claude/settings.json"
        local tmpfile=$(mktemp)
        local -a claude_files=()
        [[ -f "$PROFILES_DIR/default/claude/settings.json" ]] && claude_files+=("$PROFILES_DIR/default/claude/settings.json")
        for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
            local pf="$PROFILES_DIR/$p/claude/settings.json"
            [[ -f "$pf" ]] && claude_files+=("$pf")
        done
        if [[ ${#claude_files[@]} -eq 1 ]]; then
            cp "${claude_files[1]}" "$tmpfile"
        else
            jq -s 'reduce .[] as $item ({}; . * $item)' "${claude_files[@]}" > "$tmpfile"
        fi
        result=$($diff_cmd "$target" "$tmpfile" 2>/dev/null)
        if [[ -n "$result" ]]; then
            echo "=== claude (~/.claude/settings.json) ==="
            echo "$result"
            echo ""
            has_diff=true
        fi
        rm -f "$tmpfile"
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
