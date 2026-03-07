# Profile switcher - applies dotfiles profiles (vscode, brew, etc.)

DOTFILES_DIR="$HOME/projects/skooch"
PROFILES_DIR="$DOTFILES_DIR/profiles"

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

profile() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: profile <name>"
        echo ""
        echo "Available profiles:"
        for dir in "$PROFILES_DIR"/*/; do
            local name=$(basename "$dir")
            [[ "$name" == "default" ]] && continue
            echo "  $name"
        done
        echo ""
        echo "Each profile is applied on top of the default profile."
        return 0
    fi

    local profile_name="$1"
    local profile_dir="$PROFILES_DIR/$profile_name"

    if [[ ! -d "$profile_dir" ]]; then
        echo "Error: profile '$profile_name' not found in $PROFILES_DIR" >&2
        return 1
    fi

    _profile_apply_brew "$profile_name"
    _profile_apply_vscode "$profile_name"
}

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

    # Skip if no vscode config exists for default or this profile
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

    # Merge settings: default as base, profile overlaid
    if [[ -f "$default_dir/settings.json" ]]; then
        if [[ -f "$profile_dir/settings.json" ]]; then
            jq -s '.[0] * .[1]' "$default_dir/settings.json" "$profile_dir/settings.json" \
                > "$vscode_user_dir/settings.json"
        else
            cp "$default_dir/settings.json" "$vscode_user_dir/settings.json"
        fi
        echo "  Settings merged"
    fi

    # Keybindings: profile overrides default if present
    local kb_source="$default_dir/keybindings.json"
    [[ -f "$profile_dir/keybindings.json" ]] && kb_source="$profile_dir/keybindings.json"
    if [[ -f "$kb_source" ]]; then
        cp "$kb_source" "$vscode_user_dir/keybindings.json"
        echo "  Keybindings applied"
    fi

    # Extensions: combine default + profile, install missing
    local -a desired_extensions=()
    for ext_file in "$default_dir/extensions.txt" "$profile_dir/extensions.txt"; do
        if [[ -f "$ext_file" ]]; then
            while IFS= read -r ext; do
                ext="${ext%%#*}"   # strip comments
                ext="${ext// /}"   # strip whitespace
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
