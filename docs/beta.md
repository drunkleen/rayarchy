# Rayarchy beta

Rayarchy beta is installable as an Omarchy package with a shell UI:

```sh
omarchy plugin add https://github.com/drunkleen/rayarchy --enable
cd ~/.config/omarchy/plugins/com.drunkleen.rayarchy
RAYARCHY_BUILD_FROM_SOURCE=1 ./setup.sh
omarchy plugin enable com.drunkleen.rayarchy right
```

`setup.sh` builds the Rust backend, installs the user systemd service,
restarts it, discovers the plugin in the running shell, enables the panel and
bar status widget, and adds a Rayarchy launcher/menu entry. It does not install
Polkit rules or change system-wide networking.

The beta includes the v2rayN-style shell UI (server list, status bar, message
console, subscription/routing/DNS/option/backup dialogs rendered as inline
sheets in one window), profile import/edit/delete, subscriptions, Xray and
sing-box generation, system proxy mode, TCP/proxy/IP/speed tests, history,
routing rules, backup/restore, diagnostics, and JSON CLI workflows.

Known beta limits are TUN/transparent routing and kill switch support, the
Clash Proxies/Connections tabs and traffic statistics (both land with the
privileged-helper release), and endpoint-specific compatibility differences
between proxy providers. Rayarchy refuses unsupported modes and never reports a
connection until an outbound health check succeeds.

For upgrades from an older checkout, run `./setup.sh` again. If an older
`rayarchy` binary in `/usr/local/bin` shadows the plugin CLI, invoke the
plugin-owned binary explicitly as `~/.local/bin/rayarchy`.