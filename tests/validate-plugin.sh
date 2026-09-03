#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
command -v jq >/dev/null
jq empty "$root/manifest.json"
test -x "$root/setup.sh"
kinds=$(jq -r '.kinds | join(",")' "$root/manifest.json")
case ",$kinds," in
  *",backend,"*) ;;
  *) echo "Rayarchy manifest must declare the backend kind" >&2; exit 1 ;;
esac
# Every declared shell entry point must reference an existing file.
for kind in panel barWidget; do
  entry=$(jq -r ".entryPoints.$kind // empty" "$root/manifest.json")
  if [[ -n "$entry" ]]; then
    test -f "$root/$entry" || { echo "entryPoint $kind -> $entry missing" >&2; exit 1; }
  fi
done
test -f "$root/crates/rayarchy-daemon/src/main.rs"
printf 'Rayarchy backend files and UI entry points are valid\n'