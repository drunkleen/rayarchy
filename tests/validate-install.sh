#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
bash -n "$root/setup.sh"
"$root/setup.sh" --check
printf 'Rayarchy installer check passed\n'
