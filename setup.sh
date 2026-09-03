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
if [[ "${RAYARCHY_BUILD_FROM_SOURCE:-0}" != "1" ]] && command -v curl >/dev/null && command -v tar >/dev/null && command -v sha256sum >/dev/null && command -v jq >/dev/null; then
  version=$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' "$root/manifest.json" | head -1)
  release_tmp=$(mktemp -d)
  archive="$release_tmp/rayarchy.tar.gz"
  checksum="$release_tmp/rayarchy.tar.gz.sha256"
  release_tag=$(curl -fsSL --connect-timeout 5 --max-time 15 https://api.github.com/repos/drunkleen/rayarchy/releases/latest | jq -r '.tag_name // empty' || true)
  [[ -n "$release_tag" ]] || release_tag="v${version}"
  archive_url="https://github.com/drunkleen/rayarchy/releases/download/${release_tag}/rayarchy-${release_tag}-x86_64.tar.gz"
  checksum_url="${archive_url}.sha256"
  if [[ "$release_tag" == "v${version}" ]] && curl -fsSL --connect-timeout 5 --max-time 30 "$archive_url" -o "$archive" \
    && curl -fsSL --connect-timeout 5 --max-time 30 "$checksum_url" -o "$checksum" \
    && (cd "$release_tmp" && sha256sum -c "$(basename "$checksum")" >/dev/null); then
    tar -xzf "$archive" -C "$release_tmp"
    daemon_bin="$release_tmp/rayarchy/rayarchy-daemon"
    cli_bin="$release_tmp/rayarchy/rayarchy"
    helper_bin="$release_tmp/rayarchy/rayarchy-helper"
    echo "Using Rayarchy ${release_tag} release binaries"
  else
    echo "Release ${release_tag} unavailable or checksum failed; building from source"
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

# --- Omarchy shell integration -------------------------------------------------
# The UI ships as a shell plugin (panel window + bar status widget) that lives
# in this repository. Discover it in the running shell, then enable the panel
# and place the status widget in the right bar section.
if command -v omarchy-shell >/dev/null 2>&1 && command -v omarchy >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  omarchy plugin enable com.drunkleen.rayarchy right >/dev/null 2>&1 || true
  # Launcher/menu entry: merge a Rayarchy row into the user's omarchy-menu
  # extensions file so Super+space -> "rayarchy" opens the panel.
  menu_file="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
  if [[ ! -f "$menu_file" ]]; then
    cat > "$menu_file" <<'MENU'
{"rayarchy":{"icon":"⛨","label":"Rayarchy","action":"omarchy-shell shell toggle com.drunkleen.rayarchy '{}'"}}
MENU
  elif ! grep -q '"rayarchy"' "$menu_file" 2>/dev/null; then
    if command -v python3 >/dev/null 2>&1; then
      python3 - "$menu_file" <<'PY' || true
import json, re, sys, pathlib
path = pathlib.Path(sys.argv[1])
raw = path.read_text()
# Strip JSONC comments (best-effort; single URLs with // are rare in menus).
text = re.sub(r'//[^\n]*', '', raw)
text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
data = json.loads(text) if text.strip() else {}
entry = {"rayarchy": {"icon": "⛨", "label": "Rayarchy",
                      "action": "omarchy-shell shell toggle com.drunkleen.rayarchy '{}'"}}
data.setdefault("rayarchy", entry["rayarchy"])
path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
PY
    fi
  fi
fi

[[ -n "$release_tmp" ]] && rm -rf "$release_tmp"
echo "Rayarchy backend installed. Run ~/.local/bin/rayarchy --help."
