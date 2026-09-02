# v2rayN parity baseline

Rayarchy targets the Linux-visible behavior of v2rayN commit
`f62eaab8c54c83529712b97b1bde6899f8da7c03` (2026-09-02). The reference is
used to reproduce workflows and outcomes; its .NET/Avalonia code is not copied.

## Product decisions

- Rayarchy is backend-only. Its public user interface is the JSON CLI and its
  automation interface is JSON-RPC over a private Unix socket.
- Windows-only registry, WFP, UWP, and service behavior is replaced with Linux
  system proxy, systemd user services, and an explicitly installed Polkit
  helper for privileged networking.
- Core installation is an explicit, checksum-verified setup action. Installing
  the shell plugin never runs privileged hooks or downloads executables.

## Linux workflow inventory

| Area | Reference behavior | Rayarchy target |
|---|---|---|
| Profiles | ProfilesView, AddServer, AddServer2 | CLI/RPC list, groups, all supported protocols, custom configs, policy groups, proxy chains |
| Subscriptions | SubSetting, SubEdit | CRUD, proxy refresh, scheduled refresh, history, conversion options |
| Connectivity | MainWindow, StatusBar | Local, system proxy, TUN, transparent routing, verified activation, traffic status |
| Tests | ProfilesView actions | TCP, real/proxy delay, speed, UDP, batch cancellation, history |
| Routing and DNS | RoutingSetting, RoutingRuleSetting, DNSSetting | Presets, ordered rules, custom DNS, PAC, GeoIP/GeoSite assets |
| Cores | CoreManager, FullConfigTemplate | Detect, install, update, verify, validate, select, template editing |
| Clash API | ClashProxies, ClashConnections | Providers, proxy selection, live connections, close connection |
| Utilities | QRCode, BackupAndRestore, MsgView | QR import/export, secure backup/restore, bounded redacted logs and diagnostics |

Connection state is committed only after the selected networking mode and an
outbound health check both succeed.
