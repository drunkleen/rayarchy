# Rayarchy

v2rayN-inspired proxy management for the Omarchy shell. It uses the local
`/mnt/storage/projects/v2rayN` source tree as its behavior reference while
providing an Omarchy-native QML interface and Rust backend.

Install the shell plugin:

```sh
omarchy plugin add https://github.com/drunkleen/rayarchy --enable
```

Install and start the unprivileged backend from the cloned plugin checkout
(this compiles the Rust backend locally; no sudo is required):

```sh
~/.config/omarchy/plugins/com.drunkleen.rayarchy/setup.sh
```

The plugin itself is unprivileged. TUN/transparent routing and kill-switch
support are intentionally refused until their narrowly-scoped helper is
installed and enabled by a future release.

Then run the backend setup from the installed checkout. Development status and
the complete parity checklist are in `TODO.md` and `instructions.md`.

## Import and backup workflows

Open **Add profile**, paste a v2rayN URI, JSON, YAML, WireGuard configuration,
or subscription payload, then choose **Preview parsed profiles**. Rayarchy
shows the parsed records and parser errors before **OK** commits anything.

Use **Backup** to export the complete local state as JSON. Restore accepts only
valid Rayarchy state and refuses while a profile is connected; malformed input
is rejected without changing the existing database. Keep exported backups
private because they may contain credentials.

For a repeatable live parser check, build the CLI and run:

```sh
RAYARCHY_SUBSCRIPTION_URL='https://example.invalid/subscription' \
  tests/live-subscription.sh
```

The script keeps the downloaded payload temporary and reports only counts.

Keyboard shortcuts in the panel include Ctrl/Cmd+F to focus profile search,
Enter to connect the selected profile, and Escape to clear active filters.
Profile rows expose descriptive accessibility labels and health status.

After upgrading from an older Rayarchy build, rerun `setup.sh` from the cloned
checkout. It rebuilds and installs both the daemon and CLI under
`~/.local/bin`, then reloads the user service; this avoids accidentally
testing a stale `/usr/local/bin` binary.
