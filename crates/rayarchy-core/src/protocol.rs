use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Protocol {
    Vless,
    Vmess,
    Trojan,
    Shadowsocks,
    Socks,
    Http,
    Hysteria2,
    Tuic,
    Wireguard,
    Anytls,
    Naive,
    Custom,
    PolicyGroup,
    ProxyChain,
    /// A single sing-box outbound endpoint (v2rayN "custom outbound").
    Outbound,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "kebab-case")]
pub enum Core {
    #[default]
    Auto,
    SingBox,
    Xray,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum ConnectionMode {
    #[default]
    #[serde(alias = "systemproxy", alias = "system-proxy")]
    SystemProxy,
    Local,
    Tun,
    Transparent,
}

#[cfg(test)]
mod tests {
    use super::ConnectionMode;

    #[test]
    fn connection_mode_accepts_legacy_systemproxy_wire_value() {
        let legacy: ConnectionMode = serde_json::from_str("\"systemproxy\"").unwrap();
        let current: ConnectionMode = serde_json::from_str("\"system_proxy\"").unwrap();
        assert_eq!(legacy, ConnectionMode::SystemProxy);
        assert_eq!(current, ConnectionMode::SystemProxy);
    }
}
