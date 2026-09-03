use crate::protocol::{ConnectionMode, Core, Protocol};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use uuid::Uuid;

fn id() -> Uuid {
    Uuid::new_v4()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Profile {
    #[serde(default = "id")]
    pub id: Uuid,
    pub name: String,
    pub protocol: Protocol,
    #[serde(default)]
    pub core: Core,
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub favorite: bool,
    #[serde(default)]
    pub group: String,
    #[serde(default)]
    pub server: Option<String>,
    #[serde(default)]
    pub port: Option<u16>,
    #[serde(default)]
    pub source_id: Option<Uuid>,
    #[serde(default)]
    pub fields: Value,
    #[serde(default)]
    pub raw: Option<String>,
    /// Ordered member profile ids for policy groups and proxy chains.
    #[serde(default)]
    pub members: Vec<Uuid>,
    /// Policy selection strategy: manual, latency, fallback, or load_balance.
    #[serde(default)]
    pub strategy: Option<String>,
}

impl Default for Profile {
    fn default() -> Self {
        Self {
            id: id(),
            name: String::new(),
            protocol: Protocol::Vless,
            core: Core::Auto,
            enabled: true,
            favorite: false,
            group: String::new(),
            server: None,
            port: None,
            source_id: None,
            fields: Value::Object(Default::default()),
            raw: None,
            members: Vec::new(),
            strategy: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Subscription {
    #[serde(default = "id")]
    pub id: Uuid,
    pub name: String,
    pub url: String,
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default)]
    pub auto_update: AutoUpdate,
    #[serde(default)]
    pub last_error: Option<String>,
    #[serde(default)]
    pub last_refresh_at: Option<i64>,
    /// Extra comma-separated subscription URLs appended to the main one.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub more_url: Option<String>,
    /// Regex applied to imported remarks (v2rayN SubEdit Filter).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub filter: Option<String>,
    /// Optional subscription-conversion target (ACL4SSR style).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub convert_target: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub user_agent: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sort: Option<i64>,
    /// Profile used as the pre-SOCKS/prev hop when this sub feeds a chain.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub prev_profile_id: Option<Uuid>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub next_profile_id: Option<Uuid>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub custom_core: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub memo: Option<String>,
}
fn default_true() -> bool {
    true
}
impl Default for Subscription {
    fn default() -> Self {
        Self {
            id: id(),
            name: String::new(),
            url: String::new(),
            enabled: true,
            auto_update: AutoUpdate::default(),
            last_error: None,
            last_refresh_at: None,
            more_url: None,
            filter: None,
            convert_target: None,
            user_agent: None,
            sort: None,
            prev_profile_id: None,
            next_profile_id: None,
            custom_core: None,
            memo: None,
        }
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum AutoUpdate {
    Off,
    Startup,
    #[default]
    Daily,
    Every6Hours,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Settings {
    #[serde(default)]
    pub connection_mode: ConnectionMode,
    #[serde(default)]
    pub preferred_core: Core,
    #[serde(default = "default_port")]
    pub local_port: u16,
    #[serde(default)]
    pub kill_switch: bool,
    #[serde(default)]
    pub dns_leak_protection: bool,
    #[serde(default)]
    pub lan_bypass: bool,
    #[serde(default = "default_health_retention_hours")]
    pub health_retention_hours: u32,
    /// Persisted id of the server connected when the user hits "connect"
    /// without an explicit selection ("default server" in v2rayN terms).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub default_profile_id: Option<Uuid>,
    /// Free-form UI state (column widths, window size, layout, filters)
    /// persisted alongside the rest of the settings.
    #[serde(default)]
    pub ui: Value,
    /// Subscription-conversion service prefix used when a sub sets a convert
    /// target (ACL4SSR compatible: `{prefix}sub?target=..&url=..`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sub_convert_url: Option<String>,
    /// Simple DNS settings: `{direct, remote, bootstrap, fakeIp, systemHosts,
    /// hosts}`. Consumed by config generation when DNS protection is on.
    #[serde(default)]
    pub dns: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RoutingRule {
    #[serde(default = "id")]
    pub id: Uuid,
    pub name: String,
    pub match_type: String,
    pub value: String,
    pub action: String,
    #[serde(default = "default_true")]
    pub enabled: bool,
}
fn default_port() -> u16 {
    1080
}
impl Default for Settings {
    fn default() -> Self {
        Self {
            connection_mode: ConnectionMode::SystemProxy,
            preferred_core: Core::Auto,
            local_port: 1080,
            kill_switch: false,
            dns_leak_protection: true,
            lan_bypass: true,
            health_retention_hours: 24,
            default_profile_id: None,
            ui: Value::Object(Default::default()),
            sub_convert_url: None,
            dns: Value::Object(Default::default()),
        }
    }
}
fn default_health_retention_hours() -> u32 {
    24
}
