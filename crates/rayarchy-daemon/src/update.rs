use std::path::{Path, PathBuf};

/// Core and geo asset metadata used by the Check Update dialog.
pub const CORES: &[&str] = &["xray", "sing-box"];
pub const GEO_ASSETS: &[&str] = &["geoip.dat", "geosite.dat"];

/// GitHub API endpoint for the latest release of a given repository.
pub fn latest_release_api(repo: &str) -> String {
    format!("https://api.github.com/repos/{repo}/releases/latest")
}

/// Map a core name to its upstream repository.
pub fn core_repo(core: &str) -> Option<&'static str> {
    match core {
        "xray" => Some("XTLS/Xray-core"),
        "sing-box" => Some("SagerNet/sing-box"),
        _ => None,
    }
}

/// The geo data assets ship from the v2ray-rules-dat project.
pub fn geo_repo() -> &'static str {
    "Loyalsoldier/v2ray-rules-dat"
}

/// Asset name for a core binary on linux-amd64.
pub fn core_asset_name(core: &str, tag: &str) -> Option<String> {
    match core {
        "xray" => Some("Xray-linux-64.zip".to_string()),
        "sing-box" => Some(format!("sing-box-{tag}-linux-amd64.tar.gz")),
        _ => None,
    }
}

/// Extract the bare binary name inside the core archive.
pub fn core_binary_name(core: &str) -> &'static str {
    match core {
        "xray" => "xray",
        "sing-box" => "sing-box",
        _ => "xray",
    }
}

/// Parse the `tag_name` from a GitHub releases/latest JSON payload.
pub fn tag_from_latest(payload: &str) -> Option<String> {
    serde_json::from_str::<serde_json::Value>(payload)
        .ok()
        .and_then(|v| {
            v.get("tag_name")
                .and_then(|t| t.as_str())
                .map(str::to_string)
        })
}

/// Parse a `sha256sum` style asset listing into a map of filename -> hash.
pub fn parse_sha256sums(payload: &str) -> Vec<(String, String)> {
    payload
        .lines()
        .filter_map(|line| {
            let mut parts = line.split_whitespace();
            let hash = parts.next()?.to_lowercase();
            let file = parts.next()?.to_string();
            Some((file, hash))
        })
        .collect()
}

/// Find the checksum line for a given filename.
pub fn checksum_for<'a>(entries: &'a [(String, String)], file: &str) -> Option<&'a str> {
    entries
        .iter()
        .find(|(name, _)| name == file || file.ends_with(name))
        .map(|(_, hash)| hash.as_str())
}

/// Write bytes to a file under the data bin dir.
pub fn write_bin(bin_dir: &Path, name: &str, bytes: &[u8]) -> std::io::Result<PathBuf> {
    std::fs::create_dir_all(bin_dir)?;
    let path = bin_dir.join(name);
    std::fs::write(&path, bytes)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755))?;
    }
    Ok(path)
}

/// Verify a downloaded archive's sha256 against the expected hash.
pub fn verify_sha256(bytes: &[u8], expected: &str) -> bool {
    use sha2::Digest;
    let digest = sha2::Sha256::digest(bytes);
    let actual = format!("{digest:x}");
    actual.eq_ignore_ascii_case(expected.trim())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn asset_names_and_binaries_map_to_cores() {
        assert_eq!(
            core_asset_name("xray", "v1.8.24").unwrap(),
            "Xray-linux-64.zip"
        );
        assert_eq!(
            core_asset_name("sing-box", "1.11.0").unwrap(),
            "sing-box-1.11.0-linux-amd64.tar.gz"
        );
        assert_eq!(core_binary_name("xray"), "xray");
        assert_eq!(core_binary_name("sing-box"), "sing-box");
    }

    #[test]
    fn parses_github_latest_payload() {
        let payload = r#"{"tag_name":"v1.8.24","assets":[]}"#;
        assert_eq!(tag_from_latest(payload).unwrap(), "v1.8.24");
    }

    #[test]
    fn parses_sha256sum_listings() {
        let payload = "aaa geosite.dat\nbbb geoip.dat\n";
        let entries = parse_sha256sums(payload);
        assert_eq!(entries.len(), 2);
        assert_eq!(checksum_for(&entries, "geoip.dat").unwrap(), "bbb");
        assert!(verify_sha256(
            &[],
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        ));
    }
}
