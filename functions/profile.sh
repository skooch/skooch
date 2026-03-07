# Profile switcher - applies dotfiles profiles (vscode, brew, etc.)
# Supports multiple active profiles: profile switch embedded b

DOTFILES_DIR="$HOME/projects/skooch"
PROFILES_DIR="$DOTFILES_DIR/profiles"
HOSTS_FILE="$DOTFILES_DIR/hosts.json"

# XDG-compliant state directory
PROFILE_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
PROFILE_ACTIVE_FILE="$PROFILE_STATE_DIR/active"
PROFILE_SNAPSHOT_FILE="$PROFILE_STATE_DIR/snapshot"
PROFILE_MANAGED_FILE="$PROFILE_STATE_DIR/managed"

# --- Migration from old paths ---
if [[ -f "$HOME/.profile_active" && ! -f "$PROFILE_ACTIVE_FILE" ]]; then
    mkdir -p "$PROFILE_STATE_DIR"
    mv "$HOME/.profile_active" "$PROFILE_ACTIVE_FILE"
    mv "$HOME/.profile_snapshot" "$PROFILE_SNAPSHOT_FILE" 2>/dev/null
fi

# --- Detection helpers ---

_profile_find_vscode() {
    for dir in "$HOME/Library/Application Support/Code - Insiders/User" \
               "$HOME/Library/Application Support/Code/User"; do
        if [[ -d "$dir" ]]; then
            echo "$dir"
            return 0
        fi
    done
    return 1
}

