# Rayarchy 100% ship checklist

## Foundation
- [x] Backend-only Omarchy manifest with no shell entry points
- [x] Rust workspace, JSON-RPC Unix socket, user systemd service
- [x] User service and source-checkout setup installer
- [x] Reproducible release archive and checksum artifact workflow

## v2rayN Linux parity
- [x] Profile list: search, sort, favorites, groups, reorder, enable/disable
- [x] Add/import: URI, clipboard, JSON/YAML, WireGuard, QR payload
- [x] Profile editor with protocol-specific fields and raw config fallback
- [x] Duplicate, export, share URI, QR, delete confirmation
- [x] Subscription add/edit/delete/update, auto-refresh scheduler, basic enable controls
- [x] TCP/proxy/real latency, speed, and bounded history
- [x] Xray and sing-box generation and basic lifecycle with health-gated activation
- [x] Core validation, crash recovery, reconnect backoff, and protocol-specific settings
- [ ] Local, System Proxy, TUN, transparent, DNS, LAN bypass, kill switch
- [ ] Routing rules, GeoIP/GeoSite downloads with hash verification
- [x] Logs, diagnostics, backup/restore, migration and security hardening

## Release gates
- [x] Full workspace tests and strict Clippy
- [x] Backend manifest and repository validation
- [ ] Live daemon/CLI connect/disconnect verification
- [ ] Commit every completed vertical slice
