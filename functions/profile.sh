# Profile switcher - applies dotfiles profiles (vscode, brew, etc.)

DOTFILES_DIR="$HOME/projects/skooch"
PROFILES_DIR="$DOTFILES_DIR/profiles"
PROFILE_ACTIVE_FILE="$HOME/.profile_active"
PROFILE_SNAPSHOT_FILE="$HOME/.profile_snapshot"

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
    # Reads brew/cask package names from one or more Brewfiles
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

# --- Snapshot ---

_profile_take_snapshot() {
    local profile_name="$1"
    local default_dir="$PROFILES_DIR/default"
    local profile_dir="$PROFILES_DIR/$profile_name"

    # Hash the profile source files so drift check can detect changes
    local -a files_to_hash=(
        "$default_dir/Brewfile"
        "$default_dir/vscode/extensions.txt"
    )
    [[ "$profile_name" != "default" ]] && files_to_hash+=(
        "$profile_dir/Brewfile"
        "$profile_dir/vscode/extensions.txt"
    )

    local hash=""
    for f in "${files_to_hash[@]}"; do
        [[ -f "$f" ]] && hash+=$(md5 -q "$f" 2>/dev/null)
    done

    echo "$hash" > "$PROFILE_SNAPSHOT_FILE"
}

# --- Drift check (file-only, no subprocesses) ---

_profile_check_drift() {
    local active=$(_profile_active)
    [[ -z "$active" ]] && return 0
    [[ ! -f "$PROFILE_SNAPSHOT_FILE" ]] && return 0

    local default_dir="$PROFILES_DIR/default"
    local profile_dir="$PROFILES_DIR/$active"

    # Recompute hash of current profile files
    local -a files_to_hash=(
        "$default_dir/Brewfile"
        "$default_dir/vscode/extensions.txt"
    )
    [[ "$active" != "default" ]] && files_to_hash+=(
        "$profile_dir/Brewfile"
        "$profile_dir/vscode/extensions.txt"
    )

    local current_hash=""
    for f in "${files_to_hash[@]}"; do
        [[ -f "$f" ]] && current_hash+=$(md5 -q "$f" 2>/dev/null)
    done

    local stored_hash=$(cat "$PROFILE_SNAPSHOT_FILE" 2>/dev/null)

    if [[ "$current_hash" != "$stored_hash" ]]; then
        echo "⚠ Profile '$active' has unsynced changes. Run 'profile status' for details or 'profile switch $active' to apply."
    fi
}

# --- Apply functions ---

_profile_apply_brew() {
    local profile_name="$1"
    local default_brewfile="$PROFILES_DIR/default/Brewfile"
    local profile_brewfile="$PROFILES_DIR/$profile_name/Brewfile"

    if [[ ! -f "$default_brewfile" ]]; then
        echo "Brew: no default Brewfile found, skipping"
        return 0
    fi

    local tmpfile=$(mktemp)
    cat "$default_brewfile" > "$tmpfile"

    if [[ "$profile_name" != "default" && -f "$profile_brewfile" ]]; then
        echo "" >> "$tmpfile"
        cat "$profile_brewfile" >> "$tmpfile"
        echo "Applying Brewfile: default + $profile_name"
    else
        echo "Applying Brewfile: default"
    fi

    brew bundle --file="$tmpfile"
    rm -f "$tmpfile"
}

