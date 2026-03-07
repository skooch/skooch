# Everything starts with a test because I want the flexibility of different binaries across different computers

### zprof
# zmodload zsh/zprof

### homebrew
[[ -s "/opt/homebrew/bin/brew" ]] && eval "$(/opt/homebrew/bin/brew shellenv)"

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

### mise
eval "$(/opt/homebrew/bin/mise activate zsh)"

### pnpm
export PNPM_HOME="$HOME/Library/pnpm"
# case ":$PATH:" in
#   *":$PNPM_HOME:"*) ;;
#   *) export PATH="$PNPM_HOME:$PATH" ;;
# esac

### android
[[ -s "$HOME/Library/Android/sdk" ]] && \
    export ANDROID_SDK_ROOT="$HOME/Library/Android/sdk" && \
    export PATH="$PATH:$HOME/Library/Android/sdk/cmdline-tools/latest/bin"

### direnv
command -v direnv >/dev/null && \
    eval "$(direnv hook zsh)"

### cargo/rust
[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"
