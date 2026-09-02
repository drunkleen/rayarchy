use crate::model::Profile;
use crate::protocol::Protocol;

fn decode_base64(input: &str) -> Option<Vec<u8>> {
    let alphabet = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = Vec::new();
    let mut buffer = 0u32;
    let mut bits = 0u8;
    for byte in input.bytes().filter(|b| !b" \r\n\t".contains(b)) {
        if byte == b'=' {
            break;
        }
        let value = alphabet.iter().position(|candidate| *candidate == byte)? as u32;
        buffer = (buffer << 6) | value;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((buffer >> bits) as u8);
            buffer &= (1 << bits) - 1;
        }
    }
    (!out.is_empty()).then_some(out)
}

/// Parse the URI forms most commonly emitted by v2rayN. Additional fields are
/// retained in `fields` so editing/export remains lossless as support grows.
pub fn parse_uri(input: &str) -> Result<Profile, String> {
    let input = input.trim();
    let (scheme, rest) = input.split_once("://").ok_or("not a proxy URI")?;
    let protocol = match scheme.to_ascii_lowercase().as_str() {
        "vless" => Protocol::Vless,
        "vmess" => Protocol::Vmess,
        "trojan" => Protocol::Trojan,
        "ss" | "shadowsocks" => Protocol::Shadowsocks,
        "socks" | "socks5" => Protocol::Socks,
        "http" => Protocol::Http,
        "hy2" | "hysteria2" => Protocol::Hysteria2,
        "tuic" => Protocol::Tuic,
        "wireguard" => Protocol::Wireguard,
        _ => return Err(format!("unsupported URI scheme: {scheme}")),
    };
    if protocol == Protocol::Vmess {
        if let Some(bytes) = decode_base64(rest) {
            if let Ok(value) = serde_json::from_slice::<serde_json::Value>(&bytes) {
                let server = value
                    .get("add")
                    .and_then(|v| v.as_str())
                    .ok_or("vmess profile has no server")?;
                let port = value
                    .get("port")
                    .and_then(|v| v.as_u64().or_else(|| v.as_str()?.parse().ok()))
                    .ok_or("vmess profile has no port")?;
                let mut fields = serde_json::Map::new();
                for key in ["id", "aid", "net", "type", "host", "path", "tls", "scy"] {
                    if let Some(value) = value.get(key) {
                        fields.insert(key.into(), value.clone());
                    }
                }
                fields.insert(
                    "user".into(),
                    serde_json::Value::String(
                        value
                            .get("id")
                            .and_then(|v| v.as_str())
                            .unwrap_or_default()
                            .into(),
                    ),
                );
                return Ok(Profile {
                    protocol,
                    name: value
                        .get("ps")
                        .and_then(|v| v.as_str())
                        .unwrap_or(server)
                        .into(),
                    server: Some(server.into()),
                    port: Some(port as u16),
                    raw: Some(input.into()),
                    fields: serde_json::Value::Object(fields),
                    ..Profile::default()
                });
            }
        }
    }
    let authority = rest.split(['/', '?', '#']).next().unwrap_or(rest);
    let host_port = authority
        .rsplit_once('@')
        .map(|(_, v)| v)
        .unwrap_or(authority);
    let (host, port) = if let Some(stripped) = host_port.strip_prefix('[') {
        let (addr, tail) = stripped.split_once(']').ok_or("invalid IPv6 host")?;
        (addr, tail.strip_prefix(':').ok_or("URI is missing port")?)
    } else {
        host_port.rsplit_once(':').ok_or("URI is missing port")?
    };
    let port = port.parse::<u16>().map_err(|_| "invalid port")?;
    if host.is_empty() {
        return Err("URI is missing server".into());
    }
    let mut fields = serde_json::Map::new();
    fields.insert(
        "authority".into(),
        serde_json::Value::String(authority.into()),
    );
    if let Some((user, _)) = authority.rsplit_once('@') {
        fields.insert("user".into(), serde_json::Value::String(user.to_string()));
    }
    if let Some(query) = rest
        .split_once('?')
        .map(|(_, q)| q.split('#').next().unwrap_or(q))
    {
        for pair in query.split('&').filter(|p| !p.is_empty()) {
            let (key, value) = pair.split_once('=').unwrap_or((pair, ""));
            fields.insert(
                key.to_string(),
                serde_json::Value::String(value.to_string()),
            );
        }
    }
    let name = rest
        .split_once('#')
        .and_then(|(_, fragment)| (!fragment.is_empty()).then_some(fragment))
        .unwrap_or("");
    Ok(Profile {
        protocol,
        name: if name.is_empty() {
            format!("{scheme} {host}:{port}")
        } else {
            name.to_string()
        },
        server: Some(host.to_string()),
        port: Some(port),
        raw: Some(input.to_string()),
        fields: serde_json::Value::Object(fields),
        ..Profile::default()
    })
}

