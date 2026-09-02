# v2rayN parity map

| v2rayN workflow | Rayarchy surface |
|---|---|
| ProfilesView | Main panel profile list, groups, search, sort, actions |
| AddServer / AddServer2 | Add profile import dialog and Rust parsers |
| SubSetting / SubEdit | Subscription list/editor and refresh RPCs |
| OptionSetting | Settings page, core/mode/DNS/routing controls |
| RoutingRuleSetting | Routing RPC and generated core route rules |
| QrcodeView | QR payload RPC and shell-native display |
| MsgView | Bounded daemon log ring and Logs view |
| BackupAndRestore | Encrypted/permission-safe archive import/export |
| CoreManager | Rust process manager for xray and sing-box |

The fixed reference revision and full Linux workflow inventory are documented
in [parity-baseline.md](parity-baseline.md).

## Advanced profile behavior

AnyTLS and Naive profiles are generated for sing-box. Full custom JSON configs
are validated and handed to the selected core unchanged. Policy groups persist
an ordered member list and support manual, latency, fallback, and load-balance
selection. Proxy chains preserve hop order and compile to sing-box detours.
Groups and chains reject missing, disabled, duplicate, self-referential, or
nested members through the same RPC validation used by the QML editor.

## Profile list behavior

`profile.list` accepts `query`, `group`, `sort`, `favoritesOnly`, and
`enabledOnly`. Sorting supports the persisted manual order, name, server, and
favorites-first views. The panel only enables reorder controls in the
unfiltered manual view so moving a row cannot accidentally hide or discard
other profiles. Favorites, enabled state, groups, and manual order are stored
by the backend. RPC failures remain visible in the panel and do not apply an
optimistic state change.

Windows-only tray, registry, service, and WFP behavior is replaced by
Omarchy bar integration, systemd user services, gsettings proxy management,
and the narrow Polkit helper where Linux requires privilege.
