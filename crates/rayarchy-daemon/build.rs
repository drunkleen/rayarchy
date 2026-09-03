// Embeds the release version from the repo-root manifest.json so every
// binary's --version matches the published release. The fallback is the
// Cargo package version.
use std::path::Path;

fn main() {
    let manifest = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../manifest.json");
    println!("cargo:rerun-if-changed={}", manifest.display());
    if let Ok(text) = std::fs::read_to_string(&manifest) {
        if let Some(version) = extract_version(&text) {
            println!("cargo:rustc-env=RAYARCHY_VERSION={version}");
        }
    }
}

fn extract_version(text: &str) -> Option<String> {
    let marker = "\"version\":";
    let idx = text.find(marker)?;
    let rest = &text[idx + marker.len()..];
    let start = rest.find('"')? + 1;
    let end = rest[start..].find('"')? + start;
    Some(rest[start..end].to_string())
}
