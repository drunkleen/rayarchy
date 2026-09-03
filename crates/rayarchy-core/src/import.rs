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

fn percent_decode(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut output = Vec::with_capacity(input.len());
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == b'%' && index + 2 < bytes.len() {
            let hex = &input[index + 1..index + 3];
            if let Ok(value) = u8::from_str_radix(hex, 16) {
                output.push(value);
                index += 3;
                continue;
            }
        }
        output.push(bytes[index]);
        index += 1;
    }
    String::from_utf8_lossy(&output).replace('+', " ")
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
        "anytls" => Protocol::Anytls,
        "naive" | "naive+https" => Protocol::Naive,
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
                serde_json::Value::String(percent_decode(value)),
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
            percent_decode(name)
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
    if text.starts_with('{') || (text.starts_with('[') && !text.contains("[Peer]")) {
        let value: serde_json::Value =
            serde_json::from_str(text).map_err(|e| format!("invalid JSON: {e}"))?;
        if let Some(items) = value.as_array() {
            let mut profiles = Vec::new();
            for item in items {
                profiles.extend(parse_input(&item.to_string())?);
            }
            return Ok(profiles);
        }
        // A single sing-box outbound object (v2rayN "Outbound" profile).
        if value.get("type").and_then(|v| v.as_str()).is_some()
            && (value.get("server").is_some() || value.get("server_port").is_some())
        {
            return Ok(vec![Profile {
                protocol: Protocol::Outbound,
                name: value
                    .get("tag")
                    .and_then(|v| v.as_str())
                    .unwrap_or("Custom outbound")
                    .into(),
                server: value
                    .get("server")
                    .and_then(|v| v.as_str())
                    .map(str::to_string),
                port: value
                    .get("server_port")
                    .and_then(|v| v.as_u64())
                    .map(|p| p as u16),
                raw: Some(text.into()),
                fields: value,
                ..Profile::default()
            }]);
        }
        let protocol = value
            .get("protocol")
            .or_else(|| value.get("type"))
            .and_then(|v| v.as_str())
            .unwrap_or("");
        if protocol.is_empty()
            && (value.get("outbounds").is_some() || value.get("inbounds").is_some())
        {
            // Full core configs stay Custom; a lone `outbounds` array with one
            // entry becomes an Outbound profile (v2rayN behavior).
            if let Some(outbounds) = value.get("outbounds").and_then(|v| v.as_array()) {
                if outbounds.len() == 1 {
                    let mut endpoint = outbounds[0].clone();
                    endpoint["tag"] = serde_json::json!("outbound");
                    return Ok(vec![Profile {
                        protocol: Protocol::Outbound,
                        name: value
                            .get("name")
                            .and_then(|item| item.as_str())
                            .unwrap_or("Custom outbound")
                            .into(),
                        raw: Some(serde_json::to_string(&endpoint).unwrap_or_default()),
                        fields: endpoint,
                        ..Profile::default()
                    }]);
                }
            }
            return Ok(vec![Profile {
                protocol: Protocol::Custom,
                name: value
                    .get("name")
                    .and_then(|item| item.as_str())
                    .unwrap_or("Custom core configuration")
                    .into(),
                raw: Some(text.into()),
                fields: value,
                ..Profile::default()
            }]);
        }
        let scheme = match protocol.to_ascii_lowercase().as_str() {
            "vmess" => "vmess",
            "trojan" => "trojan",
            "shadowsocks" | "ss" => "ss",
            "socks" => "socks",
            "http" => "http",
            "hysteria2" | "hy2" => "hy2",
            "tuic" => "tuic",
            "wireguard" => "wireguard",
            "anytls" => "anytls",
            "naive" => "naive",
            _ => "vless",
        };
        let server = value
            .get("server")
            .or_else(|| value.get("address"))
            .and_then(|v| v.as_str())
            .ok_or("JSON profile has no server")?;
        let port = value
            .get("port")
            .and_then(|v| v.as_u64().or_else(|| v.as_str()?.parse().ok()))
            .ok_or("JSON profile has no port")?;
        let mut profile = Profile {
            protocol: match scheme {
                "ss" => Protocol::Shadowsocks,
                "hy2" => Protocol::Hysteria2,
                "tuic" => Protocol::Tuic,
                "trojan" => Protocol::Trojan,
                "vmess" => Protocol::Vmess,
                "socks" => Protocol::Socks,
                "http" => Protocol::Http,
                "wireguard" => Protocol::Wireguard,
                "anytls" => Protocol::Anytls,
                "naive" => Protocol::Naive,
                _ => Protocol::Vless,
            },
            name: value
                .get("name")
                .or_else(|| value.get("ps"))
                .and_then(|v| v.as_str())
                .unwrap_or(server)
                .into(),
            server: Some(server.into()),
            port: Some(port as u16),
            fields: value.clone(),
            raw: Some(text.into()),
            ..Profile::default()
        };
        if let Some(id) = value
            .get("id")
            .or_else(|| value.get("uuid"))
            .and_then(|v| v.as_str())
        {
            profile.fields["user"] = serde_json::Value::String(id.into());
        }
        return Ok(vec![profile]);
    }
    // v2rayN import order: URIs -> base64 -> SIP008 -> WireGuard -> inner URI
    // -> Clash YAML -> HTML page -> custom configs (handled above).
    if let Some(profiles) = parse_inner_uri(text) {
        return Ok(profiles);
    }
    if let Some(profiles) = parse_sip008(text) {
        return Ok(profiles);
    }
    if text.contains("[Peer]")
        && text
            .lines()
            .any(|line| line.trim_start().starts_with("Endpoint"))
    {
        let endpoint = text
            .lines()
            .find_map(|line| {
                line.trim()
                    .strip_prefix("Endpoint")
                    .and_then(|v| v.trim().strip_prefix('='))
            })
            .map(str::trim)
            .ok_or("WireGuard profile has no endpoint")?;
        let (host, port) = endpoint
            .rsplit_once(':')
            .ok_or("WireGuard endpoint is missing port")?;
        let raw = format!("wireguard://profile@{host}:{port}");
        let mut profile = parse_uri(&raw)?;
        profile.name = "WireGuard".into();
        profile.raw = Some(text.into());
        return Ok(vec![profile]);
    }
    if let Some(profiles) = parse_clash_yaml(text) {
        if !profiles.is_empty() {
            return Ok(profiles);
        }
    }
    if let Some(profiles) = parse_html_page(text) {
        if !profiles.is_empty() {
            return Ok(profiles);
        }
    }
    if text
        .lines()
        .any(|line| line.trim_start().starts_with("server:"))
    {
        let value = |key: &str| {
            text.lines().find_map(|line| {
                line.trim()
                    .strip_prefix(key)
                    .map(str::trim)
                    .map(|v| v.trim_matches(['\"', '\'']).to_string())
            })
        };
        let server = value("server:").ok_or("YAML profile has no server")?;
        let port = value("port:")
            .and_then(|v| v.parse().ok())
            .ok_or("YAML profile has no port")?;
        let protocol = match value("protocol:").as_deref().unwrap_or("vless") {
            "vmess" => Protocol::Vmess,
            "trojan" => Protocol::Trojan,
            "ss" | "shadowsocks" => Protocol::Shadowsocks,
            "socks" => Protocol::Socks,
            "http" => Protocol::Http,
            "hy2" | "hysteria2" => Protocol::Hysteria2,
            "tuic" => Protocol::Tuic,
            "wireguard" => Protocol::Wireguard,
            "anytls" => Protocol::Anytls,
            "naive" => Protocol::Naive,
            _ => Protocol::Vless,
        };
        return Ok(vec![Profile {
            protocol,
            name: value("name:").unwrap_or_else(|| server.clone()),
            server: Some(server),
            port: Some(port),
            raw: Some(text.into()),
            ..Profile::default()
        }]);
    }
    // Base64-wrapped subscription payloads (no URI scheme visible).
    if !text.contains("://") && !text.starts_with('{') {
        let compact: String = text.lines().map(str::trim).collect();
        if let Some(decoded) = decode_base64(&compact) {
            if let Ok(body) = String::from_utf8(decoded) {
                return parse_input(&body);
            }
        }
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

/// Inner URI format v2rayN uses to round-trip the full profile model:
/// `v2rayn://<protocol>/<base64url(profile JSON)>`.
pub fn parse_inner_uri(input: &str) -> Option<Vec<Profile>> {
    let rest = input.trim().strip_prefix("v2rayn://")?;
    let (protocol, encoded) = rest.split_once('/')?;
    let bytes = decode_base64(encoded)?;
    let profile: Profile = serde_json::from_slice(&bytes).ok()?;
    let expected = match protocol.to_ascii_lowercase().as_str() {
        "vless" => Protocol::Vless,
        "vmess" => Protocol::Vmess,
        "trojan" => Protocol::Trojan,
        "shadowsocks" | "ss" => Protocol::Shadowsocks,
        "socks" => Protocol::Socks,
        "http" => Protocol::Http,
        "hysteria2" | "hy2" => Protocol::Hysteria2,
        "tuic" => Protocol::Tuic,
        "wireguard" => Protocol::Wireguard,
        "anytls" => Protocol::Anytls,
        "naive" => Protocol::Naive,
        "custom" => Protocol::Custom,
        "outbound" => Protocol::Outbound,
        "policy-group" => Protocol::PolicyGroup,
        "proxy-chain" => Protocol::ProxyChain,
        _ => return None,
    };
    if profile.protocol != expected {
        return None;
    }
    Some(vec![profile])
}

/// Serialize a profile to the inner URI form.
pub fn to_inner_uri(profile: &Profile) -> String {
    let protocol = match profile.protocol {
        Protocol::Vless => "vless",
        Protocol::Vmess => "vmess",
        Protocol::Trojan => "trojan",
        Protocol::Shadowsocks => "ss",
        Protocol::Socks => "socks",
        Protocol::Http => "http",
        Protocol::Hysteria2 => "hy2",
        Protocol::Tuic => "tuic",
        Protocol::Wireguard => "wireguard",
        Protocol::Anytls => "anytls",
        Protocol::Naive => "naive",
        Protocol::Custom => "custom",
        Protocol::Outbound => "outbound",
        Protocol::PolicyGroup => "policy-group",
        Protocol::ProxyChain => "proxy-chain",
    };
    let json = serde_json::to_string(profile).unwrap_or_default();
    format!("v2rayn://{protocol}/{}", encode_base64(json.as_bytes()))
}

fn encode_base64(input: &[u8]) -> String {
    const ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(input.len().div_ceil(3) * 4);
    for chunk in input.chunks(3) {
        let b = [
            chunk[0],
            *chunk.get(1).unwrap_or(&0),
            *chunk.get(2).unwrap_or(&0),
        ];
        out.push(ALPHABET[(b[0] >> 2) as usize] as char);
        out.push(ALPHABET[(((b[0] & 0x03) << 4) | (b[1] >> 4)) as usize] as char);
        out.push(if chunk.len() > 1 {
            ALPHABET[(((b[1] & 0x0f) << 2) | (b[2] >> 6)) as usize] as char
        } else {
            '='
        });
        out.push(if chunk.len() > 2 {
            ALPHABET[(b[2] & 0x3f) as usize] as char
        } else {
            '='
        });
    }
    out
}

/// SIP008 (`ss://base64({"servers":[...]})`) and base64 JSON SS payloads.
fn parse_sip008(input: &str) -> Option<Vec<Profile>> {
    let rest = input.trim().strip_prefix("ss://")?;
    let bytes = decode_base64(rest)?;
    let value: serde_json::Value = serde_json::from_slice(&bytes).ok()?;
    let servers = value.get("servers")?.as_array()?;
    let mut profiles = Vec::new();
    for server in servers {
        let address = server.get("server").and_then(|v| v.as_str())?;
        let port = server.get("server_port").and_then(|v| v.as_u64())?;
        let mut fields = serde_json::Map::new();
        fields.insert(
            "method".into(),
            serde_json::Value::String(
                server
                    .get("method")
                    .and_then(|v| v.as_str())
                    .unwrap_or("aes-256-gcm")
                    .into(),
            ),
        );
        fields.insert(
            "password".into(),
            server
                .get("password")
                .cloned()
                .unwrap_or_else(|| serde_json::json!("")),
        );
        if let Some(plugin) = server.get("plugin").and_then(|v| v.as_str()) {
            fields.insert("plugin".into(), serde_json::Value::String(plugin.into()));
        }
        profiles.push(Profile {
            protocol: Protocol::Shadowsocks,
            name: server
                .get("remarks")
                .and_then(|v| v.as_str())
                .unwrap_or(address)
                .into(),
            server: Some(address.into()),
            port: Some(port as u16),
            raw: Some(format!("ss://{}", encode_base64(&bytes))),
            fields: serde_json::Value::Object(fields),
            ..Profile::default()
        });
    }
    (!profiles.is_empty()).then_some(profiles)
}

/// Minimal Clash YAML parser for `proxies:` blocks (flat `key: value` entries).
fn parse_clash_yaml(input: &str) -> Option<Vec<Profile>> {
    let text = input.trim();
    if !text.lines().any(|l| l.trim_start() == "proxies:")
        && !text.lines().any(|l| l.trim_start().starts_with("proxies:"))
    {
        return None;
    }
    let mut entries: Vec<serde_json::Map<String, serde_json::Value>> = Vec::new();
    let mut current: Option<serde_json::Map<String, serde_json::Value>> = None;
    for line in text.lines() {
        if line.trim_start().is_empty() || line.trim_start().starts_with('#') {
            continue;
        }
        if line.trim_start() == "proxies:" {
            continue;
        }
        // A new proxy block: `- name: ...`
        if let Some(rest) = line.trim_start().strip_prefix("- ") {
            if let Some(map) = current.take() {
                entries.push(map);
            }
            current = Some(serde_json::Map::new());
            if let Some((k, v)) = rest.split_once(':') {
                current.as_mut().unwrap().insert(
                    k.trim().to_string(),
                    serde_json::Value::String(v.trim().trim_matches(['\"', '\'']).to_string()),
                );
            }
            continue;
        }
        let Some(map) = current.as_mut() else {
            continue;
        };
        if let Some((k, v)) = line.trim_start().split_once(':') {
            let value = v.trim().trim_matches(['\"', '\'']).to_string();
            if value.is_empty() {
                map.insert(k.trim().to_string(), serde_json::Value::Null);
            } else {
                map.insert(k.trim().to_string(), serde_json::Value::String(value));
            }
        }
    }
    if let Some(map) = current.take() {
        entries.push(map);
    }
    let mut profiles = Vec::new();
    for entry in entries {
        let Some(server) = entry.get("server").and_then(|v| v.as_str()) else {
            continue;
        };
        let port = match entry.get("port") {
            Some(serde_json::Value::Number(n)) => n.as_u64().unwrap_or(0) as u16,
            Some(serde_json::Value::String(s)) => s.parse::<u16>().unwrap_or(0),
            _ => 0,
        };
        if port == 0 {
            continue;
        }
        let ty = entry
            .get("type")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_lowercase();
        let protocol = match ty.as_str() {
            "vmess" => Protocol::Vmess,
            "trojan" => Protocol::Trojan,
            "ss" | "shadowsocks" => Protocol::Shadowsocks,
            "socks5" | "socks" => Protocol::Socks,
            "http" => Protocol::Http,
            "hysteria2" => Protocol::Hysteria2,
            "tuic" => Protocol::Tuic,
            "wireguard" => Protocol::Wireguard,
            "anytls" => Protocol::Anytls,
            _ => Protocol::Vless,
        };
        let mut fields = serde_json::Map::new();
        let mut push = |key: &str, field: &str| {
            if let Some(value) = entry.get(key).and_then(|v| v.as_str()) {
                if !value.is_empty() {
                    fields.insert(
                        field.to_string(),
                        serde_json::Value::String(value.to_string()),
                    );
                }
            }
        };
        push("uuid", "user");
        push("username", "user");
        push("password", "password");
        push("cipher", "method");
        push("method", "method");
        push("sni", "sni");
        push("servername", "sni");
        push("flow", "flow");
        push("network", "type");
        if let Some(ws) = entry.get("ws-opts").and_then(|v| v.as_str()) {
            // ws-opts in flat clash exports is usually inline; best-effort split.
            if let Some(path) = ws.split(',').find_map(|p| p.trim().strip_prefix("path=")) {
                fields.insert(
                    "path".into(),
                    serde_json::Value::String(path.trim_matches(['\"', '\'']).into()),
                );
            }
        }
        if let Some(tls) = entry.get("tls").and_then(|v| v.as_str()) {
            if tls == "true" || tls == "1" {
                fields.insert("security".into(), serde_json::Value::String("tls".into()));
            }
        }
        if entry.get("tls").is_some_and(|v| v.as_bool() == Some(true)) {
            fields.insert("security".into(), serde_json::Value::String("tls".into()));
        }
        let name = entry.get("name").and_then(|v| v.as_str()).unwrap_or(server);
        profiles.push(Profile {
            protocol,
            name: name.into(),
            server: Some(server.into()),
            port: Some(port),
            raw: Some(serde_json::to_string(&serde_json::Value::Object(entry)).unwrap_or_default()),
            fields: serde_json::Value::Object(fields),
            ..Profile::default()
        });
    }
    (!profiles.is_empty()).then_some(profiles)
}

/// HTML pages that embed share links (some providers render subscriptions as
/// a web page instead of a plain text payload).
fn parse_html_page(input: &str) -> Option<Vec<Profile>> {
    let text = input.trim();
    if !text.contains('<') || !text.to_lowercase().contains("html") {
        return None;
    }
    let schemes = [
        "vmess",
        "vless",
        "trojan",
        "ss",
        "hysteria2",
        "hy2",
        "tuic",
        "wireguard",
        "anytls",
        "naive+https",
        "naive",
        "socks5",
    ];
    let mut profiles = Vec::new();
    for scheme in schemes {
        let marker = format!("{scheme}://");
        let mut start = 0;
        while let Some(relative) = text[start..].find(&marker) {
            let absolute = start + relative;
            if absolute > 0 {
                let prev = text.as_bytes()[absolute - 1];
                if prev.is_ascii_alphanumeric() || prev == b'+' || prev == b'-' || prev == b'.' {
                    start = absolute + marker.len();
                    continue;
                }
            }
            let remaining = &text[absolute..];
            let end = remaining
                .find(['<', '"', '\'', ' ', '\n', '>'])
                .unwrap_or(remaining.len());
            let uri = &remaining[..end];
            if let Ok(profile) = parse_uri(uri) {
                profiles.push(profile);
            }
            start = absolute + marker.len();
        }
    }
    (!profiles.is_empty()).then_some(profiles)
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

    #[test]
    fn parses_json_arrays_yaml_and_wireguard() {
        assert_eq!(parse_input(r#"[{"protocol":"vless","server":"a.example","port":443},{"protocol":"trojan","server":"b.example","port":"8443"}]"#).unwrap().len(), 2);
        let yaml = "name: Office\nprotocol: trojan\nserver: vpn.example\nport: 443";
        assert_eq!(parse_input(yaml).unwrap()[0].protocol, Protocol::Trojan);
        let wg = "[Interface]\nPrivateKey = hidden\n[Peer]\nEndpoint = vpn.example:51820";
        assert_eq!(parse_input(wg).unwrap()[0].protocol, Protocol::Wireguard);
    }

    #[test]
    fn decodes_uri_display_name_and_query_values() {
        let profile =
            parse_uri("vless://id@example.com:443?path=%2Fray%20ws#Office%20%E2%9C%93").unwrap();
        assert_eq!(profile.name, "Office ✓");
        assert_eq!(profile.fields["path"], "/ray ws");
    }

    #[test]
    fn parses_anytls_naive_and_full_custom_configs() {
        assert_eq!(
            parse_uri("anytls://alice@edge.example:443#AnyTLS")
                .unwrap()
                .protocol,
            Protocol::Anytls
        );
        assert_eq!(
            parse_uri("naive+https://alice:secret@edge.example:443#Naive")
                .unwrap()
                .protocol,
            Protocol::Naive
        );
        let custom = parse_input(r#"{"inbounds":[],"outbounds":[]}"#).unwrap();
        assert_eq!(custom[0].protocol, Protocol::Custom);
    }

    #[test]
    fn parses_outbound_profiles_from_json() {
        let endpoint = r#"{"type":"vless","tag":"out","server":"edge.example","server_port":443,"uuid":"00000000-0000-0000-0000-000000000001","tls":{"enabled":true}}"#;
        let profiles = parse_input(endpoint).unwrap();
        assert_eq!(profiles[0].protocol, Protocol::Outbound);
        assert_eq!(profiles[0].server.as_deref(), Some("edge.example"));

        let wrapped = r#"{"outbounds":[{"type":"trojan","server":"a.example","server_port":443}]}"#;
        let profiles = parse_input(wrapped).unwrap();
        assert_eq!(profiles[0].protocol, Protocol::Outbound);
        assert!(profiles[0].raw.as_deref().unwrap().contains("trojan"));
    }

    #[test]
    fn inner_uri_round_trips_profiles() {
        let profile = Profile {
            name: "Office ✓".into(),
            protocol: Protocol::Vless,
            server: Some("edge.example".into()),
            port: Some(443),
            fields: serde_json::json!({"security":"tls","type":"ws"}),
            ..Default::default()
        };
        let uri = to_inner_uri(&profile);
        assert!(uri.starts_with("v2rayn://vless/"));
        let parsed = parse_inner_uri(&uri).unwrap();
        assert_eq!(parsed[0].protocol, Protocol::Vless);
        assert_eq!(parsed[0].name, "Office ✓");
        assert_eq!(parsed[0].fields["type"], "ws");
    }

    #[test]
    fn parses_sip008_and_clash_yaml() {
        let sip008 = "ss://eyJzZXJ2ZXJzIjpbeyJzZXJ2ZXIiOiJzLmV4YW1wbGUiLCJzZXJ2ZXJfcG9ydCI6ODM4OCwibWV0aG9kIjoiYWVzLTI1Ni1nY20iLCJwYXNzd29yZCI6InBhc3MifV19";
        let profiles = parse_input(sip008).unwrap();
        assert_eq!(profiles[0].protocol, Protocol::Shadowsocks);
        assert_eq!(profiles[0].port, Some(8388));

        let clash = r#"
proxies:
  - name: "Clash WS"
    type: vless
    server: c.example
    port: 443
    uuid: 00000000-0000-0000-0000-000000000002
    tls: true
    network: ws
    ws-opts:
      path: /ray
  - name: "Clash SS"
    type: ss
    server: s.example
    port: 8388
    cipher: aes-256-gcm
    password: p
"#;
        let profiles = parse_input(clash).unwrap();
        assert_eq!(profiles.len(), 2);
        assert_eq!(profiles[0].protocol, Protocol::Vless);
        assert_eq!(profiles[0].fields["security"], "tls");
        assert_eq!(profiles[1].protocol, Protocol::Shadowsocks);
    }

    #[test]
    fn extracts_proxy_links_from_html() {
        let html = r#"<html><body>vless://id@a.example:443#Web <a href="vmess://eyJmb28iOiJiYXIifQ==">link</a></body></html>"#;
        let profiles = parse_input(html).unwrap();
        assert_eq!(profiles.len(), 1);
        assert_eq!(profiles[0].protocol, Protocol::Vless);
    }
}
