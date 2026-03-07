# setting up

**Prerequisites:** macOS with [Homebrew](https://brew.sh/) installed. Set Homebrew's zsh as your default shell:
```sh
chsh -s /opt/homebrew/bin/zsh
```

1. Clone both repos:
   ```sh
   git clone https://github.com/skooch/skooch.git ~/projects/skooch
   git clone https://github.com/skooch/dotfiles-private.git ~/projects/dotfiles-private
   ```

2. Install [antidote](https://getantidote.github.io/):
   ```sh
   git clone --depth=1 https://github.com/mattmc3/antidote.git ~/.antidote
   ```

3. Symlink dotfiles into your home directory:
   ```sh
   ln -sf ~/projects/skooch/.zshenv ~/.zshenv
   ln -sf ~/projects/skooch/.zshrc ~/.zshrc
   ln -sf ~/projects/skooch/.zprofile ~/.zprofile
   ln -sf ~/projects/skooch/.zsh_plugins.txt ~/.zsh_plugins.txt
   ln -sf ~/projects/skooch/.zsh_sonos.sh ~/.zsh_sonos.sh
   ```

4. Install the Brewfile:
   ```sh
   brew bundle --file=~/projects/skooch/Brewfile
   ```

5. Install runtimes managed by mise:
   ```sh
   mise install
   ```

6. Add secrets to `~/projects/dotfiles-private/.zshrc.private` (sourced automatically by `.zshrc`)

7. (Optional) Install iTerm2 shell integration:
   ```sh
   curl -L https://iterm2.com/shell_integration/zsh -o ~/.iterm2_shell_integration.zsh
   ```

8. Restart your shell
