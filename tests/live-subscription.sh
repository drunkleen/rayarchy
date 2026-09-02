#!/usr/bin/env bash
set -euo pipefail

: "${RAYARCHY_SUBSCRIPTION_URL:?Set RAYARCHY_SUBSCRIPTION_URL to run this smoke test}"

payload=$(mktemp)
decoded=$(mktemp)
result=$(mktemp)
trap 'rm -f "$payload" "$decoded" "$result"' EXIT

curl --fail --silent --show-error --location --max-time 30 \
  --output "$payload" "$RAYARCHY_SUBSCRIPTION_URL"

if base64 --decode --ignore-garbage "$payload" >"$decoded" 2>/dev/null; then
  input="$decoded"
else
  input="$payload"
fi

total=0
parsed=0
while IFS= read -r uri; do
  [[ -z "$uri" ]] && continue
  total=$((total + 1))
  if rayarchy import "$uri" >"$result" 2>/dev/null; then
    parsed=$((parsed + 1))
  fi
done < <(grep -E '^(vless|vmess|trojan|ss|socks|http|hysteria2|tuic|wireguard)://' "$input" || true)

if (( total == 0 )); then
  echo "No supported profiles found in subscription payload" >&2
  exit 1
fi
if (( parsed != total )); then
  echo "Parsed $parsed of $total profiles" >&2
  exit 1
fi
printf 'Subscription smoke test passed: %d/%d profiles parsed\n' "$parsed" "$total"
