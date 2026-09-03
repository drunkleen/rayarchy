#!/usr/bin/env bash
set -euo pipefail
systemctl --user disable --now rayarchy.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/rayarchy.service" "$HOME/.local/bin/rayarchy" "$HOME/.local/bin/rayarchy-daemon" "$HOME/.local/bin/rayarchy-helper"
systemctl --user daemon-reload
echo "Rayarchy backend removed; profile data was preserved."
