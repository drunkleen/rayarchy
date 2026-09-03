#!/usr/bin/env bash
# One-command Rayarchy installer / updater.
#
#   curl -fsSL https://github.com/drunkleen/rayarchy/raw/master/install.sh | bash
#   ~/.config/omarchy/plugins/com.drunkleen.rayarchy/install.sh   # update
#   ~/Projects/rayarchy/install.sh                               # dev install
#
# - Run from a source checkout (dev): symlinks that checkout into the plugin
#   dir and builds/installs from source (RAYARCHY_BUILD_FROM_SOURCE=1).
# - Otherwise: installs the plugin through omarchy and fetches the latest
#   GitHub release binaries (no Rust toolchain needed).
# Idempotent: safe to run again to update.
set -euo pipefail
repo="https://github.com/drunkleen/rayarchy"
target="${RAYARCHY_PLUGIN_DIR:-$HOME/.config/omarchy/plugins/com.drunkleen.rayarchy}"
script_dir=$(cd "$(dirname "$0")" && pwd -P)

# Dev install? The script is being run straight from a repo checkout.
is_dev=false
if [[ -f "$script_dir/manifest.json" ]] && [[ -d "$script_dir/.git" ]]; then
  is_dev=true
fi

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
elif [[ -d "$target" ]] && [[ ! -f "$target/manifest.json" ]] && [[ ! -L "$target" ]]; then
  echo "A non-Rayarchy item exists at $target; refusing to touch it." >&2
  exit 1
fi

# 2. Install the backend + enable the shell UI.
if [[ "$is_dev" == true ]]; then
  if [[ "$(realpath "$target" 2>/dev/null)" != "$script_dir" ]]; then
    echo "Symlinking the local checkout into the plugin dir (dev install)."
    rm -rf "$target"
    ln -s "$script_dir" "$target"
  else
    echo "Local checkout is already the active plugin (dev install)."
  fi
  echo "Building the backend from source…"
  RAYARCHY_BUILD_FROM_SOURCE=1 "$target/setup.sh"
else
  echo "Installing the latest release…"
  "$target/setup.sh"
fi

# 3. Report the installed version.
if command -v "$HOME/.local/bin/rayarchy" >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/rayarchy" ]]; then
  version=$("$HOME/.local/bin/rayarchy" --version 2>/dev/null || echo "unknown")
  echo
  echo "Rayarchy is installed ($version)."
else
  echo
  echo "Rayarchy is installed."
fi
echo "  Open it:  Super+space -> 'Rayarchy', click the ⛨ bar widget, or:"
echo "            omarchy-shell shell toggle com.drunkleen.rayarchy '{}'"
echo "  Update:   $target/install.sh   (or: omarchy plugin update com.drunkleen.rayarchy && $target/setup.sh)"