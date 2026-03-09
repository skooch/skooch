# Profile system - detection helpers, readers, and utilities

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
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%%#*}"  # strip comments
            if [[ "$line" =~ ^brew\ +\"([^\"]+)\" ]]; then
                echo "brew:${match[1]}"
            elif [[ "$line" =~ ^cask\ +\"([^\"]+)\" ]]; then
                echo "cask:${match[1]}"
            elif [[ "$line" =~ ^tap\ +\"([^\"]+)\" ]]; then
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
             "$dir/claude/settings.json"; do
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
