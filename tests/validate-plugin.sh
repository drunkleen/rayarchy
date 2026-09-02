#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
command -v jq >/dev/null
jq empty "$root/manifest.json"
test -x "$root/setup.sh"
test "$(jq -r '.kinds | join(",")' "$root/manifest.json")" = "backend"
test "$(jq '.entryPoints | length' "$root/manifest.json")" -eq 0
test ! -d "$root/plugin"
test -f "$root/crates/rayarchy-daemon/src/main.rs"
printf 'Rayarchy backend files are valid\n'
