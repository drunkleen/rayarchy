# Rayarchy

Current release channel: **0.1.0-beta.1**. See [docs/beta.md](docs/beta.md)
for the install flow and known beta limits.

Rust v2rayN-inspired proxy management for Omarchy. It provides a systemd user
daemon, JSON-RPC Unix socket, and command-line client. There is no graphical UI.

Clone through Omarchy, then install the backend:

```sh
omarchy plugin add https://github.com/drunkleen/rayarchy --enable
RAYARCHY_BUILD_FROM_SOURCE=1 ~/.config/omarchy/plugins/com.drunkleen.rayarchy/setup.sh
```

The backend is unprivileged. TUN/transparent routing and kill-switch
support are intentionally refused until their narrowly-scoped helper is
installed and enabled by a future release.

Development status and the parity checklist are in `TODO.md` and
`instructions.md`.

## CLI usage

Use the explicitly installed client if an old `/usr/local/bin` copy exists:

```sh
~/.local/bin/rayarchy status
~/.local/bin/rayarchy profiles
~/.local/bin/rayarchy import 'vless://...'
~/.local/bin/rayarchy validate PROFILE_ID
~/.local/bin/rayarchy connect PROFILE_ID
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

After upgrading from an older Rayarchy build, rerun `setup.sh` from the cloned
checkout. It rebuilds and installs both the daemon and CLI under
`~/.local/bin`, then reloads the user service; this avoids accidentally
testing a stale `/usr/local/bin` binary.
