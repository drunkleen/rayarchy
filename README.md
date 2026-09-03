# Rayarchy

Current release channel: **0.1.0-beta.4**. See [docs/beta.md](docs/beta.md)
for the install flow and known beta limits.

Rust v2rayN-inspired proxy management for Omarchy. It provides a systemd user
daemon, JSON-RPC Unix socket, a command-line client, and a **v2rayN-style
graphical UI** rendered inside the Omarchy shell: a panel window (server list,
status bar, message console, subscription/routing/DNS/settings dialogs) plus a
bar status widget and a launcher/menu entry. Every dialog is an inline sheet
in the same window — no external popups.

## Install (one command)

```sh
curl -fsSL https://github.com/drunkleen/rayarchy/raw/master/install.sh | bash
```

That clones the plugin through `omarchy`, installs the backend
(daemon/CLI/helper under `~/.local/bin`, a systemd user service), enables the
shell panel + bar widget, and adds a launcher/menu entry. No Rust toolchain is
needed when a release archive exists for the current version.

**Update an existing install:**

```sh
~/.config/omarchy/plugins/com.drunkleen.rayarchy/install.sh
# or, manually:
omarchy plugin update com.drunkleen.rayarchy
~/.config/omarchy/plugins/com.drunkleen.rayarchy/setup.sh
```

**Open the window** with the ⛨ bar widget, Super+space → “Rayarchy”, or:

```sh
omarchy-shell shell toggle com.drunkleen.rayarchy '{}'
```

The backend is unprivileged; TUN/transparent/kill-switch go through a
polkit-authorized helper (`rayarchy-helper`) installed by `setup.sh`.

## Maintainers: release (one command)

```sh
./scripts/release.sh                  # release the version in manifest.json
./scripts/release.sh --bump 0.1.0-beta.5   # bump + commit + release
./scripts/release.sh --local          # build locally + publish with gh
./scripts/release.sh --dry-run        # preview
```

It pushes `master`, tags `v<version>`, and pushes the tag; CI builds and
attaches the release archive (or `--local` publishes immediately with `gh`).
End-user `install.sh` then auto-downloads that exact archive.

## CLI usage

Use the explicitly installed client if an old `/usr/local/bin` copy exists:

```sh
~/.local/bin/rayarchy status
~/.local/bin/rayarchy profiles
~/.local/bin/rayarchy import 'vless://...'
~/.local/bin/rayarchy validate PROFILE_ID
~/.local/bin/rayarchy connect PROFILE_ID
~/.local/bin/rayarchy set-default PROFILE_ID
~/.local/bin/rayarchy default
~/.local/bin/rayarchy reload
~/.local/bin/rayarchy speed-profile PROFILE_ID
~/.local/bin/rayarchy ip
~/.local/bin/rayarchy disconnect
```

The CLI prints JSON. Imported profiles and backups may contain credentials;
keep command output and state files private.

For a repeatable live parser check, build the CLI and run:

```sh
RAYARCHY_SUBSCRIPTION_URL='https://example.invalid/subscription' \
  tests/live-subscription.sh
```

The script keeps the downloaded payload temporary and reports only counts.

Batch testing and fastest-profile selection are also available:

```sh
~/.local/bin/rayarchy bulk-proxy PROFILE_ID...
~/.local/bin/rayarchy best
~/.local/bin/rayarchy best --connect
```

After upgrading from an older Rayarchy build, rerun `install.sh` (or
`setup.sh`) from the checkout. It rebuilds/redownloads and installs the daemon
and CLI under `~/.local/bin`, then reloads the user service; this avoids
accidentally testing a stale `/usr/local/bin` binary.
