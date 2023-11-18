# skooch's configuration

This is all the stuff I use, requires brew to be installed and shell reconfigured to homebrew's zsh.

[If you want to understand the behaviour I use, read the path_helper doc.](path_helper.md)

## what's in it

### homebrew

* hashicorp/tap
* homebrew/autoupdate
* homebrew/bundle
* cmake
* coreutils
* direnv
* docker
* docker-buildx
* docker-compose
* gcc
* git-lfs
* llvm
* minikube
* mtr
* pyenv
* rbenv
* rsync
* watch
* wget
* zsh
* hashicorp/tap/terraform
* orbstack

### zsh

I like to have my shells to have the same environment regardless if they're interactive or not. Only interactive shells get inclusions that affect interactivity.

Because of path_helper on macos, I only use `.zshrc` and `.zshenv`. `.zprofile` will warn you if you accidentally run a login shell.

#### `.zshenv`

* zprof
* homebrew
* jetbrains toolbox
* rsync
* orbstack
* pyenv
* pnpm
* pnpm end
* rbenv
* sdkman
* android
* direnv
* llvm
* volta

#### `.zshrc`

* iterm2 integration
* compinstall completion style
* zsh completions
* colour ls