# Rayarchy 100% ship checklist

## Foundation
- [ ] Omarchy manifest, bar widget, panel, and theme tokens
- [ ] Rust workspace, JSON-RPC Unix socket, user systemd service
- [x] User service and source-checkout setup installer
- [ ] Reproducible release archive and checksum installer

## v2rayN Linux parity
- [ ] Profile list: search, sort, favorites, groups, reorder, enable/disable
- [ ] Add/import: URI, clipboard, JSON/YAML, WireGuard, QR payload
- [ ] Profile editor with protocol-specific fields and raw config fallback
- [ ] Duplicate, export, share URI, QR, delete confirmation
- [ ] Subscription add/edit/delete/update, filters, auto-update, overrides
- [ ] TCP/proxy/real latency, speed, bulk tests, cancellation, history
- [ ] Xray and sing-box generation, validation, lifecycle, crash recovery
- [ ] Local, System Proxy, TUN, transparent, DNS, LAN bypass, kill switch
- [ ] Routing rules, GeoIP/GeoSite downloads with hash verification
- [ ] Logs, diagnostics, backup/restore, migration and security hardening

## Release gates
- [ ] Full workspace tests and strict Clippy
- [ ] QML formatting and plugin validation
- [ ] Live Omarchy shell visual and connect/disconnect verification
- [ ] Commit every completed vertical slice