_profile_apply_vscode() {
    local profile_name="$1"
    local profile_dir="$PROFILES_DIR/$profile_name/vscode"
    local default_dir="$PROFILES_DIR/default/vscode"

    if [[ ! -d "$default_dir" && ! -d "$profile_dir" ]]; then
        return 0
    fi

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

    if [[ "$profile_name" == "default" ]]; then
        echo "Applying VSCode profile: default"
    else
        echo "Applying VSCode profile: default + $profile_name"
    fi
    echo "  Target: $vscode_user_dir"

    # Merge settings
    if [[ -f "$default_dir/settings.json" ]]; then
        if [[ -f "$profile_dir/settings.json" ]]; then
            jq -s '.[0] * .[1]' "$default_dir/settings.json" "$profile_dir/settings.json" \
                > "$vscode_user_dir/settings.json"
        else
            cp "$default_dir/settings.json" "$vscode_user_dir/settings.json"
        fi
        echo "  Settings merged"
    fi

    # Keybindings
    local kb_source="$default_dir/keybindings.json"
    [[ -f "$profile_dir/keybindings.json" ]] && kb_source="$profile_dir/keybindings.json"
    if [[ -f "$kb_source" ]]; then
        cp "$kb_source" "$vscode_user_dir/keybindings.json"
        echo "  Keybindings applied"
    fi

    # Extensions
    local -a desired_extensions=()
    for ext_file in "$default_dir/extensions.txt" "$profile_dir/extensions.txt"; do
        if [[ -f "$ext_file" ]]; then
            while IFS= read -r ext; do
                ext="${ext%%#*}"
                ext="${ext// /}"
                [[ -n "$ext" ]] && desired_extensions+=("$ext")
            done < "$ext_file"
        fi
    done

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

# --- Update (sync local state back to profile files) ---

_profile_update_brew() {
    local profile_name="$1"
    local default_brewfile="$PROFILES_DIR/default/Brewfile"
    local profile_brewfile="$PROFILES_DIR/$profile_name/Brewfile"

    echo "Syncing brew packages..."

    # Get currently installed
    local current_formulae=$(brew leaves 2>/dev/null | sort)
    local current_casks=$(brew list --cask 2>/dev/null | sort)

    # Get what's in the Brewfiles
    local default_expected=$(_profile_read_brew_packages "$default_brewfile")
    local profile_expected=""
    [[ "$profile_name" != "default" && -f "$profile_brewfile" ]] && \
        profile_expected=$(_profile_read_brew_packages "$profile_brewfile")
    local all_expected=$(echo -e "${default_expected}\n${profile_expected}" | sort -u)

    # Build current set in same format
    local current_set=$( (echo "$current_formulae" | sed 's/^/brew:/'; echo "$current_casks" | sed 's/^/cask:/') | sort -u)

    # Find additions (installed but not in Brewfiles)
    local added=$(comm -23 <(echo "$current_set") <(echo "$all_expected"))
    # Find removals (in Brewfiles but not installed)
    local removed=$(comm -13 <(echo "$current_set") <(echo "$all_expected"))
    # Filter out taps from removed (we don't track tap removal)
    removed=$(echo "$removed" | grep -v "^tap:")

    if [[ -z "$added" && -z "$removed" ]]; then
        echo "  Brew packages are in sync"
        return 0
    fi

    if [[ -n "$added" ]]; then
        echo "  New packages to add to profile:"
        echo "$added" | sed 's/^/    + /'
        # Append to profile Brewfile (or default if profile is default)
        local target="$profile_brewfile"
        [[ "$profile_name" == "default" ]] && target="$default_brewfile"
        for pkg in ${(f)added}; do
            local type="${pkg%%:*}"
            local name="${pkg#*:}"
            echo "$type \"$name\"" >> "$target"
        done
        echo "  Written to $(basename "$(dirname "$target")")/Brewfile"
    fi

    if [[ -n "$removed" ]]; then
        echo "  Packages removed locally:"
        echo "$removed" | sed 's/^/    - /'
        # Remove from whichever Brewfile contains them
        for pkg in ${(f)removed}; do
            local type="${pkg%%:*}"
            local name="${pkg#*:}"
            local pattern="^${type} \"${name}\""
            if grep -q "$pattern" "$default_brewfile" 2>/dev/null; then
                sed -i '' "/$pattern/d" "$default_brewfile"
            fi
            if [[ -f "$profile_brewfile" ]] && grep -q "$pattern" "$profile_brewfile" 2>/dev/null; then
                sed -i '' "/$pattern/d" "$profile_brewfile"
            fi
        done
        echo "  Removed from Brewfiles"
    fi
}

_profile_update_vscode() {
    local profile_name="$1"
    local default_ext="$PROFILES_DIR/default/vscode/extensions.txt"
    local profile_ext="$PROFILES_DIR/$profile_name/vscode/extensions.txt"

    local vscode_cli
    vscode_cli=$(_profile_find_vscode_cli)
    if [[ $? -ne 0 ]]; then
        echo "VSCode: no CLI found, skipping extension sync"
        return 0
    fi

    echo "Syncing VSCode extensions..."

    local current=$("$vscode_cli" --list-extensions 2>/dev/null | sort)
    local expected=$(_profile_read_extensions "$default_ext" "$profile_ext")

    local added=$(comm -23 <(echo "$current") <(echo "$expected"))
    local removed=$(comm -13 <(echo "$current") <(echo "$expected"))

    if [[ -z "$added" && -z "$removed" ]]; then
        echo "  Extensions are in sync"
        return 0
    fi

    if [[ -n "$added" ]]; then
        echo "  New extensions to add to profile:"
        echo "$added" | sed 's/^/    + /'
        local target="$profile_ext"
        [[ "$profile_name" == "default" || ! -d "$(dirname $profile_ext)" ]] && target="$default_ext"
        for ext in ${(f)added}; do
            echo "$ext" >> "$target"
        done
        echo "  Written to $(basename "$(dirname "$(dirname "$target")")")/vscode/extensions.txt"
    fi

    if [[ -n "$removed" ]]; then
        echo "  Extensions removed locally:"
        echo "$removed" | sed 's/^/    - /'
        for ext in ${(f)removed}; do
            if grep -qi "^${ext}$" "$default_ext" 2>/dev/null; then
                sed -i '' "/^${ext}$/Id" "$default_ext"
            fi
            if [[ -f "$profile_ext" ]] && grep -qi "^${ext}$" "$profile_ext" 2>/dev/null; then
                sed -i '' "/^${ext}$/Id" "$profile_ext"
            fi
        done
        echo "  Removed from extensions.txt"
    fi
}

# --- iTerm ---

_profile_apply_iterm() {
    local profile_name="$1"
    local default_iterm="$PROFILES_DIR/default/iterm/profile.json"
    local profile_iterm="$PROFILES_DIR/$profile_name/iterm/profile.json"
    local dynamic_dir="$HOME/Library/Application Support/iTerm2/DynamicProfiles"

    # Skip if no iTerm config exists
    if [[ ! -f "$default_iterm" && ! -f "$profile_iterm" ]]; then
        return 0
    fi

    # Skip if iTerm2 isn't installed
    if [[ ! -d "$HOME/Library/Application Support/iTerm2" ]]; then
        return 0
    fi

    mkdir -p "$dynamic_dir"

    if [[ "$profile_name" != "default" && -f "$profile_iterm" ]]; then
        # Merge: default profile object + profile overrides, then re-wrap
        jq -s '{"Profiles": [.[0].Profiles[0] * .[1].Profiles[0]]}' \
            "$default_iterm" "$profile_iterm" > "$dynamic_dir/dotfiles.json"
        echo "Applying iTerm profile: default + $profile_name"
    elif [[ -f "$default_iterm" ]]; then
        cp "$default_iterm" "$dynamic_dir/dotfiles.json"
        echo "Applying iTerm profile: default"
    fi
}

# --- Status ---

_profile_status() {
    local active=$(_profile_active)
    if [[ -z "$active" ]]; then
        echo "No active profile. Run 'profile switch <name>' first."
        return 0
    fi

    echo "Active profile: $active"

    if [[ ! -f "$PROFILE_SNAPSHOT_FILE" ]]; then
        echo "No snapshot found. Run 'profile switch $active' to create one."
        return 0
    fi

    local default_dir="$PROFILES_DIR/default"
    local profile_dir="$PROFILES_DIR/$active"

    # Brew drift
    local -a brewfiles=("$default_dir/Brewfile")
    [[ "$active" != "default" && -f "$profile_dir/Brewfile" ]] && brewfiles+=("$profile_dir/Brewfile")
    local expected_brew=$(_profile_read_brew_packages "${brewfiles[@]}")
    local snap_brew=$(jq -r '(.brew[] | "brew:" + .), (.casks[] | "cask:" + .)' "$PROFILE_SNAPSHOT_FILE" 2>/dev/null | sort -u)

    local brew_added=$(comm -23 <(echo "$snap_brew") <(echo "$expected_brew"))
    local brew_removed=$(comm -13 <(echo "$snap_brew") <(echo "$expected_brew"))
    # Filter taps
    brew_removed=$(echo "$brew_removed" | grep -v "^tap:")

    # Extension drift
    local -a extfiles=("$default_dir/vscode/extensions.txt")
    [[ "$active" != "default" && -f "$profile_dir/vscode/extensions.txt" ]] && \
        extfiles+=("$profile_dir/vscode/extensions.txt")
    local expected_ext=$(_profile_read_extensions "${extfiles[@]}")
    local snap_ext=$(jq -r '.extensions[]' "$PROFILE_SNAPSHOT_FILE" 2>/dev/null | sort -u)

    local ext_added=$(comm -23 <(echo "$snap_ext") <(echo "$expected_ext"))
    local ext_removed=$(comm -13 <(echo "$snap_ext") <(echo "$expected_ext"))

    if [[ -z "$brew_added" && -z "$brew_removed" && -z "$ext_added" && -z "$ext_removed" ]]; then
        echo "Everything is in sync."
        return 0
    fi

    echo ""
    if [[ -n "$brew_added" ]]; then
        echo "Brew packages installed but not in profile:"
        echo "$brew_added" | sed 's/^/  + /'
    fi
    if [[ -n "$brew_removed" ]]; then
        echo "Brew packages in profile but not installed:"
        echo "$brew_removed" | sed 's/^/  - /'
    fi
    if [[ -n "$ext_added" ]]; then
        echo "Extensions installed but not in profile:"
        echo "$ext_added" | sed 's/^/  + /'
    fi
    if [[ -n "$ext_removed" ]]; then
        echo "Extensions in profile but not installed:"
        echo "$ext_removed" | sed 's/^/  - /'
    fi
    echo ""
    echo "Run 'profile update' to sync changes back to profile files."
}

# --- Main entry point ---

profile() {
    local subcmd="${1:-help}"
    shift 2>/dev/null

    case "$subcmd" in
        switch|s)
            local profile_name="$1"
            if [[ -z "$profile_name" ]]; then
                echo "Usage: profile switch <name>"
                return 1
            fi
            if [[ ! -d "$PROFILES_DIR/$profile_name" ]]; then
                echo "Error: profile '$profile_name' not found" >&2
                return 1
            fi
            _profile_apply_brew "$profile_name"
            _profile_apply_vscode "$profile_name"
            _profile_apply_iterm "$profile_name"
            echo "$profile_name" > "$PROFILE_ACTIVE_FILE"
            echo "Taking snapshot..."
            _profile_take_snapshot "$profile_name"
            echo "Profile '$profile_name' is now active."
            ;;
        update|u)
            local profile_name="${1:-$(_profile_active)}"
            if [[ -z "$profile_name" ]]; then
                echo "No active profile. Specify one: profile update <name>"
                return 1
            fi
            if [[ ! -d "$PROFILES_DIR/$profile_name" ]]; then
                echo "Error: profile '$profile_name' not found" >&2
                return 1
            fi
            _profile_update_brew "$profile_name"
            _profile_update_vscode "$profile_name"
            echo "Taking snapshot..."
            _profile_take_snapshot "$profile_name"
            echo "Profile '$profile_name' updated."
            ;;
        status|st)
            _profile_status
            ;;
        help|*)
            echo "Usage: profile <command> [args]"
            echo ""
            echo "Commands:"
            echo "  switch <name>   (s)   Apply a profile (brew + vscode)"
            echo "  update [name]   (u)   Sync local changes back to profile files"
            echo "  status          (st)  Show active profile and drift"
            echo ""
            echo "Available profiles:"
            for dir in "$PROFILES_DIR"/*/; do
                local name=$(basename "$dir")
                local marker=""
                [[ "$name" == "$(_profile_active)" ]] && marker=" (active)"
                echo "  $name$marker"
            done
            ;;
    esac
}
