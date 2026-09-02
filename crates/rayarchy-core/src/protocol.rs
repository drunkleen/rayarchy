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
    SystemProxy,
    Local,
    Tun,
    Transparent,
}
