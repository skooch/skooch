# skooch's dotfiles

Personal dotfiles, symlinked from `~/projects/skooch` into `~/`. Requires macOS or Linux, Homebrew (or Linuxbrew), and Homebrew's zsh.

See [INSTALL.md](INSTALL.md) for setup instructions and [docs/path_helper.md](docs/path_helper.md) for macOS PATH behaviour.

## shell config layout

| File | When sourced | What goes here |
|------|-------------|----------------|
| `.zshenv` | Every shell | Env vars, PATH setup, quiet runtime bootstrap for command wrappers and Codex-safe `mise` activation |
| `.zprofile` | Login shells | Reserved for login-only hooks; must stay silent for automation |
| `.zshrc` | Interactive shells | Plugins (antidote), completions, aliases, interactive-only functions, Sonos utils |
| `.zsh_plugins.txt` | Via antidote | OMZ libs/theme/plugins + third-party zsh plugins |

## key tools

- **[mise](https://mise.jdx.dev/)** - runtime manager (replaces pyenv/rbenv/volta/nvm)
- **[antidote](https://getantidote.github.io/)** - zsh plugin manager, loads OMZ components selectively
- **[direnv](https://direnv.net/)** - per-directory environment variables
- **robbyrussell** theme via OMZ + antidote

## secrets

Machine-specific secrets live in a separate private repo at `~/projects/dotfiles-private/.zshrc.private`, sourced automatically by `.zshrc`.
