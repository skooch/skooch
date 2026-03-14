# Profile system - apply functions (profile -> local)

_profile_apply_brew() {
    local profiles="$1"
    local default_brewfile="$PROFILES_DIR/default/Brewfile"

    if [[ ! -f "$default_brewfile" ]]; then
        echo "Brew: no default Brewfile found, skipping"
        return 0
    fi

    local tmpfile=$(mktemp)
    cat "$default_brewfile" > "$tmpfile"

    local label="default"
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        local pf="$PROFILES_DIR/$p/Brewfile"
        if [[ -f "$pf" ]]; then
            echo "" >> "$tmpfile"
            cat "$pf" >> "$tmpfile"
            label+=" + $p"
        fi
    done

    echo "Applying Brewfile: $label"
    brew bundle --file="$tmpfile"
    rm -f "$tmpfile"

    _profile_post_brew
}

_profile_post_brew() {
    local BREW_ZSH="${HOMEBREW_PREFIX:-}/bin/zsh"

    # zsh: add to /etc/shells and set as login shell
    if [[ -x "$BREW_ZSH" ]]; then
        if ! grep -qFx "$BREW_ZSH" /etc/shells 2>/dev/null; then
            echo "Adding $BREW_ZSH to /etc/shells (requires sudo)..."
            echo "$BREW_ZSH" | sudo tee -a /etc/shells >/dev/null
        fi
        local current_shell
        if [[ "$IS_MACOS" == true ]]; then
            current_shell=$(dscl . -read /Users/"$(whoami)" UserShell 2>/dev/null | awk '{print $2}')
        else
            current_shell=$(getent passwd "$(whoami)" | cut -d: -f7)
        fi
        if [[ "$current_shell" != "$BREW_ZSH" ]]; then
            echo "Setting login shell to $BREW_ZSH..."
            chsh -s "$BREW_ZSH"
        fi
    fi

    # git-lfs: install hooks
    if command -v git-lfs &>/dev/null; then
        if ! git lfs env 2>/dev/null | grep -q "filter.lfs"; then
            echo "Initializing git-lfs..."
            git lfs install
        fi
    fi
}

