use rayarchy_core::{
    model::RoutingRule,
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
            serde_json::json!({"log":{"level":"info"},"inbounds":[{"type":"mixed","tag":"rayarchy-in","listen":host,"listen_port":port}],"outbounds":[outbound,{"type":"direct","tag":"direct"},{"type":"block","tag":"block"}],"route":{"rules":[]}})
        }
        Core::Xray => {
            serde_json::json!({"log":{"loglevel":"warning"},"inbounds":[{"tag":"rayarchy-in","listen":host,"port":port,"protocol":"mixed","settings":{}}],"outbounds":[outbound,{"protocol":"freedom","tag":"direct"},{"protocol":"blackhole","tag":"block"}]})
        }
        Core::Auto => unreachable!(),
    }
}

pub fn apply_rules(config: &mut serde_json::Value, core: Core, rules: &[RoutingRule]) {
    let enabled = rules.iter().filter(|r| r.enabled);
    match core {
        Core::SingBox => {
            let route = config
                .as_object_mut()
                .and_then(|o| o.get_mut("route"))
                .and_then(|v| v.as_object_mut());
            let Some(route) = route else {
                return;
            };
            let list = route
                .entry("rules")
                .or_insert_with(|| serde_json::json!([]))
                .as_array_mut();
            let Some(list) = list else {
                return;
            };
            for rule in enabled {
                let key = match rule.match_type.as_str() {
                    "domain" => "domain",
                    "domain_suffix" => "domain_suffix",
                    "ip" | "cidr" => "ip_cidr",
                    _ => "domain_keyword",
                };
                let outbound = match rule.action.as_str() {
                    "direct" => "direct",
                    "block" => "block",
                    _ => "proxy",
                };
                list.push(serde_json::json!({key:[rule.value],"outbound":outbound}));
            }
        }
        Core::Xray => {
            let routing = config
                .as_object_mut()
                .and_then(|o| o.get_mut("routing"))
                .and_then(|v| v.as_object_mut());
            let Some(routing) = routing else {
                return;
            };
            let list = routing
                .entry("rules")
                .or_insert_with(|| serde_json::json!([]))
                .as_array_mut();
            let Some(list) = list else {
                return;
            };
            for rule in enabled {
                let outbound = match rule.action.as_str() {
                    "direct" => "direct",
                    "block" => "block",
                    _ => "proxy",
                };
                list.push(serde_json::json!({"type":"field","domain":[rule.value],"outboundTag":outbound}));
            }
        }
        Core::Auto => {}
    }
}
