# Rayarchy beta

Rayarchy beta is installable as a backend-only Omarchy package:

```sh
omarchy plugin add https://github.com/drunkleen/rayarchy --enable
cd ~/.config/omarchy/plugins/com.drunkleen.rayarchy
RAYARCHY_BUILD_FROM_SOURCE=1 ./setup.sh
```

The package has no QML, bar widget, panel, or graphical interface. `setup.sh`
builds the Rust backend, installs
the user systemd service, and restarts it. It does not install Polkit rules or
change system-wide networking.

The beta includes profile import/edit/delete, subscriptions, Xray and
sing-box generation, system proxy mode, TCP/proxy/IP/speed tests, history,
routing rules, backup/restore, diagnostics, and JSON CLI workflows.

Known beta limits are TUN/transparent routing and kill switch support and
endpoint-specific compatibility differences between
proxy providers. Rayarchy refuses unsupported modes and never reports a
connection until an outbound health check succeeds.

For upgrades from an older checkout, run `./setup.sh` again. If an older
`rayarchy` binary in `/usr/local/bin` shadows the plugin CLI, invoke the
plugin-owned binary explicitly as `~/.local/bin/rayarchy`.
