# Everything starts with a test because I want the flexibility of different binaries across different computers

### zprof
# zmodload zsh/zprof

### homebrew
command -v brew >/dev/null && \
    eval "$(/opt/homebrew/bin/brew shellenv)"

### jetbrains toolbox
[[ -s "$HOME/Library/Application Support/JetBrains/Toolbox/scripts" ]] && \
    export PATH="$PATH:$HOME/Library/Application Support/JetBrains/Toolbox/scripts"

### rsync
# We have to account for versioning
setopt no_nullglob
rsync_glob=(/opt/homebrew/Cellar/rsync/*/bin/)
if [[ $? -eq 0 ]]; then
    export PATH="$PATH:$rsync_glob[1]"
fi
setopt nullglob

### orbstack
[[ -s "$HOME/.orbstack/shell/init.zsh" ]] && \
    source ~/.orbstack/shell/init.zsh 2>/dev/null || :

### pyenv
export PYENV_ROOT="$HOME/.pyenv"
command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
command -v pyenv >/dev/null && eval "$(pyenv init -)"

### pnpm
export PNPM_HOME="$HOME/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

### rbenv
command -v rbenv >/dev/null && \
    eval "$(rbenv init - zsh --no-rehash)"

### sdkman
# ensure to edit  ~/.sdkman/etc/config to turn off autocomplete
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && \
    export SDKMAN_DIR="$HOME/.sdkman" && \
    source "$HOME/.sdkman/bin/sdkman-init.sh"

### gvm
[[ -s "/Users/skooch/.gvm/scripts/gvm" ]] && \
    source "/Users/skooch/.gvm/scripts/gvm"

### android
[[ -s "$HOME/Library/Android/sdk" ]] && \
    export ANDROID_SDK_ROOT="$HOME/Library/Android/sdk" && \
    export PATH="$PATH:$HOME/Library/Android/sdk/cmdline-tools/latest/bin"

### direnv
command -v direnv >/dev/null && \
    eval "$(direnv hook zsh)"

### llvm
export PATH="/opt/homebrew/opt/llvm/bin:$PATH"

### volta
[[ -s "$HOME/.volta" ]] && \
    export VOLTA_HOME="$HOME/.volta" && \
    export PATH="$VOLTA_HOME/bin:$PATH"