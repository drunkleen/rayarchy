#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")" && pwd -P)
command -v install >/dev/null || { echo "Rayarchy setup requires install" >&2; exit 1; }
if [[ "${1:-}" == "--check" ]]; then
  command -v systemctl >/dev/null || { echo "Rayarchy setup requires systemctl" >&2; exit 1; }
  test -f "$root/manifest.json" && test -f "$root/packaging/rayarchy.service"
  test -f "$root/crates/rayarchy-daemon/src/main.rs" && test -x "$root/setup.sh"
  echo "Rayarchy setup prerequisites are valid"
  exit 0
fi
daemon_bin=""
cli_bin=""
helper_bin=""
release_tmp=""
# Install from the latest published release (SHA-256 verified); only build from
# source when RAYARCHY_BUILD_FROM_SOURCE=1 (dev) or no release exists yet.
if [[ "${RAYARCHY_BUILD_FROM_SOURCE:-0}" != "1" ]] && command -v curl >/dev/null && command -v tar >/dev/null && command -v sha256sum >/dev/null && command -v jq >/dev/null; then
  release_tmp=$(mktemp -d)
  archive="$release_tmp/rayarchy.tar.gz"
  checksum="$release_tmp/rayarchy.tar.gz.sha256"
  release_tag=$(curl -fsSL --connect-timeout 5 --max-time 15 https://api.github.com/repos/drunkleen/rayarchy/releases/latest | jq -r '.tag_name // empty' || true)
  if [[ -n "$release_tag" ]]; then
    archive_url="https://github.com/drunkleen/rayarchy/releases/download/${release_tag}/rayarchy-${release_tag}-x86_64.tar.gz"
    checksum_url="${archive_url}.sha256"
    if curl -fsSL --connect-timeout 5 --max-time 30 "$archive_url" -o "$archive" \
      && curl -fsSL --connect-timeout 5 --max-time 30 "$checksum_url" -o "$checksum" \
      && (cd "$release_tmp" && sha256sum -c "$(basename "$checksum")" >/dev/null); then
      tar -xzf "$archive" -C "$release_tmp"
      daemon_bin="$release_tmp/rayarchy/rayarchy-daemon"
      cli_bin="$release_tmp/rayarchy/rayarchy"
      helper_bin="$release_tmp/rayarchy/rayarchy-helper"
      echo "Installing Rayarchy ${release_tag} release binaries"
    else
      echo "Release ${release_tag} archive unavailable or checksum failed; building from source"
    fi
  else
    echo "No GitHub release found; building from source"
  fi
fi
if [[ -z "$daemon_bin" || -z "$cli_bin" ]]; then
  command -v cargo >/dev/null || { echo "Rayarchy setup requires cargo when no release is available" >&2; exit 1; }
  cargo build --release --workspace --manifest-path "$root/Cargo.toml"
  daemon_bin="$root/target/release/rayarchy-daemon"
  cli_bin="$root/target/release/rayarchy"
  helper_bin="$root/target/release/rayarchy-helper"
fi
install -Dm755 "$daemon_bin" "$HOME/.local/bin/rayarchy-daemon"
install -Dm755 "$cli_bin" "$HOME/.local/bin/rayarchy"
[[ -n "$helper_bin" ]] && [[ -f "$helper_bin" ]] && install -Dm755 "$helper_bin" "$HOME/.local/bin/rayarchy-helper"
install -Dm644 "$root/packaging/rayarchy.service" "$HOME/.config/systemd/user/rayarchy.service"
systemctl --user daemon-reload
systemctl --user enable rayarchy.service
systemctl --user restart rayarchy.service

[[ -n "$release_tmp" ]] && rm -rf "$release_tmp"
echo "Rayarchy backend installed."
echo "  CLI:    ~/.local/bin/rayarchy status"
echo "  UI:     the ⛨ bar widget or: omarchy-shell shell toggle com.drunkleen.rayarchy '{}'"
echo "  Logs:   journalctl --user -u rayarchy -f"