pub fn parse_input(input: &str) -> Result<Vec<Profile>, String> {
    let text = input.trim();
    if text.is_empty() {
        return Err("input is empty".into());
    }
    if !text.contains("://") && !text.starts_with('{') {
        let compact: String = text.lines().map(str::trim).collect();
        if let Some(decoded) = decode_base64(&compact) {
            if let Ok(body) = String::from_utf8(decoded) {
                return parse_input(&body);
            }
        }
    }
    if text.starts_with('{') {
        let value: serde_json::Value =
            serde_json::from_str(text).map_err(|e| format!("invalid JSON: {e}"))?;
        let protocol = value
            .get("protocol")
            .or_else(|| value.get("type"))
            .and_then(|v| v.as_str())
            .unwrap_or("vless");
        let scheme = match protocol.to_ascii_lowercase().as_str() {
            "vmess" => "vmess",
            "trojan" => "trojan",
            "shadowsocks" | "ss" => "ss",
            "socks" => "socks",
            "http" => "http",
            "hysteria2" | "hy2" => "hy2",
            "tuic" => "tuic",
            _ => "vless",
        };
        let server = value
            .get("server")
            .or_else(|| value.get("address"))
            .and_then(|v| v.as_str())
            .ok_or("JSON profile has no server")?;
        let port = value
            .get("port")
            .and_then(|v| v.as_u64())
            .ok_or("JSON profile has no port")?;
        let raw = format!("{scheme}://profile@{server}:{port}");
        return Ok(vec![parse_uri(&raw)?]);
    }
    let profiles: Vec<_> = text
        .lines()
        .filter_map(|line| parse_uri(line).ok())
        .collect();
    if profiles.is_empty() {
        return Err("no supported proxy entries found".into());
    }
    Ok(profiles)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn parses_common_uri() {
        let p = parse_uri("vless://id@example.com:443?security=tls").unwrap();
        assert_eq!(p.protocol, Protocol::Vless);
        assert_eq!(p.port, Some(443));
    }
    #[test]
    fn rejects_unknown_scheme() {
        assert!(parse_uri("ftp://example.com:21").is_err());
    }

    #[test]
    fn preserves_query_and_ipv6() {
        let p = parse_uri("vless://id@[2001:db8::1]:443?security=tls#Office").unwrap();
        assert_eq!(p.server.as_deref(), Some("2001:db8::1"));
        assert_eq!(p.name, "Office");
        assert_eq!(p.fields["security"], "tls");
    }

    #[test]
    fn parses_json_and_multiline_inputs() {
        assert_eq!(
            parse_input(r#"{"protocol":"trojan","server":"example.com","port":443}"#)
                .unwrap()
                .len(),
            1
        );
        assert_eq!(
            parse_input("vless://a@example.com:443\ntrojan://b@example.com:8443")
                .unwrap()
                .len(),
            2
        );
        assert!(parse_input("garbage").is_err());
    }

    #[test]
    fn parses_vmess_base64_and_subscription_payloads() {
        let encoded = "eyJ2IjoiMiIsInBzIjoiT2ZmaWNlIiwiYWRkIjoidnBuLmV4YW1wbGUiLCJwb3J0IjoiNDQzIiwiaWQiOiIwMDAwMDAwMC0wMDAwLTAwMDAtMDAwMC0wMDAwMDAwMDAwMDEiLCJhaWQiOiIwIiwibmV0Ijoid3MifQ==";
        let profile = parse_uri(&format!("vmess://{encoded}")).unwrap();
        assert_eq!(profile.name, "Office");
        assert_eq!(profile.server.as_deref(), Some("vpn.example"));
        assert_eq!(
            parse_input("dmxlc3M6Ly9pZEBleGFtcGxlLmNvbTo0NDM=")
                .unwrap()
                .len(),
            1
        );
    }
}
