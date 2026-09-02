#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")" && pwd -P)
command -v install >/dev/null || { echo "Rayarchy setup requires install" >&2; exit 1; }
if [[ "${1:-}" == "--check" ]]; then
  command -v systemctl >/dev/null || { echo "Rayarchy setup requires systemctl" >&2; exit 1; }
  test -f "$root/manifest.json" && test -f "$root/packaging/rayarchy.service"
  test -f "$root/plugin/src/RayarchyPanel.qml" && test -x "$root/setup.sh"
  echo "Rayarchy setup prerequisites are valid"
  exit 0
fi
daemon_bin=""
cli_bin=""
release_tmp=""
if [[ "${RAYARCHY_BUILD_FROM_SOURCE:-0}" != "1" ]] && command -v curl >/dev/null && command -v tar >/dev/null && command -v sha256sum >/dev/null; then
  version=$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' "$root/manifest.json" | head -1)
  release_tmp=$(mktemp -d)
  archive="$release_tmp/rayarchy.tar.gz"
  checksum="$release_tmp/rayarchy.tar.gz.sha256"
  archive_url="https://github.com/drunkleen/rayarchy/releases/download/v${version}/rayarchy-v${version}-x86_64.tar.gz"
  checksum_url="${archive_url}.sha256"
  if curl -fsSL --connect-timeout 5 --max-time 30 "$archive_url" -o "$archive" \
    && curl -fsSL --connect-timeout 5 --max-time 30 "$checksum_url" -o "$checksum" \
    && (cd "$release_tmp" && sha256sum -c "$(basename "$checksum")" >/dev/null); then
    tar -xzf "$archive" -C "$release_tmp"
    daemon_bin="$release_tmp/rayarchy/rayarchy-daemon"
    cli_bin="$release_tmp/rayarchy/rayarchy"
    echo "Using Rayarchy v${version} release binaries"
  else
    echo "Release v${version} unavailable or checksum failed; building from source"
  fi
fi
if [[ -z "$daemon_bin" || -z "$cli_bin" ]]; then
  command -v cargo >/dev/null || { echo "Rayarchy setup requires cargo when no release is available" >&2; exit 1; }
  cargo build --release --workspace --manifest-path "$root/Cargo.toml"
  daemon_bin="$root/target/release/rayarchy-daemon"
  cli_bin="$root/target/release/rayarchy"
fi
install -Dm755 "$daemon_bin" "$HOME/.local/bin/rayarchy-daemon"
install -Dm755 "$cli_bin" "$HOME/.local/bin/rayarchy"
install -Dm644 "$root/packaging/rayarchy.service" "$HOME/.config/systemd/user/rayarchy.service"
systemctl --user daemon-reload
systemctl --user enable rayarchy.service
systemctl --user restart rayarchy.service
[[ -n "$release_tmp" ]] && rm -rf "$release_tmp"
echo "Rayarchy backend installed. Open the Omarchy Rayarchy panel."
