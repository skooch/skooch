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
    HOMEBREW_NO_COLOR=1 HOMEBREW_NO_EMOJI=1 brew bundle --file="$tmpfile" --verbose
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

_profile_mise_merge() {
    local outfile="$1"; shift
    local -a infiles=("$@")

    local merged_rest=$(mktemp)
    local -A sections
    local -a section_order=()
    local current_section="_top"
    for f in "${infiles[@]}"; do
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" == \[* ]]; then
                current_section="$line"
                if [[ "$current_section" != "[tools]" ]]; then
                    local seen_section=false
                    for section in "${section_order[@]}"; do
                        [[ "$section" == "$current_section" ]] && seen_section=true && break
                    done
                    [[ "$seen_section" == false ]] && section_order+=("$current_section")
                fi
            elif [[ -n "$line" && "$current_section" != "[tools]" ]]; then
                sections[$current_section]+="$line"$'\n'
            fi
        done < "$f"
    done

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
    } > "$merged_rest"

    local merged_tools=$(mktemp)
    _profile_mise_collect_tools "$merged_tools" "${infiles[@]}"
    _profile_mise_write_config "$outfile" "$merged_rest" "$merged_tools"

    rm -f "$merged_rest" "$merged_tools"
}

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

    # --- Target integrity checks ---

    local expect_symlink=false
    [[ ${#mise_files[@]} -eq 1 ]] && expect_symlink=true
    local needs_prompt=false
    local prompt_reason=""

    if [[ -e "$target" || -L "$target" ]]; then
        if [[ "$expect_symlink" == true ]]; then
            # Single source: target should be a symlink to the profile file
            local expected_link="${mise_files[1]}"
            if [[ -L "$target" ]]; then
                if ! _profile_symlink_matches "$target" "$expected_link"; then
                    prompt_reason="symlink points to unexpected target"
                    echo "Warning: $target is a symlink to an unexpected location."
                    echo "  Current:  $(readlink "$target")"
                    echo "  Expected: $expected_link"
                    needs_prompt=true
                fi
            else
                prompt_reason="regular file where symlink expected"
                echo "Warning: $target should be a symlink but is a regular file."
                echo "  Expected link to: $expected_link"
                needs_prompt=true
            fi
        else
            # Multi source: target should be a merged regular file
            if [[ -L "$target" ]]; then
                prompt_reason="symlink where merged file expected"
                echo "Warning: $target is a symlink but should be a merged file."
                echo "  Current link: $(readlink "$target")"
                needs_prompt=true
            fi
        fi

        # Content check: warn if target content differs from what we would write
        if [[ "$needs_prompt" == false && -f "$target" ]]; then
            local target_real="$target"
            [[ -L "$target" ]] && target_real=$(readlink "$target")
            local target_hash=$(_platform_md5 "$target_real" 2>/dev/null)

            local expected_hash=""
            if [[ "$expect_symlink" == true ]]; then
                expected_hash=$(_platform_md5 "${mise_files[1]}" 2>/dev/null)
            else
                local tmp_merge
                tmp_merge=$(mktemp)
                _profile_mise_merge "$tmp_merge" "${mise_files[@]}"
                expected_hash=$(_platform_md5 "$tmp_merge" 2>/dev/null)
                rm -f "$tmp_merge"
            fi

            if [[ -n "$target_hash" && -n "$expected_hash" && "$target_hash" != "$expected_hash" ]]; then
                prompt_reason="content differs"
                echo "Warning: $target has local changes that will be overwritten."
                needs_prompt=true
            fi
        fi

        if [[ "$needs_prompt" == true ]]; then
            printf "Overwrite? [y/N] "
            local answer
            read -r answer
            if [[ "$answer" != [yY] && "$answer" != [yY][eE][sS] ]]; then
                echo "Skipping mise config."
                return 0
            fi
        fi
    fi

    # --- Apply ---

    if [[ ${#mise_files[@]} -eq 1 ]]; then
        _profile_ln_s "${mise_files[1]}" "$target"
        echo "Applying mise config: $label"

        if command -v mise &>/dev/null; then
            echo "Running mise install..."
            mise install
        fi
        return 0
    fi

    # Remove any existing symlink so the merge writes a real file,
    # not through the symlink into the profile source.
    [[ -L "$target" ]] && rm -f "$target"

    _profile_mise_merge "$target" "${mise_files[@]}"

    echo "Applying mise config: $label"

    if command -v mise &>/dev/null; then
        echo "Running mise install..."
        mise install
    fi
}

# --- Claude Code ---

_profile_apply_claude() {
    local profiles="$1"

    mkdir -p "$HOME/.claude"
    _profile_apply_structured_profile_config \
        "Claude Code settings" "$profiles" "claude" "settings.json" "$HOME/.claude" "json"

    _profile_claude_link_files "$profiles"
    _profile_link_union_file_collection "$profiles" "claude" "hooks" "*" "$HOME/.claude" "apply" "Hooks"
    _profile_link_union_file_collection "$profiles" "claude" "commands" "*.md" "$HOME/.claude" "apply" "Commands"
}

# --- Codex ---

_profile_apply_codex() {
    local profiles="$1"

    mkdir -p "$HOME/.codex"

    _profile_apply_structured_profile_config \
        "Codex config" "$profiles" "codex" "config.toml" "$HOME/.codex" "toml"
    _profile_apply_structured_profile_config \
        "Codex hooks" "$profiles" "codex" "hooks.json" "$HOME/.codex" "json"

    _profile_link_last_wins_paths "$profiles" "codex" "$HOME/.codex" "apply" "${_CODEX_LAST_WINS_PATHS[@]}"
    _profile_link_union_file_collection "$profiles" "codex" "hooks" "*" "$HOME/.codex" "apply" "Hooks"
    _profile_link_union_file_collection "$profiles" "codex" "agents" "*.toml" "$HOME/.codex" "apply" "Agents"
    _profile_ensure_derived_symlink "AGENTS.md" "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md" "apply"
}

# --- Tmux ---

_profile_apply_tmux() {
    local profiles="$1"
    local target="$HOME/.tmux.conf"

    # Last profile wins
    local source=""
    local source_profile=""
    [[ -f "$PROFILES_DIR/default/tmux/tmux.conf" ]] && { source="$PROFILES_DIR/default/tmux/tmux.conf"; source_profile="default"; }
    for p in ${=profiles}; do
        [[ "$p" == "default" ]] && continue
        if [[ -f "$PROFILES_DIR/$p/tmux/tmux.conf" ]]; then
            source="$PROFILES_DIR/$p/tmux/tmux.conf"
            source_profile="$p"
        fi
    done

    [[ -z "$source" ]] && return 0

    cp "$source" "$target"
    echo "Applying tmux config: $source_profile"
}

# --- codebase-memory-mcp ---
#
# Ownership split: we bootstrap the binary here, but agent config (hooks,
# MCP server entries, session reminders) is vendored in profiles/default/*
# and written by the profile system's own apply functions.
#
# We deliberately do NOT run `codebase-memory-mcp install -y`. That command
# is a multi-agent bootstrapper that would mutate settings.json, config.toml,
# and hooks we already manage — producing host-scoped paths, duplicate
# .zshrc PATH entries, and phantom drift on every `profile use`.
#
# To adopt upstream agent-config changes from a newer cbm release, run
# `codebase-memory-mcp install -y` manually, then `profile sync` to review
# the drift and import the changes you want. See `profile help`.

_profile_apply_cbm() {
    if ! command -v codebase-memory-mcp &>/dev/null; then
        echo "Installing codebase-memory-mcp..."
        if ! curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh \
            | bash -s -- --skip-config 2>&1 | sed 's/^/  /'; then
            echo "codebase-memory-mcp: install failed"
            return 0
        fi
        # Installer writes to ~/.local/bin; ensure it's on PATH for the version check below
        [[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || export PATH="$HOME/.local/bin:$PATH"
        hash -r 2>/dev/null
        if ! command -v codebase-memory-mcp &>/dev/null; then
            echo "codebase-memory-mcp: install claimed success but binary not on PATH"
            return 0
        fi
    fi

    local version
    version=$(codebase-memory-mcp --version 2>/dev/null | awk '{print $NF}')
    echo "codebase-memory-mcp: installed (${version:-unknown})"
}

# --- Git cache ---

_profile_apply_git_cache() {
    if ! command -v npm >/dev/null 2>&1; then
        echo "Git cache: npm not found, skipping (install node via mise first)"
        return 0
    fi

    echo "Setting up git cache..."
    "$DOTFILES_DIR/lib/git-cache/setup.sh" setup
}
