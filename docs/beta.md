# Rayarchy beta

Rayarchy beta installs as an Omarchy package with a shell UI in one command:

```sh
curl -fsSL https://github.com/drunkleen/rayarchy/raw/master/install.sh | bash
```

`install.sh` clones the plugin through `omarchy`, then runs `setup.sh`, which
installs the user systemd service (restarting it), enables the panel and bar
status widget, and adds a Rayarchy launcher/menu entry. It does not install
Polkit rules or change system-wide networking. Updates are the same command
again (or `omarchy plugin update com.drunkleen.rayarchy` + `setup.sh`).

The beta includes the v2rayN-style shell UI (server list, status bar, message
console, Clash Proxies/Connections tabs while sing-box runs, subscription/
routing/DNS/option/backup/check-update dialogs rendered as inline sheets in one
window), profile import/edit/delete, inner-URI round trips, subscriptions with
conversion + filtering, Xray and sing-box generation, system proxy mode,
TCP/proxy/IP/UDP/speed tests, live traffic statistics and realtime speeds,
routing presets, DNS settings, backup/restore, diagnostics, JSON CLI workflows,
and a Check Update dialog that downloads and SHA-256-verifies cores and geo
data into `~/.local/share/rayarchy/bin`.

Known beta limits are advanced core-config tuning (mux, reality fingerprint
presets, transport fragments, LAN inbound auth), per-node Clash delay-testing,
and endpoint-specific compatibility differences between proxy providers.
TUN/transparent routing and the kill switch are available when the
`rayarchy-helper` binary is installed by `setup.sh`; enabling TUN prompts once
through the Polkit agent (session authorization is remembered). Rayarchy
refuses unsupported modes and never reports a connection until an outbound
health check succeeds.

For upgrades from an older checkout, run `./setup.sh` again. If an older
`rayarchy` binary in `/usr/local/bin` shadows the plugin CLI, invoke the
plugin-owned binary explicitly as `~/.local/bin/rayarchy`.