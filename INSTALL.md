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
   This also applies the profile-managed Claude and durable Codex config under `~/.claude` and `~/.codex`.

4. Install runtimes managed by mise:
   ```sh
   mise install
   ```

5. Enable the local Git cache:
   ```sh
   profile cache on
   ```

   In interactive shells, read-only GitHub commands like `git clone`, `git fetch`, `git pull`, `git ls-remote`, `git submodule update`, and `git remote update` then use the cache automatically. `command git ...` bypasses the wrapper when needed.
   Use `profile cache status`, `profile cache off`, and `profile cache clear [repo]` to manage it later.

6. Add secrets to `~/projects/dotfiles-private/.zshrc.private` (sourced automatically by `.zshrc`)

7. (Optional) Install iTerm2 shell integration:
   ```sh
   curl -L https://iterm2.com/shell_integration/zsh -o ~/.iterm2_shell_integration.zsh
   ```
