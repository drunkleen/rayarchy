#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")" && pwd -P)
command -v cargo >/dev/null || { echo "Rayarchy setup requires cargo" >&2; exit 1; }
if [[ "${1:-}" == "--check" ]]; then
  command -v systemctl >/dev/null || { echo "Rayarchy setup requires systemctl" >&2; exit 1; }
  test -f "$root/manifest.json" && test -f "$root/packaging/rayarchy.service"
  test -f "$root/plugin/src/RayarchyPanel.qml" && test -x "$root/setup.sh"
  echo "Rayarchy setup prerequisites are valid"
  exit 0
fi
cargo build --release --workspace --manifest-path "$root/Cargo.toml"
install -Dm755 "$root/target/release/rayarchy-daemon" "$HOME/.local/bin/rayarchy-daemon"
install -Dm755 "$root/target/release/rayarchy" "$HOME/.local/bin/rayarchy"
install -Dm644 "$root/packaging/rayarchy.service" "$HOME/.config/systemd/user/rayarchy.service"
systemctl --user daemon-reload
systemctl --user enable rayarchy.service
systemctl --user restart rayarchy.service
echo "Rayarchy backend installed. Open the Omarchy Rayarchy panel."
