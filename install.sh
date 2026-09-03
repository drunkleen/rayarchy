#!/usr/bin/env bash
# One-command Rayarchy installer / updater.
#
#   curl -fsSL https://github.com/drunkleen/rayarchy/raw/master/install.sh | bash
#
# 1. Adds the shell plugin (UI + bar widget) via omarchy plugin add.
# 2. Runs setup.sh to install the backend binaries and user service.
# Idempotent: safe to run again to update.
set -euo pipefail
repo="https://github.com/drunkleen/rayarchy"
target="${RAYARCHY_PLUGIN_DIR:-$HOME/.config/omarchy/plugins/com.drunkleen.rayarchy}"

if [[ ! -e "$target" ]]; then
  if command -v omarchy >/dev/null 2>&1; then
    omarchy plugin add "$repo" --enable --yes
  else
    echo "install needs omarchy; alternatively clone the repo into $target" >&2
    exit 1
  fi
fi

"$target/setup.sh"

echo
echo "Rayarchy is installed."
echo "  Open it:  Super+space -> 'Rayarchy', click the ⛨ bar widget, or:"
echo "            omarchy-shell shell toggle com.drunkleen.rayarchy '{}'"