# .zshenv - sourced by ALL shells (env vars and PATH setup, no output)

# zprof - uncomment to profile shell startup
# zmodload zsh/zprof

### Homebrew (must come first so brew-installed tools are on PATH)
if [[ -s "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -s "/home/linuxbrew/.linuxbrew/bin/brew" ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [[ -s "/usr/local/bin/brew" ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi
export HOMEBREW_AUTOREMOVE=1

### Editor
export EDITOR='code-insiders --wait'

### Colour ls
typeset -xg CLICOLOR=1

### mise
export MISE_NODE_COREPACK=1
export MISE_GO_SET_GOBIN=true

### pnpm
if [[ "$(uname -s)" == "Darwin" ]]; then
    export PNPM_HOME="$HOME/Library/pnpm"
else
    export PNPM_HOME="$HOME/.local/share/pnpm"
fi

### Build flags (only when brew readline is present)
if [[ -n "${HOMEBREW_PREFIX:-}" && -d "$HOMEBREW_PREFIX/opt/readline" ]]; then
    export LDFLAGS="-L$HOMEBREW_PREFIX/opt/readline/lib"
    export CPPFLAGS="-I$HOMEBREW_PREFIX/opt/readline/include"
fi

### cargo/rust
[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

### PATH additions
export PATH="$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH"

### GNU coreutils & grep (macOS only — Linux has these natively)
if [[ "$(uname -s)" == "Darwin" && -n "${HOMEBREW_PREFIX:-}" ]]; then
    [[ -d "$HOMEBREW_PREFIX/opt/coreutils/libexec/gnubin" ]] && export PATH="$HOMEBREW_PREFIX/opt/coreutils/libexec/gnubin:$PATH"
    [[ -d "$HOMEBREW_PREFIX/opt/grep/libexec/gnubin" ]] && export PATH="$HOMEBREW_PREFIX/opt/grep/libexec/gnubin:$PATH"
fi

### libpq (Postgres CLI without full server)
[[ -n "${HOMEBREW_PREFIX:-}" && -d "$HOMEBREW_PREFIX/opt/libpq/bin" ]] && export PATH="$HOMEBREW_PREFIX/opt/libpq/bin:$PATH"

### OrbStack (macOS only)
[[ -s "$HOME/.orbstack/shell/init.zsh" ]] && \
    source ~/.orbstack/shell/init.zsh 2>/dev/null || :

### JetBrains Toolbox
if [[ "$(uname -s)" == "Darwin" ]]; then
    [[ -d "$HOME/Library/Application Support/JetBrains/Toolbox/scripts" ]] && \
        export PATH="$PATH:$HOME/Library/Application Support/JetBrains/Toolbox/scripts"
else
    [[ -d "$HOME/.local/share/JetBrains/Toolbox/scripts" ]] && \
        export PATH="$PATH:$HOME/.local/share/JetBrains/Toolbox/scripts"
fi

### rsync (use Homebrew version on macOS — Linux rsync is modern)
if [[ "$(uname -s)" == "Darwin" ]]; then
    rsync_glob=(${HOMEBREW_PREFIX:-/opt/homebrew}/Cellar/rsync/*/bin/(N))
    if [[ ${#rsync_glob} -gt 0 ]]; then
        export PATH="$PATH:$rsync_glob[1]"
    fi
fi

### Android SDK
if [[ "$(uname -s)" == "Darwin" ]]; then
    [[ -d "$HOME/Library/Android/sdk" ]] && \
        export ANDROID_SDK_ROOT="$HOME/Library/Android/sdk" && \
        export PATH="$PATH:$HOME/Library/Android/sdk/cmdline-tools/latest/bin"
else
    [[ -d "$HOME/Android/Sdk" ]] && \
        export ANDROID_SDK_ROOT="$HOME/Android/Sdk" && \
        export PATH="$PATH:$HOME/Android/Sdk/cmdline-tools/latest/bin"
fi
