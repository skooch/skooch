#!/usr/bin/env bash
set -euo pipefail

# Syncs installed Claude plugins to match enabledPlugins in settings.json.
# Installs missing plugins and uninstalls plugins not declared in settings.

SETTINGS="$HOME/.claude/settings.json"
INSTALLED="$HOME/.claude/plugins/installed_plugins.json"

if [[ ! -f "$SETTINGS" ]]; then
  echo "No settings.json found at $SETTINGS"
  exit 1
fi

declared=$(jq -r '.enabledPlugins // {} | keys[]' "$SETTINGS" | sort)
if [[ -f "$INSTALLED" ]]; then
  installed=$(jq -r '.plugins // {} | keys[]' "$INSTALLED" | sort)
else
  installed=""
fi

to_install=$(comm -23 <(echo "$declared") <(echo "$installed"))
to_remove=$(comm -13 <(echo "$declared") <(echo "$installed"))

changes=0

if [[ -n "$to_install" ]]; then
  count=$(echo "$to_install" | wc -l | tr -d ' ')
  echo "Installing $count missing plugin(s)..."
  while IFS= read -r plugin; do
    echo "  + $plugin"
    claude plugins install "$plugin" 2>&1 | sed 's/^/    /'
  done <<< "$to_install"
  changes=1
fi

if [[ -n "$to_remove" ]]; then
  count=$(echo "$to_remove" | wc -l | tr -d ' ')
  echo "Removing $count extra plugin(s)..."
  while IFS= read -r plugin; do
    echo "  - $plugin"
    claude plugins uninstall "$plugin" 2>&1 | sed 's/^/    /'
  done <<< "$to_remove"
  changes=1
fi

if [[ $changes -eq 0 ]]; then
  echo "Plugins in sync."
fi