_profile_apply_vscode() {
    local profiles="$1"
    local default_dir="$PROFILES_DIR/default/vscode"

    local has_config=false
    [[ -d "$default_dir" ]] && has_config=true
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        [[ -d "$PROFILES_DIR/$p/vscode" ]] && has_config=true
    done
    [[ "$has_config" == "false" ]] && return 0

    local instances
    instances=$(_profile_vscode_instances)
    if [[ -z "$instances" ]]; then
        echo "VSCode: no installation found, skipping"
        return 0
    fi

    local profile_label="default"
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        profile_label+=" + $p"
    done

    local conflicts
    conflicts=$(_profile_detect_vscode_conflicts "$profiles")
    if [[ -n "$conflicts" ]]; then
        echo ""
        echo "$conflicts"
        echo ""
    fi

    # Merge settings
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

    # Extensions: union
    local -a ext_files=()
    [[ -f "$default_dir/extensions.txt" ]] && ext_files+=("$default_dir/extensions.txt")
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        local ef="$PROFILES_DIR/$p/vscode/extensions.txt"
        [[ -f "$ef" ]] && ext_files+=("$ef")
    done

    local -a desired_extensions=()
    for ext_file in "${ext_files[@]}"; do
        while IFS= read -r ext || [[ -n "$ext" ]]; do
            ext="${ext%%#*}"
            ext="${ext// /}"
            [[ -n "$ext" ]] && desired_extensions+=("$ext")
        done < "$ext_file"
    done
    local -aU desired_extensions=("${desired_extensions[@]}")

    while IFS='|' read -r inst_label vscode_user_dir vscode_cli; do
        [[ -z "$inst_label" ]] && continue
        echo "Applying VSCode profile ($inst_label): $profile_label"
        echo "  Target: $vscode_user_dir"

        if [[ ${#settings_files[@]} -gt 0 ]]; then
            if [[ ${#settings_files[@]} -eq 1 ]]; then
                cp "${settings_files[1]}" "$vscode_user_dir/settings.json"
            else
                jq -s 'reduce .[] as $item ({}; . * $item)' "${settings_files[@]}" \
                    > "$vscode_user_dir/settings.json"
            fi
            echo "  Settings merged"
        fi

        if [[ -n "$kb_source" ]]; then
            cp "$kb_source" "$vscode_user_dir/keybindings.json"
            echo "  Keybindings applied"
        fi

        if [[ ${#desired_extensions} -gt 0 ]]; then
            local installed
            installed=$("$vscode_cli" --list-extensions 2>/dev/null)
            local to_install=()
            for ext in "${desired_extensions[@]}"; do
                if ! echo "$installed" | grep -qi "^${ext}$"; then
                    to_install+=("$ext")
                fi
            done

            if [[ ${#to_install} -gt 0 ]]; then
                echo "  Installing ${#to_install} extensions..."
                for ext in "${to_install[@]}"; do
                    "$vscode_cli" --install-extension "$ext" --force 2>/dev/null
                done
                echo "  Extensions installed"
            else
                echo "  All extensions already installed"
            fi

            # Uninstall extensions not in any active profile
            local to_uninstall=()
            while IFS= read -r ext; do
                [[ -z "$ext" ]] && continue
                local found=0
                for desired in "${desired_extensions[@]}"; do
                    if [[ "${ext:l}" == "${desired:l}" ]]; then
                        found=1
                        break
                    fi
                done
                if [[ $found -eq 0 ]]; then
                    to_uninstall+=("$ext")
                fi
            done <<< "$installed"

            if [[ ${#to_uninstall} -gt 0 ]]; then
                echo "  Uninstalling ${#to_uninstall} extensions not in profile..."
                for ext in "${to_uninstall[@]}"; do
                    "$vscode_cli" --uninstall-extension "$ext" 2>/dev/null
                done
                echo "  Extensions uninstalled"
            fi
        fi

        echo "  Done. Restart $inst_label to apply changes."
    done <<< "$instances"
}

# --- iTerm ---

_profile_apply_iterm() {
    [[ "$IS_MACOS" != true ]] && return 0
    local profiles="$1"
    local default_iterm="$PROFILES_DIR/default/iterm/profile.json"
    local dynamic_dir="$HOME/Library/Application Support/iTerm2/DynamicProfiles"

    local has_config=false
    [[ -f "$default_iterm" ]] && has_config=true
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        [[ -f "$PROFILES_DIR/$p/iterm/profile.json" ]] && has_config=true
    done
    [[ "$has_config" == "false" ]] && return 0

    if [[ ! -d "$HOME/Library/Application Support/iTerm2" ]]; then
        return 0
    fi

    mkdir -p "$dynamic_dir"

    local -a iterm_files=()
    [[ -f "$default_iterm" ]] && iterm_files+=("$default_iterm")
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        local pf="$PROFILES_DIR/$p/iterm/profile.json"
        [[ -f "$pf" ]] && iterm_files+=("$pf")
    done

    if [[ ${#iterm_files[@]} -eq 1 ]]; then
        cp "${iterm_files[1]}" "$dynamic_dir/dotfiles.json"
        echo "Applying iTerm profile: default"
    elif [[ ${#iterm_files[@]} -gt 1 ]]; then
        jq -s 'reduce .[] as $item ({}; {"Profiles": [(.Profiles[0] // {}) * ($item.Profiles[0] // {})]})' \
            "${iterm_files[@]}" > "$dynamic_dir/dotfiles.json"
        local label="default"
        for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
            [[ -f "$PROFILES_DIR/$p/iterm/profile.json" ]] && label+=" + $p"
        done
        echo "Applying iTerm profile: $label"
    fi
}

# --- Git ---

_profile_apply_git() {
    local profiles="$1"
    local target="$HOME/.gitconfig"

    local has_config=false
    [[ -f "$PROFILES_DIR/default/git/config" ]] && has_config=true
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        [[ -f "$PROFILES_DIR/$p/git/config" ]] && has_config=true
    done
    [[ "$has_config" == "false" ]] && return 0

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

    printf '%s' "$content" > "$target"

    local label="default"
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        [[ -f "$PROFILES_DIR/$p/git/config" ]] && label+=" + $p"
    done
    echo "Applying git config: $label"
}

# --- Mise ---

_profile_apply_mise() {
    local profiles="$1"
    local target="$HOME/.config/mise/config.toml"

    local has_config=false
    [[ -f "$PROFILES_DIR/default/mise/config.toml" ]] && has_config=true
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        [[ -f "$PROFILES_DIR/$p/mise/config.toml" ]] && has_config=true
    done
    [[ "$has_config" == "false" ]] && return 0

    mkdir -p "$(dirname "$target")"

    local label="default"
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        [[ -f "$PROFILES_DIR/$p/mise/config.toml" ]] && label+=" + $p"
    done

    local -a mise_files=()
    [[ -f "$PROFILES_DIR/default/mise/config.toml" ]] && mise_files+=("$PROFILES_DIR/default/mise/config.toml")
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        local pf="$PROFILES_DIR/$p/mise/config.toml"
        [[ -f "$pf" ]] && mise_files+=("$pf")
    done

    # Merge TOML files by collecting lines per section
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
            # Deduplicate by key (last value wins)
            local -A seen_keys=()
            local -a ordered_lines=()
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                local key="${line%%=*}"
                key="${key%% }"
                if [[ -n "${seen_keys[$key]+x}" ]]; then
                    # Replace previous occurrence
                    local idx="${seen_keys[$key]}"
                    ordered_lines[$idx]="$line"
                else
                    ordered_lines+=("$line")
                    seen_keys[$key]="${#ordered_lines}"
                fi
            done <<< "${sections[$section]}"
            printf '%s\n' "${ordered_lines[@]}"
            echo ""
        done
    } > "$target"

    echo "Applying mise config: $label"

    if command -v mise &>/dev/null; then
        echo "Running mise install..."
        mise install
    fi
}

# --- Claude Code ---

_profile_apply_claude() {
    local profiles="$1"
    local target="$HOME/.claude/settings.json"

    local has_config=false
    [[ -f "$PROFILES_DIR/default/claude/settings.json" ]] && has_config=true
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        [[ -f "$PROFILES_DIR/$p/claude/settings.json" ]] && has_config=true
    done
    [[ "$has_config" == "false" ]] && return 0

    mkdir -p "$HOME/.claude"

    local -a settings_files=()
    [[ -f "$PROFILES_DIR/default/claude/settings.json" ]] && settings_files+=("$PROFILES_DIR/default/claude/settings.json")
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        local pf="$PROFILES_DIR/$p/claude/settings.json"
        [[ -f "$pf" ]] && settings_files+=("$pf")
    done

    if [[ ${#settings_files[@]} -eq 1 ]]; then
        ln -sf "${settings_files[1]}" "$target"
    else
        jq -s 'reduce .[] as $item ({}; . * $item)' "${settings_files[@]}" > "$target"
    fi

    local label="default"
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        [[ -f "$PROFILES_DIR/$p/claude/settings.json" ]] && label+=" + $p"
    done
    echo "Applying Claude Code settings: $label"
}
