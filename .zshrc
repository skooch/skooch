### iterm2 integration
test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"

### Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
zstyle ':omz:update' mode auto

# Performance
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE="20"
ZSH_AUTOSUGGEST_USE_ASYNC=1
COMPLETION_WAITING_DOTS="true"

plugins=(
  git
  gh
  history-substring-search
  aliases
)

source $ZSH/oh-my-zsh.sh

### compinstall completion style
zstyle ':completion:*' completer _expand _complete _ignored _correct _approximate
zstyle ':completion:*' matcher-list '' 'm:{[:lower:]}={[:upper:]}' 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}'

### zsh completions
autoload -Uz compinit
if [ "$(date +'%j')" != "$(stat -f '%Sm' -t '%j' ~/.zcompdump 2>/dev/null)" ]; then
    compinit
else
    compinit -C
fi

### colour ls
typeset -xg CLICOLOR=1

### PATH additions
export PATH="$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH"
export PATH="/opt/homebrew/opt/libpq/bin:$PATH"

### EDITOR
export EDITOR='code-insiders --wait'

### refresh dns
refreshdns() {
    sudo dscacheutil -flushcache
    sudo killall -HUP mDNSResponder
}

### trifecta
trifecta() {
    git add -u
    git commit --amend --no-edit
    git push --force
}

### listening
listening() {
    if [ $# -eq 0 ]; then
        sudo lsof -iTCP -sTCP:LISTEN -n -P
    elif [ $# -eq 1 ]; then
        sudo lsof -iTCP -sTCP:LISTEN -n -P | grep -i --color $1
    else
        echo "Usage: listening [pattern]"
    fi
}

### Sonos utilities
check_if_refresh_sonos() {
  local SPEAKERS_MODIFIED=$(date -r /Users/skooch/.soco-cli/speakers_v2.pickle +%s)
  local CURRENT_DATE=$(date +%s)
  local DIFFERENCE=$(($CURRENT_DATE - $SPEAKERS_MODIFIED))
  if [ $DIFFERENCE -gt 43200 ]; then
    echo "One moment, updating sonos speaker list..."
    sonos-discover -t 256 -n 1.0 -m 24 >> /dev/null
  fi
}

stfu-list() {
  check_if_refresh_sonos
  echo "Your currently available speakers are:"
  sonos-discover -p | tail -n +6
}

stfu() {
  check_if_refresh_sonos
  echo "Shushing all Sonos speakers..."
  sonos _all_ vol 0
}

stfu-eng() {
  check_if_refresh_sonos
  echo "Shushing eng speakers..."
  sonos "Engineering & Product" vol 0
}

stfu-kitchen() {
  check_if_refresh_sonos
  echo "Shushing kitchen speakers..."
  sonos "Kitchen" vol 0
}

stfu-allhands() {
  check_if_refresh_sonos
  echo "Shushing all hands speakers..."
  sonos "All Hands" vol 0
}

unstfu() {
  check_if_refresh_sonos
  echo "Restoring volume on all Sonos speakers..."
  sonos _all_ vol 30
}

stfu-play() {
  sonos kitchen play_sharelink $1
}

stfu-nowplaying() {
  sonos kitchen track | tail -n +3
}

### Aliases
alias p="pnpm"
alias code="code-insiders"
alias turbo="pnpx turbo"
alias vercel="pnpx vercel"

### Source private dotfiles (secrets, machine-specific config)
source ~/projects/dotfiles-private/.zshrc.private 2>/dev/null

# zprof - comment back in in .zshenv first to use
# zprof
