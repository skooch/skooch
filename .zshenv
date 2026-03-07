# .zshenv - sourced by ALL shells (env vars and PATH setup, no output)

# zprof - uncomment to profile shell startup
# zmodload zsh/zprof

### Homebrew (must come first so brew-installed tools are on PATH)
[[ -s "/opt/homebrew/bin/brew" ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
export HOMEBREW_AUTOREMOVE=1

### Editor
export EDITOR='code-insiders --wait'

### Colour ls
typeset -xg CLICOLOR=1

### mise
export MISE_NODE_COREPACK=1
export MISE_GO_SET_GOBIN=true

### pnpm
export PNPM_HOME="$HOME/Library/pnpm"

### Build flags
export LDFLAGS="-L/opt/homebrew/opt/readline/lib"
export CPPFLAGS="-I/opt/homebrew/opt/readline/include"

### cargo/rust
[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

### PATH additions
export PATH="$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH"

### GNU coreutils & grep (unprefixed)
[[ -d "/opt/homebrew/opt/coreutils/libexec/gnubin" ]] && export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"
[[ -d "/opt/homebrew/opt/grep/libexec/gnubin" ]] && export PATH="/opt/homebrew/opt/grep/libexec/gnubin:$PATH"

### libpq (Postgres CLI without full server)
[[ -d "/opt/homebrew/opt/libpq/bin" ]] && export PATH="/opt/homebrew/opt/libpq/bin:$PATH"

### OrbStack
[[ -s "$HOME/.orbstack/shell/init.zsh" ]] && \
    source ~/.orbstack/shell/init.zsh 2>/dev/null || :

### JetBrains Toolbox
[[ -s "$HOME/Library/Application Support/JetBrains/Toolbox/scripts" ]] && \
    export PATH="$PATH:$HOME/Library/Application Support/JetBrains/Toolbox/scripts"

### rsync (use Homebrew version)
rsync_glob=(/opt/homebrew/Cellar/rsync/*/bin/(N))
if [[ ${#rsync_glob} -gt 0 ]]; then
    export PATH="$PATH:$rsync_glob[1]"
fi

### Android SDK
[[ -s "$HOME/Library/Android/sdk" ]] && \
    export ANDROID_SDK_ROOT="$HOME/Library/Android/sdk" && \
    export PATH="$PATH:$HOME/Library/Android/sdk/cmdline-tools/latest/bin"
