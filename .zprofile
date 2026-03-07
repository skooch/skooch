# .zprofile - sourced once at login (heavy init goes here)

### Homebrew
[[ -s "/opt/homebrew/bin/brew" ]] && eval "$(/opt/homebrew/bin/brew shellenv)"

### mise
command -v mise >/dev/null && eval "$(mise activate zsh)"

### direnv
command -v direnv >/dev/null && eval "$(direnv hook zsh)"

### cargo/rust
[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

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

### libpq (Postgres CLI without full server)
[[ -d "/opt/homebrew/opt/libpq/bin" ]] && export PATH="/opt/homebrew/opt/libpq/bin:$PATH"

### PATH additions
export PATH="$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH"

### Functions
for f in "$HOME/.zsh_functions"/*.sh(N); do source "$f"; done

### Aliases
alias p="pnpm"
alias code="code-insiders"
alias turbo="pnpx turbo"
alias vercel="pnpx vercel"
alias esp="source ~/esp/esp-idf/export.sh"

### Source private dotfiles (secrets, machine-specific config)
source ~/projects/dotfiles-private/.zshrc.private 2>/dev/null
