# .zshrc - interactive shell config

### iterm2 integration
test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"

### Completions (must run before antidote so plugins can register completions)
zstyle ':completion:*' completer _expand _complete _ignored _correct _approximate
zstyle ':completion:*' matcher-list '' 'm:{[:lower:]}={[:upper:]}' 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}'
autoload -Uz compinit
if [ "$(date +'%j')" != "$(stat -f '%Sm' -t '%j' ~/.zcompdump 2>/dev/null)" ]; then
    compinit
else
    compinit -C
fi

### Antidote plugin manager
source "$HOME/.antidote/antidote.zsh"
antidote load

### Autosuggestions performance
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE="20"
ZSH_AUTOSUGGEST_USE_ASYNC=1

### Functions
for f in "$HOME/.zsh_functions"/*.sh(N); do source "$f"; done

### Profile drift check
if [[ -f "$HOME/.profile_active" && -f "$HOME/.profile_snapshot" ]]; then
    _profile_check_drift
fi

### Aliases
alias p="pnpm"
alias code="code-insiders"
alias turbo="pnpx turbo"
alias vercel="pnpx vercel"
alias esp="source ~/esp/esp-idf/export.sh"

### Source private dotfiles (secrets, machine-specific config)
source ~/projects/dotfiles-private/.zshrc.private 2>/dev/null

# zprof - uncomment matching line in .zshenv to use
# zprof
