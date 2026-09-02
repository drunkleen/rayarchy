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
    let (host, port) = host_port.rsplit_once(':').ok_or("URI is missing port")?;
    let port = port.parse::<u16>().map_err(|_| "invalid port")?;
    if host.is_empty() {
        return Err("URI is missing server".into());
    }
    let mut profile = Profile::default();
    profile.protocol = protocol;
    profile.name = format!("{scheme} {host}:{port}");
    profile.server = Some(host.trim_matches(['[', ']']).to_string());
    profile.port = Some(port);
    profile.raw = Some(input.to_string());
    profile.fields = serde_json::json!({"authority": authority});
    Ok(profile)
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
}
