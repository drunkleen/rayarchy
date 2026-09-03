#!/usr/bin/env bash
# One-command Rayarchy installer / updater.
#
#   curl -fsSL https://github.com/drunkleen/rayarchy/raw/master/install.sh | bash
#   ~/.config/omarchy/plugins/com.drunkleen.rayarchy/install.sh   # update
#
# Installs the shell plugin (if missing), then the backend + shell integration.
# Idempotent: safe to run again to update.
set -euo pipefail
repo="https://github.com/drunkleen/rayarchy"
target="${RAYARCHY_PLUGIN_DIR:-$HOME/.config/omarchy/plugins/com.drunkleen.rayarchy}"

# 1. Make sure the plugin is present.
if [[ ! -e "$target" ]]; then
  echo "Installing the Rayarchy plugin into $target …"
  if command -v omarchy >/dev/null 2>&1; then
    omarchy plugin add "$repo" --enable --yes
  else
    command -v git >/dev/null || { echo "install needs git or omarchy" >&2; exit 1; }
    git clone --depth 1 "$repo" "$target"
    if command -v omarchy-shell >/dev/null 2>&1; then
      omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
    fi
  fi
elif [[ -L "$target" ]] || [[ -d "$target/.git" ]] || [[ -f "$target/manifest.json" ]]; then
  echo "Rayarchy plugin already present at $target; keeping it."
else
  echo "A non-Rayarchy item exists at $target; refusing to touch it." >&2
  exit 1
fi

# 2. Install the backend + enable the shell UI (binaries, systemd, bar widget,
#    launcher entry). setup.sh is idempotent and rebuilds/restarts the daemon.
echo "Running the backend + shell setup…"
"$target/setup.sh"

echo
echo "Rayarchy is installed."
echo "  Open it:  Super+space -> 'Rayarchy', click the ⛨ bar widget, or:"
echo "            omarchy-shell shell toggle com.drunkleen.rayarchy '{}'"
echo "  Update:   $target/install.sh   (or: omarchy plugin update com.drunkleen.rayarchy && $target/setup.sh)"