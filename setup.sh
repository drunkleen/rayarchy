#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")" && pwd -P)
command -v cargo >/dev/null || { echo "Rayarchy setup requires cargo" >&2; exit 1; }
cargo build --release --workspace --manifest-path "$root/Cargo.toml"
install -Dm755 "$root/target/release/rayarchy-daemon" "$HOME/.local/bin/rayarchy-daemon"
install -Dm755 "$root/target/release/rayarchy" "$HOME/.local/bin/rayarchy"
install -Dm644 "$root/packaging/rayarchy.service" "$HOME/.config/systemd/user/rayarchy.service"
systemctl --user daemon-reload
systemctl --user enable --now rayarchy.service
echo "Rayarchy backend installed. Open the Omarchy Rayarchy panel."
