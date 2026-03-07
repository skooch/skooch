# setting up

1. Clone both repos:
   ```sh
   git clone https://github.com/skooch/skooch.git ~/projects/skooch
   git clone https://github.com/skooch/dotfiles-private.git ~/projects/dotfiles-private
   ```

2. Symlink dotfiles into your home directory:
   ```sh
   ln -sf ~/projects/skooch/.zshenv ~/.zshenv
   ln -sf ~/projects/skooch/.zshrc ~/.zshrc
   ln -sf ~/projects/skooch/.zprofile ~/.zprofile
   ```

3. Install the Brewfile:
   ```sh
   brew bundle --file=~/projects/skooch/Brewfile
   ```

4. Add secrets to `~/projects/dotfiles-private/.zshrc.private` (sourced automatically by `.zshrc`)

5. Restart your shell
