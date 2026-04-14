# Profile system - initialization, variables, and core setup

DOTFILES_DIR="$HOME/projects/skooch"
PROFILES_DIR="$DOTFILES_DIR/profiles"
HOSTS_FILE="$DOTFILES_DIR/hosts.json"

# Stable, privacy-preserving machine identifier (SHA-256 of hardware UUID, first 12 chars)
_profile_machine_id() {
    local uuid
    if [[ "$IS_MACOS" == true ]]; then
        uuid=$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformUUID/{print $4}')
    elif [[ -f /etc/machine-id ]]; then
        uuid=$(cat /etc/machine-id)
    else
        uuid=$(hostname)
    fi
    echo -n "$uuid" | _platform_sha256 | cut -c1-12
}

# XDG-compliant state directory
PROFILE_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
PROFILE_ACTIVE_FILE="$PROFILE_STATE_DIR/active"
PROFILE_SNAPSHOT_FILE="$PROFILE_STATE_DIR/snapshot"
PROFILE_CHECKPOINT_FILE="$PROFILE_STATE_DIR/checkpoint"
PROFILE_MANAGED_FILE="$PROFILE_STATE_DIR/managed"
PROFILE_SYNC_SKIPS_FILE="$PROFILE_STATE_DIR/sync_skips"
PROFILE_DRIFT_CACHE="$PROFILE_STATE_DIR/drift-cache"

# --- Migration from old paths ---
if [[ -f "$HOME/.profile_active" && ! -f "$PROFILE_ACTIVE_FILE" ]]; then
    mkdir -p "$PROFILE_STATE_DIR"
    mv "$HOME/.profile_active" "$PROFILE_ACTIVE_FILE"
    mv "$HOME/.profile_snapshot" "$PROFILE_SNAPSHOT_FILE" 2>/dev/null
fi

if [[ -f "$PROFILE_SNAPSHOT_FILE" && ! -f "$PROFILE_CHECKPOINT_FILE" ]]; then
    cp "$PROFILE_SNAPSHOT_FILE" "$PROFILE_CHECKPOINT_FILE"
fi

# --- Core symlinks ---

_profile_ensure_links() {
    # Ensures core dotfile symlinks exist. Safe to run repeatedly.
    local -A links=(
        ["$DOTFILES_DIR/.zshenv"]="$HOME/.zshenv"
        ["$DOTFILES_DIR/.zshrc"]="$HOME/.zshrc"
        ["$DOTFILES_DIR/.zprofile"]="$HOME/.zprofile"
        ["$DOTFILES_DIR/.zsh_plugins.txt"]="$HOME/.zsh_plugins.txt"
    )
    local -A dir_links=(
        ["$DOTFILES_DIR/functions"]="$HOME/.zsh_functions"
    )

    for src dst in "${(@kv)links}"; do
        if _profile_symlink_matches "$dst" "$src"; then
            continue
        fi
        if [[ -e "$dst" && ! -L "$dst" ]]; then
            mv "$dst" "$dst.bak"
            echo "Backed up existing $dst to $dst.bak"
        fi
        _profile_ln_s "$src" "$dst"
        echo "Linked $dst -> $src"
    done

    for src dst in "${(@kv)dir_links}"; do
        if _profile_symlink_matches "$dst" "$src"; then
            continue
        fi
        if [[ -e "$dst" && ! -L "$dst" ]]; then
            mv "$dst" "$dst.bak"
            echo "Backed up existing $dst to $dst.bak"
        fi
        _profile_ln_sn "$src" "$dst"
        echo "Linked $dst -> $src"
    done
}

# --- Dependency check ---

_profile_check_deps() {
    local -a missing=()
    for cmd in brew jq python3; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Missing required tools: ${missing[*]}" >&2
        echo "Run install.sh first, or install manually: brew install ${missing[*]}" >&2
        return 1
    fi
    return 0
}
