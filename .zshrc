# .zshrc - interactive shell config

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

### Profile drift check
if [[ -f "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/active" ]]; then
    _profile_check_drift
fi

# zprof - uncomment matching line in .zshenv to use
# zprof
