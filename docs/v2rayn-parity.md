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

Windows-only tray, registry, service, and WFP behavior is replaced by
Omarchy bar integration, systemd user services, gsettings proxy management,
and the narrow Polkit helper where Linux requires privilege.
