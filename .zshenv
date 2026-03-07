# .zshenv - sourced by ALL shells (keep minimal, no commands that produce output)

# zprof - uncomment to profile shell startup
# zmodload zsh/zprof

### Editor
export EDITOR='code-insiders --wait'

### Colour ls
typeset -xg CLICOLOR=1

### mise
export MISE_NODE_COREPACK=1
export MISE_GO_SET_GOBIN=true

### Homebrew
export HOMEBREW_AUTOREMOVE=1

### pnpm
export PNPM_HOME="$HOME/Library/pnpm"

### Build flags
export LDFLAGS="-L/opt/homebrew/opt/readline/lib"
export CPPFLAGS="-I/opt/homebrew/opt/readline/include"
