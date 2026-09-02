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
    let field = |name: &str| {
        profile
            .fields
            .get(name)
            .and_then(|v| v.as_str())
            .unwrap_or_default()
    };
    let user = field("user");
    let password = field("password");
    let method = field("method");
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
            if profile.protocol == Protocol::Wireguard {
                return serde_json::json!({"log":{"level":"info"},"inbounds":[{"type":"mixed","tag":"rayarchy-in","listen":host,"listen_port":port}],"outbounds":[{"type":"wireguard","tag":"proxy","server":server,"server_port":server_port,"local_address":[field("local_address")],"private_key":field("private_key"),"peers":[{"public_key":field("public_key"),"allowed_ips":["0.0.0.0/0","::/0"]}]},{"type":"direct","tag":"direct"},{"type":"block","tag":"block"}],"route":{"rules":[]}});
            }
            let mut value = serde_json::json!({"type":typ,"tag":"proxy","server":server,"server_port":server_port});
            if matches!(
                profile.protocol,
                Protocol::Vless | Protocol::Vmess | Protocol::Tuic
            ) {
                value["uuid"] = serde_json::Value::String(user.to_string());
            }
            if matches!(
                profile.protocol,
                Protocol::Trojan | Protocol::Shadowsocks | Protocol::Hysteria2 | Protocol::Tuic
            ) {
                value["password"] = serde_json::Value::String(if password.is_empty() {
                    user.to_string()
                } else {
                    password.to_string()
                });
            }
            if profile.protocol == Protocol::Shadowsocks && !method.is_empty() {
                value["method"] = serde_json::Value::String(method.to_string());
            }
            if matches!(profile.protocol, Protocol::Hysteria2 | Protocol::Tuic) {
                if !field("congestion_control").is_empty() {
                    value["congestion_control"] =
                        serde_json::Value::String(field("congestion_control").to_string());
                }
                if !field("obfs").is_empty() {
                    value["obfs"] =
                        serde_json::json!({"type":field("obfs"),"password":field("obfs-password")});
                }
            }
            if field("security") == "tls" || field("tls") == "tls" {
                value["tls"] = serde_json::json!({"enabled":true,"server_name":if field("sni").is_empty() { server.clone() } else { field("sni").to_string() }});
            }
            if field("type") == "ws" || field("network") == "ws" {
                value["transport"] = serde_json::json!({"type":"ws","path":field("path"),"headers":{"Host":field("host")} });
            }
            value
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
            let settings = if matches!(profile.protocol, Protocol::Vless | Protocol::Vmess) {
                serde_json::json!({"vnext":[{"address":server,"port":server_port,"users":[{"id":user,"alterId":profile.fields.get("aid").and_then(|v| v.as_u64()).unwrap_or(0),"encryption":if field("encryption").is_empty() { "none" } else { field("encryption") },"flow":field("flow")}]}]})
            } else if profile.protocol == Protocol::Trojan {
                serde_json::json!({"servers":[{"address":server,"port":server_port,"password":if password.is_empty() { user } else { password }}]})
            } else {
                serde_json::json!({"servers":[{"address":server,"port":server_port,"method":method,"password":password}]})
            };
            let mut value =
                serde_json::json!({"protocol":protocol,"tag":"proxy","settings":settings});
            if field("security") == "tls" || field("tls") == "tls" {
                let network = if field("type").is_empty() {
                    "tcp"
                } else {
                    field("type")
                };
                let mut stream = serde_json::json!({"network":network,"security":"tls","tlsSettings":{"serverName":if field("sni").is_empty() { server.clone() } else { field("sni").to_string() }}});
                if network == "ws" {
                    stream["wsSettings"] =
                        serde_json::json!({"path":field("path"),"headers":{"Host":field("host")}});
                }
                value["streamSettings"] = stream;
            }
            if field("security") != "tls" && field("tls") != "tls" {
                let network = field("type");
                if network == "ws" {
                    value["streamSettings"] = serde_json::json!({"network":"ws","wsSettings":{"path":field("path"),"headers":{"Host":field("host")}}});
                }
                if network == "grpc" {
                    value["streamSettings"] = serde_json::json!({"network":"grpc","grpcSettings":{"serviceName":field("serviceName")}});
                }
            }
            value
        }
        Core::Auto => unreachable!(),
    };
    match core {
        Core::SingBox => {
            serde_json::json!({"log":{"level":"info"},"inbounds":[{"type":"mixed","tag":"rayarchy-in","listen":host,"listen_port":port}],"outbounds":[outbound,{"type":"direct","tag":"direct"},{"type":"block","tag":"block"}],"route":{"rules":[]}})
        }
        Core::Xray => {
            serde_json::json!({"log":{"loglevel":"warning"},"inbounds":[{"tag":"rayarchy-in","listen":host,"port":port,"protocol":"http","settings":{}}],"outbounds":[outbound,{"protocol":"freedom","tag":"direct"},{"protocol":"blackhole","tag":"block"}],"routing":{"domainStrategy":"AsIs","rules":[]}})
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

#[cfg(test)]
mod tests {
    use super::*;
    use rayarchy_core::protocol::Protocol;

    #[test]
    fn vless_tls_websocket_transport_is_preserved() {
        let mut profile = Profile {
            protocol: Protocol::Vless,
            server: Some("edge.example".into()),
            port: Some(443),
            ..Default::default()
        };
        profile.fields = serde_json::json!({"user":"00000000-0000-0000-0000-000000000001","security":"tls","type":"ws","path":"/ray","host":"edge.example"});
        let config = build(&profile, Core::SingBox, "127.0.0.1", 1080);
        let outbound = &config["outbounds"][0];
        assert_eq!(outbound["tls"]["enabled"], true);
        assert_eq!(outbound["transport"]["type"], "ws");
    }

    #[test]
    fn wireguard_uses_peer_based_sing_box_outbound() {
        let mut profile = Profile {
            protocol: Protocol::Wireguard,
            server: Some("wg.example".into()),
            port: Some(51820),
            ..Default::default()
        };
        profile.fields = serde_json::json!({"private_key":"private","public_key":"public","local_address":"10.0.0.2/32"});
        let config = build(&profile, Core::SingBox, "127.0.0.1", 1080);
        assert_eq!(config["outbounds"][0]["type"], "wireguard");
        assert_eq!(config["outbounds"][0]["peers"][0]["public_key"], "public");
    }

    #[test]
    fn hysteria2_preserves_obfuscation_and_tls() {
        let mut profile = Profile {
            protocol: Protocol::Hysteria2,
            server: Some("hy.example".into()),
            port: Some(443),
            ..Default::default()
        };
        profile.fields = serde_json::json!({"password":"secret","security":"tls","sni":"hy.example","obfs":"salamander","obfs-password":"obfs"});
        let config = build(&profile, Core::SingBox, "127.0.0.1", 1080);
        let outbound = &config["outbounds"][0];
        assert_eq!(outbound["type"], "hysteria2");
        assert_eq!(outbound["obfs"]["type"], "salamander");
        assert_eq!(outbound["tls"]["enabled"], true);
    }

    #[test]
    fn xray_vless_includes_user_flow_and_websocket_settings() {
        let mut profile = Profile {
            protocol: Protocol::Vless,
            server: Some("x.example".into()),
            port: Some(443),
            ..Default::default()
        };
        profile.fields = serde_json::json!({"user":"00000000-0000-0000-0000-000000000001","security":"tls","type":"ws","path":"/x","host":"x.example","flow":"xtls-rprx-vision"});
        let config = build(&profile, Core::Xray, "127.0.0.1", 1080);
        assert_eq!(
            config["outbounds"][0]["settings"]["vnext"][0]["users"][0]["flow"],
            "xtls-rprx-vision"
        );
        assert_eq!(
            config["outbounds"][0]["streamSettings"]["wsSettings"]["path"],
            "/x"
        );
    }

    #[test]
    fn xray_trojan_and_shadowsocks_use_server_credentials() {
        let mut trojan = Profile {
            protocol: Protocol::Trojan,
            server: Some("t.example".into()),
            port: Some(443),
            ..Default::default()
        };
        trojan.fields = serde_json::json!({"password":"secret"});
        let config = build(&trojan, Core::Xray, "127.0.0.1", 1080);
        assert_eq!(
            config["outbounds"][0]["settings"]["servers"][0]["password"],
            "secret"
        );
        let mut shadowsocks = Profile {
            protocol: Protocol::Shadowsocks,
            server: Some("s.example".into()),
            port: Some(8388),
            ..Default::default()
        };
        shadowsocks.fields =
            serde_json::json!({"method":"2022-blake3-aes-128-gcm","password":"secret"});
        let ss = build(&shadowsocks, Core::Xray, "127.0.0.1", 1080);
        assert_eq!(
            ss["outbounds"][0]["settings"]["servers"][0]["method"],
            "2022-blake3-aes-128-gcm"
        );
    }
}
