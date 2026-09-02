use crate::model::Profile;
use crate::protocol::Protocol;

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
}
