# .zshrc - interactive shell config

### Interactive functions
# Git wrappers and `mise` bootstrap are loaded earlier from `.zshenv` so
# login and non-interactive shells behave the same way as interactive ones.
for f in "$HOME/.zsh_functions"/*.sh(N); do source "$f"; done

### Profile system
source "$HOME/projects/skooch/lib/profile/index.sh"

### Aliases
alias claude='claude --append-system-prompt-file ~/.claude/system-prompt.md'
alias p="pnpm"
alias code="code-insiders"
alias turbo="pnpx turbo"
alias vercel="pnpx vercel"
alias esp="source ~/esp/esp-idf/export.sh"

### Source private dotfiles (secrets, machine-specific config)
source ~/projects/dotfiles-private/.zshrc.private 2>/dev/null

### direnv
command -v direnv >/dev/null && eval "$(direnv hook zsh)"

### fzf
command -v fzf >/dev/null && eval "$(fzf --zsh)"

### iterm2 integration
test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"

### Completions (must run before antidote so plugins can register completions)
zstyle ':completion:*' completer _expand _complete _ignored _correct _approximate
zstyle ':completion:*' matcher-list '' 'm:{[:lower:]}={[:upper:]}' 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}'
if (( $+commands[gh] )); then
    local _gh_comp="${HOME}/.zcompcache/_gh"
    [[ -d "${HOME}/.zcompcache" ]] || mkdir -p "${HOME}/.zcompcache"
    if [[ ! -f "$_gh_comp" || "$_gh_comp" -ot "$(command -v gh)" ]]; then
        gh completion -s zsh >| "$_gh_comp"
    fi
    fpath=("${HOME}/.zcompcache" $fpath)
fi
autoload -Uz compinit
local _zcomp_mtime
_zcomp_mtime=$(stat -c %Y ~/.zcompdump 2>/dev/null || stat -f %m ~/.zcompdump 2>/dev/null || echo 0)
if (( $(date +%s) - _zcomp_mtime > 86400 )); then
    compinit
else
    compinit -C
fi

### Antidote plugin manager
if [[ -f "$HOME/.antidote/antidote.zsh" ]]; then
    source "$HOME/.antidote/antidote.zsh"
    antidote load
fi

### Autosuggestions performance
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE="20"
ZSH_AUTOSUGGEST_USE_ASYNC=1

### Profile drift check (async: shows cached result, refreshes in background)
if [[ -f "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/active" ]]; then
    _profile_check_drift_async
fi

# zprof - uncomment matching line in .zshenv to use
# zprof
export PATH="$HOME/.bun/bin:$PATH"

# Added by codebase-memory-mcp install
export PATH="$HOME/.local/bin:$PATH"
