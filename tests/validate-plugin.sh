#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
command -v jq >/dev/null
jq empty "$root/manifest.json"
test -x "$root/setup.sh"
test -f "$root/plugin/src/RayarchyPanel.qml"
test -f "$root/plugin/src/RayarchyBar.qml"
test -f "$root/crates/rayarchy-daemon/src/main.rs"
printf 'Rayarchy plugin files are valid\n'
