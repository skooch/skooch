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

if [ "$(uname)" != "Darwin" ]; then
    fail "macOS required"
    exit 1
fi
ok "macOS"

if ! command -v brew >/dev/null 2>&1; then
    fail "Homebrew not installed. Visit https://brew.sh"
    exit 1
fi
ok "Homebrew"

BREW_ZSH="/opt/homebrew/bin/zsh"
if [ ! -x "$BREW_ZSH" ]; then
    warn "Homebrew zsh not found at $BREW_ZSH — will be installed via profile"
else
    ok "Homebrew zsh"
    current_shell=$(dscl . -read /Users/"$(whoami)" UserShell 2>/dev/null | awk '{print $2}')
    if [ "$current_shell" = "$BREW_ZSH" ]; then
        ok "Default shell is Homebrew zsh"
    else
        warn "Default shell is $current_shell, not $BREW_ZSH"
        printf "  Run: chsh -s %s\n" "$BREW_ZSH"
    fi
fi

if [ ! -d "$DOTFILES_DIR" ]; then
    fail "Dotfiles repo not found at $DOTFILES_DIR"
    exit 1
fi
ok "Dotfiles repo"

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

link() {
    src="$1"
    dst="$2"
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
        ok "$dst -> $src (already correct)"
    else
        if [ -e "$dst" ] && [ ! -L "$dst" ]; then
            mv "$dst" "$dst.bak"
            warn "Backed up existing $dst to $dst.bak"
        fi
        ln -sf "$src" "$dst"
        ok "$dst -> $src"
    fi
}

link_dir() {
    src="$1"
    dst="$2"
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
        ok "$dst -> $src (already correct)"
    else
        if [ -e "$dst" ] && [ ! -L "$dst" ]; then
            mv "$dst" "$dst.bak"
            warn "Backed up existing $dst to $dst.bak"
        fi
        ln -sfn "$src" "$dst"
        ok "$dst -> $src"
    fi
}

link "$DOTFILES_DIR/.zshenv" "$HOME/.zshenv"
link "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"
link "$DOTFILES_DIR/.zprofile" "$HOME/.zprofile"
link "$DOTFILES_DIR/.zsh_plugins.txt" "$HOME/.zsh_plugins.txt"
link_dir "$DOTFILES_DIR/functions" "$HOME/.zsh_functions"

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

echo ""

if [ "$all_good" = 1 ]; then
    echo "=== All good! ==="
    echo ""
    echo "Next steps:"
    echo "  1. Restart your shell"
    echo "  2. Run: profile switch <name>  (e.g. embedded, b, default)"
    echo "  3. Run: mise install"
else
    echo "=== Some issues found — see warnings above ==="
fi
