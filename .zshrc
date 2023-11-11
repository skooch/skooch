### iterm2 integration
test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"

### compinstall completion style
zstyle ':completion:*' completer _expand _complete _ignored _correct _approximate
zstyle ':completion:*' matcher-list '' 'm:{[:lower:]}={[:upper:]}' 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}'

### zsh completions
autoload -Uz compinit bashcompinit
for dump in ~/.zcompdump(N.mh+24); do
  compinit
  bashcompinit
done
compinit -C

### colour ls
typeset -xg CLICOLOR=1

# zprof - comment back in in .zshenv first to use
# zprof