_profile_find_vscode_cli() {
    for cmd in code-insiders code; do
        if command -v "$cmd" &>/dev/null; then
            echo "$cmd"
            return 0
        fi
    done
    for app in "/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/bin/code" \
               "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"; do
        if [[ -x "$app" ]]; then
            echo "$app"
            return 0
        fi
    done
    return 1
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
        while IFS= read -r line; do
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

_profile_read_extensions() {
    local -a files=("$@")
    for f in "${files[@]}"; do
        [[ -f "$f" ]] || continue
        while IFS= read -r ext; do
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
             "$dir/git/config" "$dir/mise/config.toml"; do
        echo "$f"
    done
}

# --- Snapshot ---

_profile_take_snapshot() {
    local profiles="$1"
    mkdir -p "$PROFILE_STATE_DIR"
    local hash=""
    for dir in $(_profile_collect_dirs "$profiles"); do
        for f in $(_profile_snapshot_files "$dir"); do
            [[ -f "$f" ]] && hash+=$(md5 -q "$f" 2>/dev/null)
        done
    done
    echo "$hash" > "$PROFILE_SNAPSHOT_FILE"
}

_profile_compute_hash() {
    local profiles="$1"
    local hash=""
    for dir in $(_profile_collect_dirs "$profiles"); do
        for f in $(_profile_snapshot_files "$dir"); do
            [[ -f "$f" ]] && hash+=$(md5 -q "$f" 2>/dev/null)
        done
    done
    echo "$hash"
}

# --- Drift check (file-only, no subprocesses) ---

_profile_check_drift() {
    local active=$(_profile_active)
    [[ -z "$active" ]] && return 0
    [[ ! -f "$PROFILE_SNAPSHOT_FILE" ]] && return 0

    local current_hash
    current_hash=$(_profile_compute_hash "$active")
    local stored_hash=$(cat "$PROFILE_SNAPSHOT_FILE" 2>/dev/null)

    if [[ "$current_hash" != "$stored_hash" ]]; then
        local display="${active// /, }"
        echo "Profile(s) '$display' have unsynced changes. Run 'profile status' for details or 'profile switch $active' to apply."
    fi
}

# --- Conflict detection for VSCode settings ---

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

# --- Managed files tracking ---

_profile_is_managed() {
    local path="$1"
    [[ -f "$PROFILE_MANAGED_FILE" ]] && grep -qFx "$path" "$PROFILE_MANAGED_FILE" 2>/dev/null
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
    local vscode_user_dir
    vscode_user_dir=$(_profile_find_vscode 2>/dev/null)
    if [[ -n "$vscode_user_dir" ]]; then
        local has_vscode=false
        [[ -d "$PROFILES_DIR/default/vscode" ]] && has_vscode=true
        for p in ${=profiles}; do
            [[ -d "$PROFILES_DIR/$p/vscode" ]] && has_vscode=true
        done
        if [[ "$has_vscode" == "true" ]]; then
            paths+=("$vscode_user_dir/settings.json")
            paths+=("$vscode_user_dir/keybindings.json")
        fi
    fi

    # iTerm
    local dynamic_dir="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
    local has_iterm=false
    [[ -f "$PROFILES_DIR/default/iterm/profile.json" ]] && has_iterm=true
    for p in ${=profiles}; do
        [[ -f "$PROFILES_DIR/$p/iterm/profile.json" ]] && has_iterm=true
    done
    [[ "$has_iterm" == "true" && -d "$HOME/Library/Application Support/iTerm2" ]] && \
        paths+=("$dynamic_dir/dotfiles.json")

    printf '%s\n' "${paths[@]}"
}

# --- Overwrite detection ---

_profile_check_overwrite() {
    local profiles="$1"
    local -a warnings=()

    local -a targets=()
    while IFS= read -r path; do
        [[ -n "$path" ]] && targets+=("$path")
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

# --- Apply functions ---

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
}

_profile_apply_vscode() {
    local profiles="$1"
    local default_dir="$PROFILES_DIR/default/vscode"

    local has_config=false
    [[ -d "$default_dir" ]] && has_config=true
    for p in ${=profiles}; do
        [[ -d "$PROFILES_DIR/$p/vscode" ]] && has_config=true
    done
    [[ "$has_config" == "false" ]] && return 0

    local vscode_user_dir
    vscode_user_dir=$(_profile_find_vscode)
    if [[ $? -ne 0 ]]; then
        echo "VSCode: no installation found, skipping"
        return 0
    fi

    local vscode_cli
    vscode_cli=$(_profile_find_vscode_cli)
    if [[ $? -ne 0 ]]; then
        echo "VSCode: no CLI found, skipping"
        return 0
    fi

    local label="default"
    for p in ${=profiles}; do
        label+=" + $p"
    done
    echo "Applying VSCode profile: $label"
    echo "  Target: $vscode_user_dir"

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
        local pf="$PROFILES_DIR/$p/vscode/settings.json"
        [[ -f "$pf" ]] && settings_files+=("$pf")
    done

    if [[ ${#settings_files[@]} -gt 0 ]]; then
        if [[ ${#settings_files[@]} -eq 1 ]]; then
            cp "${settings_files[1]}" "$vscode_user_dir/settings.json"
        else
            jq -s 'reduce .[] as $item ({}; . * $item)' "${settings_files[@]}" \
                > "$vscode_user_dir/settings.json"
        fi
        echo "  Settings merged"
    fi

    # Keybindings: last profile wins
    local kb_source=""
    [[ -f "$default_dir/keybindings.json" ]] && kb_source="$default_dir/keybindings.json"
    for p in ${=profiles}; do
        [[ -f "$PROFILES_DIR/$p/vscode/keybindings.json" ]] && kb_source="$PROFILES_DIR/$p/vscode/keybindings.json"
    done
    if [[ -n "$kb_source" ]]; then
        cp "$kb_source" "$vscode_user_dir/keybindings.json"
        echo "  Keybindings applied"
    fi

    # Extensions: union
    local -a ext_files=()
    [[ -f "$default_dir/extensions.txt" ]] && ext_files+=("$default_dir/extensions.txt")
    for p in ${=profiles}; do
        local ef="$PROFILES_DIR/$p/vscode/extensions.txt"
        [[ -f "$ef" ]] && ext_files+=("$ef")
    done

    local -a desired_extensions=()
    for ext_file in "${ext_files[@]}"; do
        while IFS= read -r ext; do
            ext="${ext%%#*}"
            ext="${ext// /}"
            [[ -n "$ext" ]] && desired_extensions+=("$ext")
        done < "$ext_file"
    done
    local -aU desired_extensions=("${desired_extensions[@]}")

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
                "$vscode_cli" --install-extension "$ext" --force 2>/dev/null &
            done
            wait
            echo "  Extensions installed"
        else
            echo "  All extensions already installed"
        fi
    fi

    echo "  Done. Restart VSCode to apply changes."
}

# --- iTerm ---

_profile_apply_iterm() {
    local profiles="$1"
    local default_iterm="$PROFILES_DIR/default/iterm/profile.json"
    local dynamic_dir="$HOME/Library/Application Support/iTerm2/DynamicProfiles"

    local has_config=false
    [[ -f "$default_iterm" ]] && has_config=true
    for p in ${=profiles}; do
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
        [[ -f "$PROFILES_DIR/$p/git/config" ]] && has_config=true
    done
    [[ "$has_config" == "false" ]] && return 0

    local content=""
    if [[ -f "$PROFILES_DIR/default/git/config" ]]; then
        content+="[include]"$'\n'
        content+="	path = $PROFILES_DIR/default/git/config"$'\n'
    fi
    for p in ${=profiles}; do
        if [[ -f "$PROFILES_DIR/$p/git/config" ]]; then
            content+="[include]"$'\n'
            content+="	path = $PROFILES_DIR/$p/git/config"$'\n'
        fi
    done

    printf '%s' "$content" > "$target"

    local label="default"
    for p in ${=profiles}; do
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
        [[ -f "$PROFILES_DIR/$p/mise/config.toml" ]] && has_config=true
    done
    [[ "$has_config" == "false" ]] && return 0

    mkdir -p "$(dirname "$target")"

    local label="default"
    for p in ${=profiles}; do
        [[ -f "$PROFILES_DIR/$p/mise/config.toml" ]] && label+=" + $p"
    done

    local -a mise_files=()
    [[ -f "$PROFILES_DIR/default/mise/config.toml" ]] && mise_files+=("$PROFILES_DIR/default/mise/config.toml")
    for p in ${=profiles}; do
        local pf="$PROFILES_DIR/$p/mise/config.toml"
        [[ -f "$pf" ]] && mise_files+=("$pf")
    done

    # Merge TOML files by collecting lines per section
    local -A sections
    local current_section="_top"
    for f in "${mise_files[@]}"; do
        while IFS= read -r line; do
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
            printf '%s' "${sections[$section]}"
            echo ""
        done
    } > "$target"

    echo "Applying mise config: $label"
}

# --- Diff (preview what switch would do) ---

_profile_diff() {
    local profiles="$1"
    local has_diff=false
    local diff_cmd="diff"
    diff --color /dev/null /dev/null 2>/dev/null && diff_cmd="diff --color"

    # Git
    local has_git=false
    [[ -f "$PROFILES_DIR/default/git/config" ]] && has_git=true
    for p in ${=profiles}; do
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
            if [[ -f "$PROFILES_DIR/$p/git/config" ]]; then
                content+="[include]"$'\n'
                content+="	path = $PROFILES_DIR/$p/git/config"$'\n'
            fi
        done
        printf '%s' "$content" > "$tmpfile"
        local result
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
        [[ -f "$PROFILES_DIR/$p/mise/config.toml" ]] && has_mise=true
    done
    if [[ "$has_mise" == "true" ]]; then
        local target="$HOME/.config/mise/config.toml"
        local tmpfile=$(mktemp)
        local -a diff_mise_files=()
        [[ -f "$PROFILES_DIR/default/mise/config.toml" ]] && diff_mise_files+=("$PROFILES_DIR/default/mise/config.toml")
        for p in ${=profiles}; do
            local pf="$PROFILES_DIR/$p/mise/config.toml"
            [[ -f "$pf" ]] && diff_mise_files+=("$pf")
        done
        local -A diff_sections
        local diff_current_section="_top"
        for f in "${diff_mise_files[@]}"; do
            while IFS= read -r line; do
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
                printf '%s' "${diff_sections[$section]}"
                echo ""
            done
        } > "$tmpfile"
        local result
        result=$($diff_cmd "$target" "$tmpfile" 2>/dev/null)
        if [[ -n "$result" ]]; then
            echo "=== mise (~/.config/mise/config.toml) ==="
            echo "$result"
            echo ""
            has_diff=true
        fi
        rm -f "$tmpfile"
    fi

    # VSCode settings
    local vscode_user_dir
    vscode_user_dir=$(_profile_find_vscode 2>/dev/null)
    if [[ -n "$vscode_user_dir" ]]; then
        local default_dir="$PROFILES_DIR/default/vscode"

        # Settings
        local -a settings_files=()
        [[ -f "$default_dir/settings.json" ]] && settings_files+=("$default_dir/settings.json")
        for p in ${=profiles}; do
            local pf="$PROFILES_DIR/$p/vscode/settings.json"
            [[ -f "$pf" ]] && settings_files+=("$pf")
        done
        if [[ ${#settings_files[@]} -gt 0 ]]; then
            local tmpfile=$(mktemp)
            if [[ ${#settings_files[@]} -eq 1 ]]; then
                cp "${settings_files[1]}" "$tmpfile"
            else
                jq -s 'reduce .[] as $item ({}; . * $item)' "${settings_files[@]}" > "$tmpfile"
            fi
            local result
            result=$($diff_cmd "$vscode_user_dir/settings.json" "$tmpfile" 2>/dev/null)
            if [[ -n "$result" ]]; then
                echo "=== vscode/settings ==="
                echo "$result"
                echo ""
                has_diff=true
            fi
            rm -f "$tmpfile"
        fi

        # Keybindings
        local kb_source=""
        [[ -f "$default_dir/keybindings.json" ]] && kb_source="$default_dir/keybindings.json"
        for p in ${=profiles}; do
            [[ -f "$PROFILES_DIR/$p/vscode/keybindings.json" ]] && kb_source="$PROFILES_DIR/$p/vscode/keybindings.json"
        done
        if [[ -n "$kb_source" && -f "$vscode_user_dir/keybindings.json" ]]; then
            local result
            result=$($diff_cmd "$vscode_user_dir/keybindings.json" "$kb_source" 2>/dev/null)
            if [[ -n "$result" ]]; then
                echo "=== vscode/keybindings ==="
                echo "$result"
                echo ""
                has_diff=true
            fi
        fi

        # Extensions
        local -a ext_files=()
        [[ -f "$default_dir/extensions.txt" ]] && ext_files+=("$default_dir/extensions.txt")
        for p in ${=profiles}; do
            local ef="$PROFILES_DIR/$p/vscode/extensions.txt"
            [[ -f "$ef" ]] && ext_files+=("$ef")
        done
        if [[ ${#ext_files[@]} -gt 0 ]]; then
            local vscode_cli
            vscode_cli=$(_profile_find_vscode_cli 2>/dev/null)
            if [[ -n "$vscode_cli" ]]; then
                local installed
                installed=$("$vscode_cli" --list-extensions 2>/dev/null | sort)
                local desired
                desired=$(_profile_read_extensions "${ext_files[@]}")
                local missing=$(comm -23 <(echo "$desired") <(echo "$installed"))
                local extra=$(comm -13 <(echo "$desired") <(echo "$installed"))
                if [[ -n "$missing" || -n "$extra" ]]; then
                    echo "=== vscode/extensions ==="
                    [[ -n "$missing" ]] && echo "$missing" | sed 's/^/  + /'
                    [[ -n "$extra" ]] && echo "$extra" | sed 's/^/  - /'
                    echo ""
                    has_diff=true
                fi
            fi
        fi
    fi

    # Brew
    local default_brewfile="$PROFILES_DIR/default/Brewfile"
    if [[ -f "$default_brewfile" ]]; then
        local -a brewfiles=("$default_brewfile")
        for p in ${=profiles}; do
            local pf="$PROFILES_DIR/$p/Brewfile"
            [[ -f "$pf" ]] && brewfiles+=("$pf")
        done
        local all_expected=$(_profile_read_brew_packages "${brewfiles[@]}")
        local current_formulae=$(brew leaves 2>/dev/null | sort)
        local current_casks=$(brew list --cask 2>/dev/null | sort)
        local current_set=$( (echo "$current_formulae" | sed 's/^/brew:/'; echo "$current_casks" | sed 's/^/cask:/') | sort -u)
        local brew_missing=$(comm -23 <(echo "$all_expected" | grep -v "^tap:") <(echo "$current_set"))
        if [[ -n "$brew_missing" ]]; then
            echo "=== brew ==="
            echo "$brew_missing" | sed 's/^/  + /'
            echo ""
            has_diff=true
        fi
    fi

    # iTerm
    local default_iterm="$PROFILES_DIR/default/iterm/profile.json"
    local dynamic_dir="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
    if [[ -d "$HOME/Library/Application Support/iTerm2" ]]; then
        local -a iterm_files=()
        [[ -f "$default_iterm" ]] && iterm_files+=("$default_iterm")
        for p in ${=profiles}; do
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
                local result
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

# --- Update helpers ---

_profile_pick_target() {
    local profiles="$1"
    local label="$2"
    local -a candidates=()

    for p in ${=profiles}; do
        candidates+=("$p")
    done

    if [[ ${#candidates[@]} -le 1 ]]; then
        if [[ ${#candidates[@]} -eq 0 ]]; then
            echo "default"
        else
            echo "${candidates[1]}"
        fi
        return 0
    fi

    echo "" >&2
    echo "  Multiple profiles active. Add new ${label} entries to which profile?" >&2
    local i
    for (( i=1; i <= ${#candidates[@]}; i++ )); do
        local suffix=""
        [[ $i -eq ${#candidates[@]} ]] && suffix=" (default)"
        echo "    $i) ${candidates[$i]}${suffix}" >&2
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

# --- Update (sync local state back to profile files) ---

_profile_update_brew() {
    local profiles="$1"
    local default_brewfile="$PROFILES_DIR/default/Brewfile"

    echo "Syncing brew packages..."

    local current_formulae=$(brew leaves 2>/dev/null | sort)
    local current_casks=$(brew list --cask 2>/dev/null | sort)

    local -a brewfiles=("$default_brewfile")
    for p in ${=profiles}; do
        local pf="$PROFILES_DIR/$p/Brewfile"
        [[ -f "$pf" ]] && brewfiles+=("$pf")
    done
    local all_expected=$(_profile_read_brew_packages "${brewfiles[@]}")

    local current_set=$( (echo "$current_formulae" | sed 's/^/brew:/'; echo "$current_casks" | sed 's/^/cask:/') | sort -u)

    local added=$(comm -23 <(echo "$current_set") <(echo "$all_expected"))
    local removed=$(comm -13 <(echo "$current_set") <(echo "$all_expected"))
    removed=$(echo "$removed" | grep -v "^tap:")

    if [[ -z "$added" && -z "$removed" ]]; then
        echo "  Brew packages are in sync"
        return 0
    fi

    if [[ -n "$added" ]]; then
        echo "  New packages to add to profile:"
        echo "$added" | sed 's/^/    + /'

        local target_profile
        target_profile=$(_profile_pick_target "$profiles" "Brewfile")
        local target_brewfile="$PROFILES_DIR/$target_profile/Brewfile"
        [[ "$target_profile" == "default" ]] && target_brewfile="$default_brewfile"

        for pkg in ${(f)added}; do
            local type="${pkg%%:*}"
            local name="${pkg#*:}"
            echo "$type \"$name\"" >> "$target_brewfile"
        done
        echo "  Written to $(basename "$(dirname "$target_brewfile")")/Brewfile"
    fi

    if [[ -n "$removed" ]]; then
        echo "  Packages removed locally:"
        echo "$removed" | sed 's/^/    - /'
        for pkg in ${(f)removed}; do
            local type="${pkg%%:*}"
            local name="${pkg#*:}"
            local pattern="^${type} \"${name}\""
            if grep -q "$pattern" "$default_brewfile" 2>/dev/null; then
                sed -i '' "/$pattern/d" "$default_brewfile"
            fi
            for p in ${=profiles}; do
                local pf="$PROFILES_DIR/$p/Brewfile"
                if [[ -f "$pf" ]] && grep -q "$pattern" "$pf" 2>/dev/null; then
                    sed -i '' "/$pattern/d" "$pf"
                fi
            done
        done
        echo "  Removed from Brewfiles"
    fi
}

_profile_update_vscode() {
    local profiles="$1"
    local default_ext="$PROFILES_DIR/default/vscode/extensions.txt"

    local vscode_cli
    vscode_cli=$(_profile_find_vscode_cli)
    if [[ $? -ne 0 ]]; then
        echo "VSCode: no CLI found, skipping extension sync"
        return 0
    fi

    echo "Syncing VSCode extensions..."

    local current=$("$vscode_cli" --list-extensions 2>/dev/null | sort)

    local -a ext_files=("$default_ext")
    for p in ${=profiles}; do
        local ef="$PROFILES_DIR/$p/vscode/extensions.txt"
        [[ -f "$ef" ]] && ext_files+=("$ef")
    done
    local expected=$(_profile_read_extensions "${ext_files[@]}")

    local added=$(comm -23 <(echo "$current") <(echo "$expected"))
    local removed=$(comm -13 <(echo "$current") <(echo "$expected"))

    if [[ -z "$added" && -z "$removed" ]]; then
        echo "  Extensions are in sync"
        return 0
    fi

    if [[ -n "$added" ]]; then
        echo "  New extensions to add to profile:"
        echo "$added" | sed 's/^/    + /'

        local target_profile
        target_profile=$(_profile_pick_target "$profiles" "extensions")
        local target_ext="$PROFILES_DIR/$target_profile/vscode/extensions.txt"
        [[ "$target_profile" == "default" || ! -d "$(dirname "$target_ext")" ]] && target_ext="$default_ext"

        for ext in ${(f)added}; do
            echo "$ext" >> "$target_ext"
        done
        echo "  Written to $(basename "$(dirname "$(dirname "$target_ext")")")/vscode/extensions.txt"
    fi

    if [[ -n "$removed" ]]; then
        echo "  Extensions removed locally:"
        echo "$removed" | sed 's/^/    - /'
        for ext in ${(f)removed}; do
            if grep -qi "^${ext}$" "$default_ext" 2>/dev/null; then
                sed -i '' "/^${ext}$/Id" "$default_ext"
            fi
            for p in ${=profiles}; do
                local ef="$PROFILES_DIR/$p/vscode/extensions.txt"
                if [[ -f "$ef" ]] && grep -qi "^${ext}$" "$ef" 2>/dev/null; then
                    sed -i '' "/^${ext}$/Id" "$ef"
                fi
            done
        done
        echo "  Removed from extensions.txt"
    fi
}

# --- Status ---

_profile_status() {
    local active=$(_profile_active)
    if [[ -z "$active" ]]; then
        echo "No active profile. Run 'profile switch <name>' first."
        return 0
    fi

    local display="${active// /, }"
    echo "Active profiles: $display"

    if [[ ! -f "$PROFILE_SNAPSHOT_FILE" ]]; then
        echo "No snapshot found. Run 'profile switch $active' to create one."
        return 0
    fi

    local current_hash
    current_hash=$(_profile_compute_hash "$active")
    local stored_hash=$(cat "$PROFILE_SNAPSHOT_FILE" 2>/dev/null)

    if [[ "$current_hash" == "$stored_hash" ]]; then
        echo "Everything is in sync."
    else
        echo "Profile files have changed since last switch."
        echo "Run 'profile switch $active' to re-apply, or 'profile update' to sync local state back."
    fi
}

# --- Host mapping ---

_profile_register() {
    local hostname=$(hostname)
    local active=$(_profile_active)

    if [[ -z "$active" ]]; then
        echo "No active profiles. Run 'profile switch <name>' first."
        return 1
    fi

    local -a profile_list=(${=active})
    local json_array
    json_array=$(printf '%s\n' "${profile_list[@]}" | jq -R . | jq -s .)

    if [[ -f "$HOSTS_FILE" ]]; then
        local updated
        updated=$(jq --arg host "$hostname" --argjson profiles "$json_array" \
            '.[$host] = $profiles' "$HOSTS_FILE")
        echo "$updated" > "$HOSTS_FILE"
    else
        jq -n --arg host "$hostname" --argjson profiles "$json_array" \
            '{($host): $profiles}' > "$HOSTS_FILE"
    fi

    local display="${active// /, }"
    echo "Registered $hostname -> [$display] in hosts.json"
}

_profile_hosts() {
    if [[ ! -f "$HOSTS_FILE" ]]; then
        echo "No hosts.json found. Run 'profile register' to create one."
        return 0
    fi

    local current_hostname=$(hostname)
    echo "Host mappings:"
    echo ""
    jq -r 'to_entries[] | "  \(.key): \(.value | join(", "))"' "$HOSTS_FILE" | while IFS= read -r line; do
        local host="${line%%:*}"
        local trimmed_host="${host## }"
        if [[ "$trimmed_host" == "$current_hostname" ]]; then
            echo "$line  (this machine)"
        else
            echo "$line"
        fi
    done
}

# --- Dependency check ---

_profile_check_deps() {
    local -a missing=()
    for cmd in brew jq; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Missing required tools: ${missing[*]}" >&2
        echo "Run install.sh first, or install manually: brew install ${missing[*]}" >&2
        return 1
    fi
    return 0
}

# --- Main entry point ---

profile() {
    local subcmd="${1:-help}"
    shift 2>/dev/null

    case "$subcmd" in
        switch|s)
            _profile_check_deps || return 1
            # Parse -f/--force flag
            local force=false
            local -a args=()
            for arg in "$@"; do
                case "$arg" in
                    -f|--force) force=true ;;
                    *) args+=("$arg") ;;
                esac
            done
            set -- "${args[@]}"

            if [[ $# -eq 0 ]]; then
                echo "Usage: profile switch [-f] <name> [name2 ...]"
                return 1
            fi
            for p in "$@"; do
                if [[ ! -d "$PROFILES_DIR/$p" ]]; then
                    echo "Error: profile '$p' not found" >&2
                    return 1
                fi
            done
            local active_set=""
            for p in "$@"; do
                [[ "$p" == "default" ]] && continue
                if [[ -n "$active_set" ]]; then
                    active_set+=" $p"
                else
                    active_set="$p"
                fi
            done
            [[ -z "$active_set" ]] && active_set="default"

            # No-op detection
            if [[ "$force" == "false" ]]; then
                local current_active=$(_profile_active)
                if [[ "$active_set" == "$current_active" ]]; then
                    local current_hash
                    current_hash=$(_profile_compute_hash "$active_set")
                    local stored_hash=$(cat "$PROFILE_SNAPSHOT_FILE" 2>/dev/null)
                    if [[ "$current_hash" == "$stored_hash" ]]; then
                        echo "Already up to date."
                        return 0
                    fi
                fi
            fi

            if [[ "$force" == "false" ]]; then
                _profile_check_overwrite "$active_set" || return 1
            fi

            mkdir -p "$PROFILE_STATE_DIR"
            _profile_apply_brew "$active_set"
            _profile_apply_vscode "$active_set"
            _profile_apply_iterm "$active_set"
            _profile_apply_git "$active_set"
            _profile_apply_mise "$active_set"
            echo "$active_set" > "$PROFILE_ACTIVE_FILE"

            # Record managed files
            local -a managed=()
            while IFS= read -r path; do
                [[ -n "$path" ]] && managed+=("$path")
            done < <(_profile_target_paths "$active_set")
            _profile_write_managed "${managed[@]}"

            echo "Taking snapshot..."
            _profile_take_snapshot "$active_set"
            local display="${active_set// /, }"
            echo "Active profiles: $display"
            ;;
        diff|d)
            _profile_check_deps || return 1
            if [[ $# -eq 0 ]]; then
                # Default to current active profiles
                local active=$(_profile_active)
                if [[ -z "$active" ]]; then
                    echo "Usage: profile diff <name> [name2 ...]"
                    return 1
                fi
                _profile_diff "$active"
            else
                for p in "$@"; do
                    if [[ ! -d "$PROFILES_DIR/$p" && "$p" != "default" ]]; then
                        echo "Error: profile '$p' not found" >&2
                        return 1
                    fi
                done
                local diff_set=""
                for p in "$@"; do
                    [[ "$p" == "default" ]] && continue
                    if [[ -n "$diff_set" ]]; then
                        diff_set+=" $p"
                    else
                        diff_set="$p"
                    fi
                done
                [[ -z "$diff_set" ]] && diff_set="default"
                _profile_diff "$diff_set"
            fi
            ;;
        update|u)
            _profile_check_deps || return 1
            local active=$(_profile_active)
            if [[ -z "$active" ]]; then
                echo "No active profile. Run 'profile switch <name>' first."
                return 1
            fi
            _profile_update_brew "$active"
            _profile_update_vscode "$active"
            echo "Taking snapshot..."
            _profile_take_snapshot "$active"
            local display="${active// /, }"
            echo "Profiles updated: $display"
            ;;
        status|st)
            _profile_status
            ;;
        register)
            _profile_check_deps || return 1
            _profile_register
            ;;
        hosts)
            _profile_hosts
            ;;
        help|*)
            echo "Usage: profile <command> [args]"
            echo ""
            echo "Commands:"
            echo "  switch <name> [name2 ...]  (s)   Apply profiles (brew + vscode + iterm + git + mise)"
            echo "  diff [name] [name2 ...]    (d)   Preview what switch would change"
            echo "  update                     (u)   Sync local changes back to profile files"
            echo "  status                     (st)  Show active profiles and drift"
            echo "  register                         Save hostname + active profiles to hosts.json"
            echo "  hosts                            Show all host mappings"
            echo ""
            echo "Flags:"
            echo "  -f, --force                      Force switch even if already up to date"
            echo ""
            echo "Available profiles:"
            local active=$(_profile_active)
            for dir in "$PROFILES_DIR"/*/; do
                local name=$(basename "$dir")
                local marker=""
                [[ " $active " == *" $name "* || "$active" == "$name" ]] && marker=" (active)"
                echo "  $name$marker"
            done
            ;;
    esac
}
