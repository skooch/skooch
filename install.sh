#!/bin/sh
# Dotfiles install script
# Symlinks config files, installs antidote, sets up git hooks, and verifies everything.

set -e

DOTFILES_DIR="$HOME/projects/skooch"
PRIVATE_DIR="$HOME/projects/dotfiles-private"

ok() { printf "  ✓ %s\n" "$1"; }
warn() { printf "  ⚠ %s\n" "$1"; }
fail() { printf "  ✗ %s\n" "$1"; }

echo "=== Dotfiles installer ==="
echo ""

# --- Prerequisites ---

echo "Checking prerequisites..."

OS="$(uname -s)"
if [ "$OS" != "Darwin" ] && [ "$OS" != "Linux" ]; then
    fail "macOS or Linux required"
    exit 1
fi
ok "$OS"

if [ ! -d "$DOTFILES_DIR" ]; then
    fail "Dotfiles repo not found at $DOTFILES_DIR"
    exit 1
fi
ok "Dotfiles repo"

echo ""

# --- Core tools ---

echo "Checking core tools..."

# Homebrew
if ! command -v brew >/dev/null 2>&1; then
    echo "  Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Activate brew for this session
    if [ "$OS" = "Darwin" ]; then
        if [ -s "/opt/homebrew/bin/brew" ]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        else
            eval "$(/usr/local/bin/brew shellenv)"
        fi
    else
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    fi
    ok "Homebrew installed"
else
    ok "Homebrew"
fi

BREW_PREFIX="$(brew --prefix)"

# Core formulae needed by the dotfiles themselves
for tool in git jq mise; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "  Installing $tool..."
        brew install "$tool"
        ok "$tool installed"
    else
        ok "$tool"
    fi
done

# Homebrew zsh
BREW_ZSH="$BREW_PREFIX/bin/zsh"
if [ ! -x "$BREW_ZSH" ]; then
    echo "  Installing Homebrew zsh..."
    brew install zsh
    ok "Homebrew zsh installed"
else
    ok "Homebrew zsh"
fi

if ! grep -qFx "$BREW_ZSH" /etc/shells 2>/dev/null; then
    echo "  Adding $BREW_ZSH to /etc/shells (requires sudo)..."
    echo "$BREW_ZSH" | sudo tee -a /etc/shells >/dev/null
    ok "Added to /etc/shells"
fi

if [ "$OS" = "Darwin" ]; then
    current_shell=$(dscl . -read /Users/"$(whoami)" UserShell 2>/dev/null | awk '{print $2}')
else
    current_shell=$(getent passwd "$(whoami)" | cut -d: -f7)
fi
if [ "$current_shell" = "$BREW_ZSH" ]; then
    ok "Default shell is Homebrew zsh"
else
    echo "  Setting login shell to $BREW_ZSH..."
    chsh -s "$BREW_ZSH"
    ok "Login shell set to Homebrew zsh"
fi

# git-lfs
if command -v git-lfs >/dev/null 2>&1; then
    git lfs install >/dev/null 2>&1
    ok "git-lfs initialized"
fi

echo ""

# --- Antidote ---

echo "Checking antidote..."
if [ ! -d "$HOME/.antidote" ]; then
    echo "  Installing antidote..."
    git clone --depth=1 https://github.com/mattmc3/antidote.git "$HOME/.antidote"
    ok "Antidote installed"
else
    ok "Antidote already installed"
fi

echo ""

# --- Symlinks ---

echo "Setting up symlinks..."
# Reuse the profile system's link logic (defined in lib/profile/)
"$BREW_ZSH" -c "source '$DOTFILES_DIR/lib/profile/index.sh' && _profile_ensure_links"
ok "Core symlinks verified"

echo ""

# --- Git hooks ---

echo "Setting up git hooks..."
HOOK_SRC="$DOTFILES_DIR/hooks/pre-commit"
HOOK_DST="$DOTFILES_DIR/.git/hooks/pre-commit"

if [ -f "$HOOK_SRC" ]; then
    cp "$HOOK_SRC" "$HOOK_DST"
    chmod +x "$HOOK_DST"
    ok "pre-commit hook installed"
else
    warn "No pre-commit hook found at $HOOK_SRC"
fi

echo ""

# --- Private dotfiles ---

echo "Checking private dotfiles..."
if [ -d "$PRIVATE_DIR" ]; then
    ok "Private repo found at $PRIVATE_DIR"
    if [ -f "$PRIVATE_DIR/.zshrc.private" ]; then
        ok ".zshrc.private exists"
    else
        warn ".zshrc.private not found — create it for secrets"
    fi
else
    warn "Private repo not found at $PRIVATE_DIR"
    printf "  Run: git clone https://github.com/skooch/dotfiles-private.git %s\n" "$PRIVATE_DIR"
fi

echo ""

# --- Verification ---

echo "Verifying installation..."

all_good=1

for f in .zshenv .zshrc .zprofile .zsh_plugins.txt; do
    if [ -L "$HOME/$f" ]; then
        ok "$HOME/$f symlinked"
    else
        fail "$HOME/$f not symlinked"
        all_good=0
    fi
done

if [ -L "$HOME/.zsh_functions" ]; then
    ok "$HOME/.zsh_functions symlinked"
else
    fail "$HOME/.zsh_functions not symlinked"
    all_good=0
fi

if [ -d "$HOME/.antidote" ]; then
    ok "Antidote present"
else
    fail "Antidote missing"
    all_good=0
fi

for tool in brew git jq mise; do
    if command -v "$tool" >/dev/null 2>&1; then
        ok "$tool available"
    else
        fail "$tool missing"
        all_good=0
    fi
done

echo ""

if [ "$all_good" = 1 ]; then
    echo "=== All good! ==="
    echo ""

    # Check hosts.json for recommended profiles
    HOSTS_FILE="$DOTFILES_DIR/hosts.json"
    recommended=""
    current_machine_id=""
    if [ -f "$HOSTS_FILE" ]; then
        current_machine_id=$("$BREW_ZSH" -c "source '$DOTFILES_DIR/lib/profile/index.sh' && _profile_machine_id" 2>/dev/null)
        if [ -n "$current_machine_id" ]; then
            recommended=$(jq -r --arg h "$current_machine_id" '.[$h] // empty | join(" ")' "$HOSTS_FILE" 2>/dev/null)
        fi
    fi

    echo "Next steps:"
    echo "  1. Restart your shell"
    if [ -n "$recommended" ]; then
        echo "  2. Run: profile use $recommended  (from hosts.json for $current_machine_id)"
    else
        echo "  2. Run: profile use <name> [name2 ...]  (e.g. embedded, b)"
    fi
    echo ""
    echo "Note: 'profile use' applies all profile configs (brew, vscode, git, mise, claude, codex, iterm, tmux)."
    echo "After initial setup, use 'profile sync' to reconcile changes in either direction."
else
    echo "=== Some issues found — see warnings above ==="
fi
