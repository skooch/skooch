# setting up

**Prerequisites:** macOS or Linux with [Homebrew](https://brew.sh/) installed (Linuxbrew on Linux).

1. Clone both repos:
   ```sh
   git clone https://github.com/skooch/skooch.git ~/projects/skooch
   git clone https://github.com/skooch/dotfiles-private.git ~/projects/dotfiles-private
   ```

2. Run the install script:
   ```sh
   ~/projects/skooch/install.sh
   ```
   This installs antidote, symlinks all dotfiles, sets up git hooks, and verifies everything.

3. Restart your shell, then apply a profile:
   ```sh
   profile use embedded   # or: profile s b  (default is always applied)
   ```

4. Install runtimes managed by mise:
   ```sh
   mise install
   ```

5. Add secrets to `~/projects/dotfiles-private/.zshrc.private` (sourced automatically by `.zshrc`)

6. (Optional) Install iTerm2 shell integration:
   ```sh
   curl -L https://iterm2.com/shell_integration/zsh -o ~/.iterm2_shell_integration.zsh
   ```
