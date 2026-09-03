#!/usr/bin/env bash
# Publish a Rayarchy release with plain git (gh optional for local publish).
#
#   ./scripts/release.sh                 # release the version in manifest.json
#   ./scripts/release.sh 0.1.0-beta.5    # release a specific version
#   ./scripts/release.sh --bump 0.1.0-beta.5   # bump version files, commit, then release
#   ./scripts/release.sh --dry-run       # preview without touching git
#   ./scripts/release.sh --local         # build archive locally + gh release create
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
cd "$root"

mode="ci"
bump=0
version=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bump) bump=1; shift; [[ $# -gt 0 ]] && version="$1"; shift ;;
    --dry-run) mode="dry-run"; shift ;;
    --local) mode="local"; shift ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) version="$1"; shift ;;
  esac
done

manifest_version=$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' manifest.json | head -1)
if [[ -z "$version" ]]; then
  version="$manifest_version"
fi
tag="v${version}"

if [[ "$mode" == "dry-run" ]]; then
  echo "Rayarchy release dry run (version=$version, tag=$tag):"
  echo "  git push origin HEAD"
  [[ "$bump" == "1" ]] && echo "  (bump manifest/README/beta.md)"
  echo "  git tag $tag"
  echo "  git push origin $tag"
  echo "  # CI builds + attaches the archive; verify: gh release view $tag"
  exit 0
fi

# Optional version bump: edit manifest + README + docs/beta.md and commit.
if [[ "$bump" == "1" ]]; then
  [[ "$version" == "$manifest_version" ]] || {
    command -v python3 >/dev/null || { echo "--bump needs python3" >&2; exit 1; }
    python3 - "$version" <<'PY'
import json, pathlib, sys
version = sys.argv[1]
path = pathlib.Path("manifest.json")
data = json.loads(path.read_text())
data["version"] = version
path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
for f in ["README.md", "docs/beta.md"]:
    p = pathlib.Path(f)
    s = p.read_text()
    import re
    s = re.sub(r"0\.1\.0-beta\.\d+", version, s)
    p.write_text(s)
print(f"bumped manifest + docs to {version}")
PY
    git add manifest.json README.md docs/beta.md
    git commit -q -m "release: v${version}"
  }
fi

# Safety checks.
if [[ -n "$(git status --porcelain)" ]]; then
  echo "working tree is not clean; commit or stash first" >&2
  exit 1
fi
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  echo "tag $tag already exists" >&2
  exit 1
fi

echo "Publishing Rayarchy v${version} (mode: $mode)"
git push origin HEAD
git tag "$tag"
git push origin "$tag"

if [[ "$mode" == "local" ]]; then
  command -v gh >/dev/null || { echo "--local needs gh" >&2; exit 1; }
  echo "Building release archive locally…"
  cargo build --release --workspace
  dist_dir=$(mktemp -d)
  mkdir -p "$dist_dir/rayarchy"
  install -Dm755 target/release/rayarchy "$dist_dir/rayarchy/rayarchy"
  install -Dm755 target/release/rayarchy-daemon "$dist_dir/rayarchy/rayarchy-daemon"
  install -Dm755 target/release/rayarchy-helper "$dist_dir/rayarchy/rayarchy-helper"
  install -Dm755 setup.sh "$dist_dir/rayarchy/setup.sh"
  install -Dm755 packaging/uninstall.sh "$dist_dir/rayarchy/uninstall.sh"
  install -Dm755 install.sh "$dist_dir/rayarchy/install.sh"
  cp -r scripts "$dist_dir/rayarchy/scripts"
  cp manifest.json "$dist_dir/rayarchy/"
  cp -r ui "$dist_dir/rayarchy/ui"
  (cd "$dist_dir" \
    && tar -czf "rayarchy-${tag}-x86_64.tar.gz" rayarchy \
    && sha256sum "rayarchy-${tag}-x86_64.tar.gz" > "rayarchy-${tag}-x86_64.tar.gz.sha256")
  gh release create "$tag" "$dist_dir/rayarchy-${tag}-x86_64.tar.gz" "$dist_dir/rayarchy-${tag}-x86_64.tar.gz.sha256" \
    --repo drunkleen/rayarchy --title "$tag"
  rm -rf "$dist_dir"
  echo "Published locally: https://github.com/drunkleen/rayarchy/releases/tag/$tag"
else
  echo "Tag pushed. CI is building the archive now."
  echo "  watch:  gh run watch"
  echo "  verify: gh release view $tag"
fi