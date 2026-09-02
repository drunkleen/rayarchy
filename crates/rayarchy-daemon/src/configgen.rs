use rayarchy_core::{
    protocol::{Core, Protocol},
    Profile,
};

pub fn choose_core(profile: &Profile, preferred: Core) -> Core {
    if preferred != Core::Auto {
        return preferred;
    }
    if matches!(
        profile.protocol,
        Protocol::Hysteria2 | Protocol::Tuic | Protocol::Wireguard
    ) {
        Core::SingBox
    } else {
        Core::Xray
    }
}

pub fn build(profile: &Profile, core: Core, host: &str, port: u16) -> serde_json::Value {
    let server = profile.server.clone().unwrap_or_default();
    let server_port = profile.port.unwrap_or_default();
    let user = profile
        .fields
        .get("user")
        .and_then(|v| v.as_str())
        .unwrap_or_default();
    let outbound = match core {
        Core::SingBox => {
            let typ = match profile.protocol {
                Protocol::Vless => "vless",
                Protocol::Vmess => "vmess",
                Protocol::Trojan => "trojan",
                Protocol::Shadowsocks => "shadowsocks",
                Protocol::Socks => "socks",
                Protocol::Http => "http",
                Protocol::Hysteria2 => "hysteria2",
                Protocol::Tuic => "tuic",
                Protocol::Wireguard => "wireguard",
            };
            serde_json::json!({"type":typ,"tag":"proxy","server":server,"server_port":server_port,"uuid":user,"password":user})
        }
        Core::Xray => {
            let protocol = match profile.protocol {
                Protocol::Vless => "vless",
                Protocol::Vmess => "vmess",
                Protocol::Trojan => "trojan",
                Protocol::Shadowsocks => "shadowsocks",
                Protocol::Socks => "socks",
                Protocol::Http => "http",
                _ => "freedom",
            };
            serde_json::json!({"protocol":protocol,"tag":"proxy","settings":{"vnext":[{"address":server,"port":server_port,"users":[{"id":user,"encryption":"none"}]}]}})
        }
        Core::Auto => unreachable!(),
    };
    match core {
        Core::SingBox => {
            serde_json::json!({"log":{"level":"info"},"inbounds":[{"type":"mixed","tag":"rayarchy-in","listen":host,"listen_port":port}],"outbounds":[outbound,{"type":"direct","tag":"direct"},{"type":"block","tag":"block"}]})
        }
        Core::Xray => {
            serde_json::json!({"log":{"loglevel":"warning"},"inbounds":[{"tag":"rayarchy-in","listen":host,"port":port,"protocol":"mixed","settings":{}}],"outbounds":[outbound,{"protocol":"freedom","tag":"direct"},{"protocol":"blackhole","tag":"block"}]})
        }
        Core::Auto => unreachable!(),
    }
}
