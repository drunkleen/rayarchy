use rayarchy_core::{Profile, RoutingRule, Settings, Subscription};
use std::collections::HashMap;
use std::{
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, AtomicU32, Ordering},
        Arc,
    },
};
use tokio::io::AsyncReadExt;
use tokio::sync::Mutex;
pub mod configgen;
pub mod server;
pub mod sysproxy;
pub mod udp;
pub mod update;

fn command_exists(name: &str) -> bool {
    std::env::var_os("PATH")
        .map(|path| std::env::split_paths(&path).any(|dir| dir.join(name).is_file()))
        .unwrap_or(false)
}

/// Prefer a locally-managed core under the data bin dir, falling back to PATH.
fn resolve_bin(bin_dir: &std::path::Path, name: &str) -> PathBuf {
    let local = bin_dir.join(name);
    if local.is_file() {
        local
    } else {
        PathBuf::from(name)
    }
}

fn valid_subscription_url(url: &str) -> bool {
    let trimmed = url.trim();
    (trimmed.starts_with("https://") || trimmed.starts_with("http://")) && trimmed.len() > 8
}

fn urlencoding(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for byte in input.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(byte as char)
            }
            _ => out.push_str(&format!("%{byte:02X}")),
        }
    }
    out
}

/// Parse cumulative up/down traffic from the core's observation endpoint.
/// sing-box `/traffic` streams `{"up":N,"down":N}` lines; xray `/debug/vars`
/// exposes Go expvar counters whose keys contain `traffic|uplink` /
/// `traffic|downlink`.
fn parse_traffic(core: rayarchy_core::protocol::Core, body: &[u8]) -> Option<serde_json::Value> {
    let text = String::from_utf8_lossy(body);
    if core == rayarchy_core::protocol::Core::SingBox {
        let first = text
            .lines()
            .find(|line| line.trim_start().starts_with('{'))?;
        let value: serde_json::Value = serde_json::from_str(first).ok()?;
        let up = value.get("up").and_then(|v| v.as_u64()).unwrap_or(0);
        let down = value.get("down").and_then(|v| v.as_u64()).unwrap_or(0);
        return Some(serde_json::json!({"up": up, "down": down}));
    }
    let value: serde_json::Value = serde_json::from_str(&text).ok()?;
    let mut up = 0u64;
    let mut down = 0u64;
    if let Some(object) = value.as_object() {
        for (key, counter) in object {
            if key.contains("traffic|uplink") {
                up = up.saturating_add(as_counter(counter));
            } else if key.contains("traffic|downlink") {
                down = down.saturating_add(as_counter(counter));
            }
        }
    }
    Some(serde_json::json!({"up": up, "down": down}))
}

fn as_counter(value: &serde_json::Value) -> u64 {
    value
        .as_u64()
        .or_else(|| value.as_str()?.parse().ok())
        .unwrap_or(0)
}

/// Extract an archive (zip or tar.gz) in memory using system tools and return
/// the file paths of the entries. Used by the core installer.
fn extract_archive(asset: &str, bytes: &[u8]) -> Option<Vec<Vec<u8>>> {
    let tmp = std::env::temp_dir().join(format!("rayarchy-extract-{}", uuid::Uuid::new_v4()));
    std::fs::create_dir_all(&tmp).ok()?;
    let archive_path = tmp.join("archive.bin");
    std::fs::write(&archive_path, bytes).ok()?;
    let status = if asset.ends_with(".zip") {
        std::process::Command::new("unzip")
            .arg("-o")
            .arg(&archive_path)
            .arg("-d")
            .arg(&tmp)
            .status()
            .ok()
    } else if asset.ends_with(".tar.gz") || asset.ends_with(".tgz") {
        std::process::Command::new("tar")
            .arg("-xzf")
            .arg(&archive_path)
            .arg("-C")
            .arg(&tmp)
            .status()
            .ok()
    } else {
        None
    };
    let success = status.map(|s| s.success()).unwrap_or(false);
    let mut files = Vec::new();
    if success {
        collect_files(&tmp, &mut files);
    }
    let _ = std::fs::remove_dir_all(&tmp);
    success.then_some(files)
}

fn collect_files(dir: &std::path::Path, out: &mut Vec<Vec<u8>>) {
    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                collect_files(&path, out);
            } else if let Ok(bytes) = std::fs::read(&path) {
                out.push(bytes);
            }
        }
    }
}

fn validate_profile(profile: &Profile) -> Result<(), String> {
    use rayarchy_core::protocol::Protocol;

    if matches!(
        profile.protocol,
        Protocol::PolicyGroup | Protocol::ProxyChain
    ) {
        let minimum = if profile.protocol == Protocol::ProxyChain {
            2
        } else {
            1
        };
        if profile.members.len() < minimum {
            return Err(format!(
                "{} requires at least {minimum} member profile(s)",
                if profile.protocol == Protocol::ProxyChain {
                    "proxy chain"
                } else {
                    "policy group"
                }
            ));
        }
        if profile.protocol == Protocol::PolicyGroup
            && !matches!(
                profile.strategy.as_deref().unwrap_or("manual"),
                "manual" | "latency" | "fallback" | "load_balance"
            )
        {
            return Err("unsupported policy-group strategy".into());
        }
        return Ok(());
    }
    if profile.protocol == Protocol::Custom {
        let raw = profile.raw.as_deref().unwrap_or("").trim();
        if raw.is_empty() {
            return Err("custom profile requires a raw core configuration".into());
        }
        serde_json::from_str::<serde_json::Value>(raw)
            .map_err(|_| "custom profile configuration must be valid JSON".to_string())?;
        return Ok(());
    }
    if profile.protocol == Protocol::Outbound {
        let raw = profile.raw.as_deref().unwrap_or("").trim();
        if raw.is_empty() {
            return Err("outbound profile requires a sing-box outbound configuration".into());
        }
        let value: serde_json::Value = serde_json::from_str(raw)
            .map_err(|_| "outbound profile configuration must be valid JSON".to_string())?;
        if value
            .get("type")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .is_empty()
        {
            return Err("outbound profile configuration must include a type".into());
        }
        return Ok(());
    }
    if profile.server.as_deref().unwrap_or("").trim().is_empty() {
        return Err("profile server is required".into());
    }
    if profile.port == Some(0) {
        return Err("profile port must be between 1 and 65535".into());
    }
    if matches!(
        profile.protocol,
        rayarchy_core::protocol::Protocol::Vless
            | rayarchy_core::protocol::Protocol::Vmess
            | rayarchy_core::protocol::Protocol::Tuic
            | rayarchy_core::protocol::Protocol::Anytls
    ) && profile
        .fields
        .as_object()
        .is_some_and(|fields| !fields.is_empty())
    {
        let user = profile
            .fields
            .get("user")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        if user.trim().is_empty() {
            return Err("profile credential/UUID is required".into());
        }
        if matches!(
            profile.protocol,
            rayarchy_core::protocol::Protocol::Vless | rayarchy_core::protocol::Protocol::Vmess
        ) && uuid::Uuid::parse_str(user).is_err()
        {
            return Err("VLESS/VMess user must be a valid UUID".into());
        }
    }
    if let Some(security) = profile.fields.get("security").and_then(|v| v.as_str()) {
        if !security.is_empty() && !matches!(security, "tls" | "none") {
            return Err("security must be tls or none".into());
        }
    }
    if let Some(network) = profile
        .fields
        .get("type")
        .or_else(|| profile.fields.get("network"))
        .and_then(|v| v.as_str())
    {
        if !network.is_empty()
            && !matches!(
                network,
                "tcp" | "ws" | "grpc" | "http" | "h2" | "httpupgrade" | "xhttp" | "quic"
            )
        {
            return Err("unsupported transport network".into());
        }
    }
    Ok(())
}

fn validate_profile_members(profile: &Profile, profiles: &[Profile]) -> Result<(), String> {
    if !matches!(
        profile.protocol,
        rayarchy_core::protocol::Protocol::PolicyGroup
            | rayarchy_core::protocol::Protocol::ProxyChain
    ) {
        return Ok(());
    }
    let mut unique = std::collections::HashSet::new();
    for member in &profile.members {
        if *member == profile.id {
            return Err("a profile cannot contain itself".into());
        }
        if !unique.insert(*member) {
            return Err("member profiles must be unique".into());
        }
        let Some(candidate) = profiles.iter().find(|item| item.id == *member) else {
            return Err(format!("member profile {member} was not found"));
        };
        if !candidate.enabled {
            return Err(format!("member profile {} is disabled", candidate.name));
        }
        if matches!(
            candidate.protocol,
            rayarchy_core::protocol::Protocol::PolicyGroup
                | rayarchy_core::protocol::Protocol::ProxyChain
        ) {
            return Err("nested policy groups and proxy chains are not supported".into());
        }
    }
    Ok(())
}

fn profiles_equivalent(left: &Profile, right: &Profile) -> bool {
    left.protocol == right.protocol
        && left.server == right.server
        && left.port == right.port
        && left.fields == right.fields
        && left.raw == right.raw
        && left.members == right.members
        && left.strategy == right.strategy
}

fn validate_rule(rule: &RoutingRule) -> Result<(), String> {
    if rule.name.trim().is_empty() || rule.value.trim().is_empty() {
        return Err("routing rule name and value are required".into());
    }
    if !matches!(
        rule.match_type.as_str(),
        "domain" | "domain_suffix" | "domain_keyword" | "cidr" | "ip"
    ) {
        return Err("unsupported routing match type".into());
    }
    if !matches!(rule.action.as_str(), "proxy" | "direct" | "block") {
        return Err("unsupported routing action".into());
    }
    if matches!(rule.match_type.as_str(), "cidr" | "ip") {
        let (address, prefix) = rule
            .value
            .split_once('/')
            .ok_or("CIDR rule must include a prefix")?;
        address
            .parse::<std::net::IpAddr>()
            .map_err(|_| "invalid CIDR address")?;
        let max = if address.contains(':') { 128 } else { 32 };
        if prefix
            .parse::<u8>()
            .ok()
            .filter(|value| *value <= max)
            .is_none()
        {
            return Err("invalid CIDR prefix".into());
        }
    }
    Ok(())
}

async fn validate_core_config(
    core: rayarchy_core::protocol::Core,
    path: &std::path::Path,
    bin_dir: &std::path::Path,
) -> Result<(), String> {
    let name = if core == rayarchy_core::protocol::Core::SingBox {
        "sing-box"
    } else {
        "xray"
    };
    let bin = resolve_bin(bin_dir, name);
    let args: &[&str] = if core == rayarchy_core::protocol::Core::SingBox {
        &["check", "-c"]
    } else {
        &["run", "-test", "-c"]
    };
    let output = tokio::process::Command::new(&bin)
        .args(args)
        .arg(path)
        .output()
        .await
        .map_err(|e| format!("could not validate {name} config: {e}"))?;
    if output.status.success() {
        Ok(())
    } else {
        let detail = String::from_utf8_lossy(&output.stderr).trim().to_string();
        Err(if detail.is_empty() {
            format!("{name} rejected the generated configuration")
        } else {
            format!("{name} rejected the generated configuration: {detail}")
        })
    }
}

async fn command_version(name: &str, bin_dir: &std::path::Path) -> Option<String> {
    let bin = resolve_bin(bin_dir, name);
    let output = tokio::process::Command::new(&bin)
        .arg("--version")
        .output()
        .await
        .ok()?;
    output
        .status
        .success()
        .then(|| String::from_utf8_lossy(&output.stdout).trim().to_string())
}

#[derive(Default, serde::Serialize, serde::Deserialize)]
struct ProfileStats {
    #[serde(default)]
    today_up: u64,
    #[serde(default)]
    today_down: u64,
    #[serde(default)]
    total_up: u64,
    #[serde(default)]
    total_down: u64,
    #[serde(default)]
    day: String,
}

#[derive(Default, serde::Serialize, serde::Deserialize)]
struct Database {
    #[serde(default)]
    profiles: Vec<Profile>,
    #[serde(default)]
    subscriptions: Vec<Subscription>,
    #[serde(default)]
    routing: Vec<RoutingRule>,
    #[serde(default)]
    test_history: Vec<serde_json::Value>,
    #[serde(default)]
    settings: Settings,
    /// Cumulative per-profile traffic counters keyed by profile id.
    #[serde(default)]
    statistics: std::collections::HashMap<String, ProfileStats>,
}

pub struct Daemon {
    db: Mutex<Database>,
    path: PathBuf,
    bin_dir: PathBuf,
    connected: Mutex<Option<uuid::Uuid>>,
    process: Mutex<Option<tokio::process::Child>>,
    child_pid: AtomicU32,
    config_path: PathBuf,
    proxy_backup: Mutex<Option<sysproxy::Backup>>,
    logs: Mutex<Vec<String>>,
    bulk_cancel: AtomicBool,
    last_ip: Mutex<Option<serde_json::Value>>,
    core_started_at: Mutex<Option<i64>>,
}
impl Daemon {
    pub fn new(path: PathBuf) -> anyhow::Result<Arc<Self>> {
        let db = if path.exists() {
            serde_json::from_slice(&std::fs::read(&path)?)?
        } else {
            Database::default()
        };
        let bin_dir = std::env::var_os("XDG_DATA_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| std::env::temp_dir().join("rayarchy-data"))
            .join("rayarchy/bin");
        Ok(Arc::new(Self {
            db: Mutex::new(db),
            path,
            bin_dir,
            connected: Mutex::new(None),
            process: Mutex::new(None),
            child_pid: AtomicU32::new(0),
            config_path: std::env::temp_dir().join("rayarchy/config.json"),
            proxy_backup: Mutex::new(None),
            logs: Mutex::new(Vec::new()),
            bulk_cancel: AtomicBool::new(false),
            last_ip: Mutex::new(None),
            core_started_at: Mutex::new(None),
        }))
    }
    async fn save(&self) -> anyhow::Result<()> {
        let db = self.db.lock().await;
        let bytes = serde_json::to_vec_pretty(&*db)?;
        if let Some(p) = self.path.parent() {
            std::fs::create_dir_all(p)?;
        }
        let tmp = self.path.with_extension("json.tmp");
        std::fs::write(&tmp, bytes)?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&tmp, std::fs::Permissions::from_mode(0o600))?;
        }
        std::fs::rename(tmp, &self.path)?;
        Ok(())
    }
    async fn log(&self, line: impl Into<String>) {
        let mut logs = self.logs.lock().await;
        logs.push(line.into());
        if logs.len() > 500 {
            logs.remove(0);
        }
    }

    async fn set_subscription_error(&self, id: uuid::Uuid, error: Option<String>) {
        if let Some(subscription) = self
            .db
            .lock()
            .await
            .subscriptions
            .iter_mut()
            .find(|s| s.id == id)
        {
            subscription.last_error = error;
            subscription.last_refresh_at = Some(chrono::Utc::now().timestamp());
        }
        let _ = self.save().await;
    }

    /// Start the unprivileged subscription refresh loop. The loop is deliberately
    /// coarse (one hour) so a bad source cannot cause a request storm.
    pub fn spawn_subscription_scheduler(self: &Arc<Self>) {
        let daemon = Arc::clone(self);
        tokio::spawn(async move {
            let mut refreshed: HashMap<uuid::Uuid, std::time::Instant> = HashMap::new();
            let mut ticker = tokio::time::interval(std::time::Duration::from_secs(3600));
            ticker.tick().await;
            loop {
                let now = std::time::Instant::now();
                let subscriptions = daemon.db.lock().await.subscriptions.clone();
                for subscription in subscriptions {
                    if !subscription.enabled
                        || matches!(
                            subscription.auto_update,
                            rayarchy_core::model::AutoUpdate::Off
                        )
                    {
                        continue;
                    }
                    let interval = match subscription.auto_update {
                        rayarchy_core::model::AutoUpdate::Startup => {
                            std::time::Duration::from_secs(u64::MAX / 2)
                        }
                        rayarchy_core::model::AutoUpdate::Daily => {
                            std::time::Duration::from_secs(86_400)
                        }
                        rayarchy_core::model::AutoUpdate::Every6Hours => {
                            std::time::Duration::from_secs(21_600)
                        }
                        rayarchy_core::model::AutoUpdate::Off => continue,
                    };
                    if refreshed
                        .get(&subscription.id)
                        .is_some_and(|last| now.duration_since(*last) < interval)
                    {
                        continue;
                    }
                    let result = daemon
                        .dispatch(
                            "subscription.refresh",
                            serde_json::json!({"subscriptionId":subscription.id}),
                        )
                        .await;
                    refreshed.insert(subscription.id, now);
                    if let Some(error) = result.get("error").and_then(|v| v.as_str()) {
                        daemon
                            .log(format!("subscription refresh failed: {error}"))
                            .await;
                    }
                }
                ticker.tick().await;
            }
        });
    }

    async fn connect_profile(self: &Arc<Self>, id: uuid::Uuid) -> Result<(), String> {
        let (profile, settings, profiles, rules, history) = {
            let db = self.db.lock().await;
            (
                db.profiles
                    .iter()
                    .find(|p| p.id == id && p.enabled)
                    .cloned()
                    .ok_or("profile not found")?,
                db.settings.clone(),
                db.profiles.clone(),
                db.routing.clone(),
                db.test_history.clone(),
            )
        };
        if matches!(
            settings.connection_mode,
            rayarchy_core::protocol::ConnectionMode::Tun
                | rayarchy_core::protocol::ConnectionMode::Transparent
        ) {
            return Err(
                "selected mode requires the Rayarchy privileged helper and is not enabled yet"
                    .into(),
            );
        }
        let selected = if profile.protocol == rayarchy_core::protocol::Protocol::PolicyGroup {
            let mut candidates: Vec<_> = profile
                .members
                .iter()
                .filter_map(|member| profiles.iter().find(|item| item.id == *member))
                .cloned()
                .collect();
            match profile.strategy.as_deref().unwrap_or("manual") {
                "latency" => candidates.sort_by_key(|candidate| {
                    history
                        .iter()
                        .rev()
                        .find(|row| {
                            row["profileId"].as_str() == Some(&candidate.id.to_string())
                                && row["ok"].as_bool() == Some(true)
                        })
                        .and_then(|row| row["latencyMs"].as_u64())
                        .unwrap_or(u64::MAX)
                }),
                "load_balance" if !candidates.is_empty() => {
                    let rotate =
                        chrono::Utc::now().timestamp().unsigned_abs() as usize % candidates.len();
                    candidates.rotate_left(rotate);
                }
                _ => {}
            }
            candidates
                .into_iter()
                .next()
                .ok_or("policy group has no available members")?
        } else {
            profile.clone()
        };
        let core = if profile.protocol == rayarchy_core::protocol::Protocol::ProxyChain {
            rayarchy_core::protocol::Core::SingBox
        } else {
            configgen::choose_core(&selected, settings.preferred_core)
        };
        let mut config = if profile.protocol == rayarchy_core::protocol::Protocol::ProxyChain {
            let members: Vec<_> = profile
                .members
                .iter()
                .filter_map(|member| profiles.iter().find(|item| item.id == *member))
                .cloned()
                .collect();
            configgen::build_chain(&members, "127.0.0.1", settings.local_port)?
        } else {
            configgen::build(&selected, core, "127.0.0.1", settings.local_port)
        };
        configgen::apply_rules(&mut config, core, &rules);
        configgen::apply_dns(&mut config, core, settings.dns_leak_protection);
        configgen::apply_lan_bypass(&mut config, core, settings.lan_bypass);
        configgen::apply_stats(&mut config, core, settings.local_port);
        if let Some(parent) = self.config_path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        std::fs::write(
            &self.config_path,
            serde_json::to_vec_pretty(&config).map_err(|e| e.to_string())?,
        )
        .map_err(|e| e.to_string())?;
        let bin = if core == rayarchy_core::protocol::Core::SingBox {
            "sing-box"
        } else {
            "xray"
        };
        validate_core_config(core, &self.config_path, &self.bin_dir).await?;
        let child = tokio::process::Command::new(resolve_bin(&self.bin_dir, bin))
            .args(["run", "-c"])
            .arg(&self.config_path)
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::piped())
            .spawn()
            .map_err(|e| format!("could not start {bin}: {e}"))?;
        self.child_pid
            .store(child.id().unwrap_or(0), Ordering::Relaxed);
        *self.core_started_at.lock().await = Some(chrono::Utc::now().timestamp());
        *self.process.lock().await = Some(child);
        for _ in 0..30 {
            if tokio::net::TcpStream::connect(("127.0.0.1", settings.local_port))
                .await
                .is_ok()
            {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(100)).await;
        }
        let health = tokio::process::Command::new("curl")
            .args(["-fsS", "--noproxy", "", "--max-time", "8", "--proxy"])
            .arg(format!("http://127.0.0.1:{}", settings.local_port))
            .arg("https://www.gstatic.com/generate_204")
            .output()
            .await
            .map_err(|e| e.to_string())?;
        if !health.status.success() {
            let detail = String::from_utf8_lossy(&health.stderr)
                .trim()
                .chars()
                .take(240)
                .collect::<String>();
            let _ = self.disconnect_profile().await;
            let message = if detail.is_empty() {
                "proxy health check failed; connection was not activated".to_string()
            } else {
                format!("proxy health check failed: {detail}")
            };
            self.log(message.clone()).await;
            return Err(message);
        }
        if settings.connection_mode == rayarchy_core::protocol::ConnectionMode::SystemProxy {
            match sysproxy::apply("127.0.0.1", settings.local_port) {
                Ok(backup) => *self.proxy_backup.lock().await = Some(backup),
                Err(error) => {
                    let _ = self.disconnect_profile().await;
                    return Err(error);
                }
            }
        }
        *self.connected.lock().await = Some(id);
        self.spawn_statistics_poller();
        let daemon = Arc::clone(self);
        tokio::spawn(async move {
            let mut child = match daemon.process.lock().await.take() {
                Some(child) => child,
                None => return,
            };
            let mut stderr = child.stderr.take();
            let _ = child.wait().await;
            if let Some(mut stream) = stderr.take() {
                let mut bytes = Vec::new();
                if stream.read_to_end(&mut bytes).await.is_ok() {
                    let text = String::from_utf8_lossy(&bytes).trim().to_string();
                    if !text.is_empty() {
                        daemon.log(format!("core exited: {text}")).await;
                    }
                }
            }
            daemon.child_pid.store(0, Ordering::Relaxed);
            *daemon.core_started_at.lock().await = None;
            let crashed_profile = daemon.connected.lock().await.take();
            let _ = std::fs::remove_file(&daemon.config_path);
            // Reconnect supervision is deliberately kept outside this child
            // monitor; a crashed core is never reported as connected again.
            let _ = crashed_profile;
        });
        Ok(())
    }

    async fn disconnect_profile(&self) -> Result<(), String> {
        *self.connected.lock().await = None;
        *self.core_started_at.lock().await = None;
        let pid = self.child_pid.swap(0, Ordering::Relaxed);
        if pid != 0 {
            let _ = std::process::Command::new("kill")
                .arg(pid.to_string())
                .status();
        }
        if let Some(backup) = self.proxy_backup.lock().await.take() {
            let _ = sysproxy::restore(&backup);
        }
        if let Some(mut child) = self.process.lock().await.take() {
            let _ = child.kill().await;
        }
        let _ = std::fs::remove_file(&self.config_path);
        Ok(())
    }
    pub async fn dispatch(
        self: &Arc<Self>,
        method: &str,
        params: serde_json::Value,
    ) -> serde_json::Value {
        match method {
            "system.ping" => serde_json::json!({"ok":true}),
            "system.status" => {
                let profile_id = *self.connected.lock().await;
                let (profile_name, core, local_port, last_health) = {
                    let db = self.db.lock().await;
                    let name = profile_id.and_then(|id| {
                        db.profiles
                            .iter()
                            .find(|profile| profile.id == id)
                            .map(|profile| profile.name.clone())
                    });
                    let selected_core = profile_id.and_then(|id| {
                        db.profiles
                            .iter()
                            .find(|profile| profile.id == id)
                            .map(|profile| {
                                configgen::choose_core(profile, db.settings.preferred_core)
                            })
                    });
                    let health = profile_id.and_then(|id| {
                        let id = id.to_string();
                        db.test_history
                            .iter()
                            .rev()
                            .find(|row| {
                                row.get("profileId").and_then(|v| v.as_str()) == Some(id.as_str())
                                    && matches!(
                                        row.get("kind").and_then(|v| v.as_str()),
                                        Some("proxy") | Some("bulk-proxy")
                                    )
                            })
                            .cloned()
                    });
                    (name, selected_core, db.settings.local_port, health)
                };
                let last_ip = self.last_ip.lock().await.clone();
                let connecting =
                    profile_id.is_none() && self.child_pid.load(Ordering::Relaxed) != 0;
                let stats = match profile_id {
                    Some(id) => self.profile_stats(id).await,
                    None => {
                        serde_json::json!({"todayUp":0,"todayDown":0,"totalUp":0,"totalDown":0})
                    }
                };
                let mut status = serde_json::json!({"connected": profile_id.is_some(), "connecting": connecting, "profileId": profile_id, "profileName": profile_name, "core": core, "localPort": local_port, "lastHealth": last_health, "lastIp": last_ip, "cores": {"xray": self.core_available("xray"), "singBox": self.core_available("sing-box")}});
                for (key, value) in stats.as_object().unwrap_or(&serde_json::Map::new()) {
                    status[key] = value.clone();
                }
                status
            }
            "system.capabilities" => {
                let settings = self.db.lock().await.settings.clone();
                serde_json::json!({"xray":self.core_available("xray"),"singBox":self.core_available("sing-box"),"systemProxy":true,"dnsProtection":settings.dns_leak_protection,"lanBypass":settings.lan_bypass,"tun":false,"transparent":false,"killSwitch":false})
            }
            "system.diagnostics" => {
                let started = *self.core_started_at.lock().await;
                let status = serde_json::json!({"connected": self.connected.lock().await.is_some(), "socket": true, "corePid": self.child_pid.load(Ordering::Relaxed), "coreUptimeSeconds": started.map(|at| (chrono::Utc::now().timestamp() - at).max(0))});
                let xray = command_version("xray", &self.bin_dir).await;
                let sing_box = command_version("sing-box", &self.bin_dir).await;
                serde_json::json!({"status":status,"cores":{"xray":xray,"singBox":sing_box},"hints": if xray.is_none() && sing_box.is_none() { vec!["install xray or sing-box"] } else { Vec::<&str>::new() }})
            }
            "core.validate" => {
                let id = params["profileId"]
                    .as_str()
                    .and_then(|s| uuid::Uuid::parse_str(s).ok());
                let (profile, settings) = {
                    let db = self.db.lock().await;
                    (
                        db.profiles.iter().find(|p| Some(p.id) == id).cloned(),
                        db.settings.clone(),
                    )
                };
                let Some(profile) = profile else {
                    return serde_json::json!({"error":"profile not found"});
                };
                let core = configgen::choose_core(&profile, settings.preferred_core);
                let mut config = configgen::build(&profile, core, "127.0.0.1", settings.local_port);
                let rules = self.db.lock().await.routing.clone();
                configgen::apply_rules(&mut config, core, &rules);
                configgen::apply_dns(&mut config, core, settings.dns_leak_protection);
                configgen::apply_lan_bypass(&mut config, core, settings.lan_bypass);
                configgen::apply_stats(&mut config, core, settings.local_port);
                let path = std::env::temp_dir()
                    .join(format!("rayarchy-validate-{}.json", uuid::Uuid::new_v4()));
                if let Err(error) =
                    std::fs::write(&path, serde_json::to_vec(&config).unwrap_or_default())
                {
                    return serde_json::json!({"error":error.to_string()});
                }
                let result = validate_core_config(core, &path, &self.bin_dir).await;
                let _ = std::fs::remove_file(&path);
                match result {
                    Ok(()) => serde_json::json!({"ok":true,"core":core}),
                    Err(error) => serde_json::json!({"error":error}),
                }
            }
            "system.logs" => {
                let limit = params["limit"].as_u64().unwrap_or(200).min(500) as usize;
                let logs = self.logs.lock().await;
                serde_json::json!({"lines":logs.iter().rev().take(limit).cloned().collect::<Vec<_>>().into_iter().rev().collect::<Vec<_>>()})
            }
            "backup.export" => {
                let db = self.db.lock().await;
                serde_json::json!({"version":1,"state":serde_json::to_value(&*db).unwrap_or_default()})
            }
            "backup.import" => {
                let Some(state) = params.get("state") else {
                    return serde_json::json!({"error":"missing backup state"});
                };
                let parsed: Database = match serde_json::from_value(state.clone()) {
                    Ok(v) => v,
                    Err(e) => return serde_json::json!({"error":format!("invalid backup: {e}")}),
                };
                if self.connected.lock().await.is_some() {
                    return serde_json::json!({"error":"disconnect before restoring a backup"});
                };
                *self.db.lock().await = parsed;
                let _ = self.save().await;
                serde_json::json!({"ok":true})
            }
            "test.history" => {
                let profile_id = params["profileId"].as_str().map(str::to_owned);
                let kind = params["kind"].as_str().map(str::to_owned);
                let db = self.db.lock().await;
                let rows = db
                    .test_history
                    .iter()
                    .filter(|row| {
                        profile_id.as_deref().is_none_or(|id| {
                            row.get("profileId").and_then(|v| v.as_str()) == Some(id)
                        }) && kind.as_deref().is_none_or(|wanted| {
                            row.get("kind").and_then(|v| v.as_str()) == Some(wanted)
                        })
                    })
                    .cloned()
                    .collect::<Vec<_>>();
                serde_json::to_value(rows).unwrap_or_default()
            }
            "test.history.clear" => {
                let id = params["profileId"]
                    .as_str()
                    .and_then(|s| uuid::Uuid::parse_str(s).ok());
                let mut db = self.db.lock().await;
                let id_text = id.map(|profile_id| profile_id.to_string());
                db.test_history.retain(|row| match id_text.as_deref() {
                    Some(profile_id) => {
                        row.get("profileId").and_then(|v| v.as_str()) != Some(profile_id)
                    }
                    None => false,
                });
                drop(db);
                let _ = self.save().await;
                serde_json::json!({"ok":true})
            }
            "test.tcp" => {
                let host = params["host"].as_str().unwrap_or("www.google.com");
                let port = params["port"].as_u64().unwrap_or(443) as u16;
                let start = std::time::Instant::now();
                let result = tokio::net::TcpStream::connect((host, port)).await;
                let row = serde_json::json!({"kind":"tcp","host":host,"port":port,"ok":result.is_ok(),"latencyMs":start.elapsed().as_millis()});
                self.record_test(row.clone()).await;
                row
            }
            "test.bulk" => {
                self.bulk_cancel.store(false, Ordering::Relaxed);
                let ids = params["profileIds"].as_array().cloned().unwrap_or_default();
                let profiles = self.db.lock().await.profiles.clone();
                let mut results = Vec::new();
                for value in ids.into_iter().take(100) {
                    if self.bulk_cancel.load(Ordering::Relaxed) {
                        break;
                    }
                    let id = value.as_str().and_then(|s| uuid::Uuid::parse_str(s).ok());
                    let Some(profile) = profiles.iter().find(|p| Some(p.id) == id) else {
                        continue;
                    };
                    let host = profile.server.clone().unwrap_or_default();
                    let port = profile.port.unwrap_or(443);
                    let start = std::time::Instant::now();
                    let ok = tokio::time::timeout(
                        std::time::Duration::from_secs(5),
                        tokio::net::TcpStream::connect((host.as_str(), port)),
                    )
                    .await
                    .map(|r| r.is_ok())
                    .unwrap_or(false);
                    let row = serde_json::json!({"kind":"bulk-tcp","profileId":profile.id,"name":profile.name,"host":host,"port":port,"ok":ok,"latencyMs":start.elapsed().as_millis()});
                    self.record_test(row.clone()).await;
                    results.push(row);
                }
                serde_json::json!({"results":results,"cancelled":self.bulk_cancel.load(Ordering::Relaxed)})
            }
            "test.bulk.proxy" => {
                if self.connected.lock().await.is_some() {
                    return serde_json::json!({"error":"disconnect before running bulk proxy tests"});
                }
                self.bulk_cancel.store(false, Ordering::Relaxed);
                let ids = params["profileIds"].as_array().cloned().unwrap_or_default();
                let profiles = self.db.lock().await.profiles.clone();
                let mut results = Vec::new();
                for value in ids.into_iter().take(20) {
                    if self.bulk_cancel.load(Ordering::Relaxed) {
                        break;
                    }
                    let id = value.as_str().and_then(|s| uuid::Uuid::parse_str(s).ok());
                    let Some(profile) = profiles.iter().find(|p| Some(p.id) == id && p.enabled)
                    else {
                        continue;
                    };
                    let start = std::time::Instant::now();
                    let outcome = self.connect_profile(profile.id).await;
                    let ok = outcome.is_ok();
                    let error = outcome.err();
                    let _ = self.disconnect_profile().await;
                    let row = serde_json::json!({"kind":"bulk-proxy","profileId":profile.id,"name":profile.name,"ok":ok,"latencyMs":start.elapsed().as_millis(),"error":error});
                    self.record_test(row.clone()).await;
                    results.push(row);
                }
                serde_json::json!({"results":results,"cancelled":self.bulk_cancel.load(Ordering::Relaxed)})
            }
            "test.speed.profile" => {
                if self.connected.lock().await.is_some() {
                    return serde_json::json!({"error":"disconnect before running a profile speed test"});
                }
                let id = params["profileId"]
                    .as_str()
                    .and_then(|s| uuid::Uuid::parse_str(s).ok());
                let Some(id) = id else {
                    return serde_json::json!({"error":"profileId is required"});
                };
                let profile_name = self
                    .db
                    .lock()
                    .await
                    .profiles
                    .iter()
                    .find(|p| p.id == id)
                    .map(|p| p.name.clone());
                let Some(name) = profile_name else {
                    return serde_json::json!({"error":"profile not found"});
                };
                if let Err(error) = self.connect_profile(id).await {
                    return serde_json::json!({"error":error});
                }
                let port = self.db.lock().await.settings.local_port;
                let start = std::time::Instant::now();
                let result = tokio::process::Command::new("curl")
                    .args([
                        "-fsS",
                        "-o",
                        "/dev/null",
                        "--noproxy",
                        "",
                        "--max-time",
                        "20",
                        "--proxy",
                    ])
                    .arg(format!("http://127.0.0.1:{port}"))
                    .arg("https://speed.cloudflare.com/__down?bytes=25000000")
                    .status()
                    .await;
                let _ = self.disconnect_profile().await;
                let seconds = start.elapsed().as_secs_f64();
                let ok = result.map(|s| s.success()).unwrap_or(false);
                let mbps = if ok && seconds > 0.0 {
                    200.0 / seconds
                } else {
                    0.0
                };
                let row = serde_json::json!({"kind":"speed","profileId":id,"name":name,"ok":ok,"megabitsPerSecond":mbps,"durationMs":start.elapsed().as_millis()});
                self.record_test(row.clone()).await;
                row
            }
            "test.bulk.cancel" => {
                self.bulk_cancel.store(true, Ordering::Relaxed);
                serde_json::json!({"ok":true})
            }
            "test.udp" => {
                if self.connected.lock().await.is_some() {
                    return serde_json::json!({"error":"disconnect before running a UDP test"});
                }
                let id = params["profileId"]
                    .as_str()
                    .and_then(|s| uuid::Uuid::parse_str(s).ok());
                let Some(id) = id else {
                    return serde_json::json!({"error":"profileId is required"});
                };
                let profile_name = self
                    .db
                    .lock()
                    .await
                    .profiles
                    .iter()
                    .find(|p| p.id == id)
                    .map(|p| p.name.clone());
                let Some(name) = profile_name else {
                    return serde_json::json!({"error":"profile not found"});
                };
                if let Err(error) = self.connect_profile(id).await {
                    return serde_json::json!({"error":error});
                }
                let port = self.db.lock().await.settings.local_port;
                let result = udp::probe_dns("127.0.0.1", port).await;
                let _ = self.disconnect_profile().await;
                match result {
                    Ok(latency_ms) => {
                        let row = serde_json::json!({"kind":"udp","profileId":id,"name":name,"ok":true,"latencyMs":latency_ms});
                        self.record_test(row.clone()).await;
                        row
                    }
                    Err(error) => {
                        let row = serde_json::json!({"kind":"udp","profileId":id,"name":name,"ok":false,"error":error});
                        self.record_test(row.clone()).await;
                        row
                    }
                }
            }
            "clash.proxies" => {
                let port = self.db.lock().await.settings.local_port.saturating_add(5);
                let output = tokio::process::Command::new("curl")
                    .args(["-fsS", "--noproxy", "*", "--max-time", "3"])
                    .arg(format!("http://127.0.0.1:{port}/proxies"))
                    .output()
                    .await;
                match output {
                    Ok(o) if o.status.success() => {
                        match serde_json::from_slice::<serde_json::Value>(&o.stdout) {
                            Ok(value) => value,
                            Err(_) => serde_json::json!({"error":"invalid clash api response"}),
                        }
                    }
                    Ok(_) => serde_json::json!({"error":"clash api is not reachable"}),
                    Err(_) => serde_json::json!({"error":"clash api is not reachable"}),
                }
            }
            "clash.connections" => {
                let port = self.db.lock().await.settings.local_port.saturating_add(5);
                let output = tokio::process::Command::new("curl")
                    .args(["-fsS", "--noproxy", "*", "--max-time", "3"])
                    .arg(format!("http://127.0.0.1:{port}/connections"))
                    .output()
                    .await;
                match output {
                    Ok(o) if o.status.success() => {
                        match serde_json::from_slice::<serde_json::Value>(&o.stdout) {
                            Ok(value) => value,
                            Err(_) => serde_json::json!({"error":"invalid clash api response"}),
                        }
                    }
                    _ => serde_json::json!({"error":"clash api is not reachable"}),
                }
            }
            "clash.closeConnection" => {
                let id = params["id"].as_str().unwrap_or("");
                let port = self.db.lock().await.settings.local_port.saturating_add(5);
                let output = tokio::process::Command::new("curl")
                    .args(["-fsS", "-X", "DELETE", "--noproxy", "*", "--max-time", "3"])
                    .arg(format!("http://127.0.0.1:{port}/connections/{id}"))
                    .output()
                    .await;
                serde_json::json!({"ok": output.map(|o| o.status.success()).unwrap_or(false)})
            }
            "clash.closeAll" => {
                let port = self.db.lock().await.settings.local_port.saturating_add(5);
                let output = tokio::process::Command::new("curl")
                    .args(["-fsS", "-X", "DELETE", "--noproxy", "*", "--max-time", "3"])
                    .arg(format!("http://127.0.0.1:{port}/connections"))
                    .output()
                    .await;
                serde_json::json!({"ok": output.map(|o| o.status.success()).unwrap_or(false)})
            }
            "clash.setMode" => {
                let mode = params["mode"].as_str().unwrap_or("rule");
                let port = self.db.lock().await.settings.local_port.saturating_add(5);
                let output = tokio::process::Command::new("curl")
                    .args(["-fsS", "-X", "PATCH", "--noproxy", "*", "--max-time", "3"])
                    .arg(format!("http://127.0.0.1:{port}/configs"))
                    .arg("-d")
                    .arg(format!(r#"{{"mode":"{mode}"}}"#))
                    .output()
                    .await;
                serde_json::json!({"ok": output.map(|o| o.status.success()).unwrap_or(false)})
            }
            "clash.select" => {
                let group = params["group"].as_str().unwrap_or("");
                let proxy = params["proxy"].as_str().unwrap_or("");
                let port = self.db.lock().await.settings.local_port.saturating_add(5);
                let output = tokio::process::Command::new("curl")
                    .args(["-fsS", "-X", "PUT", "--noproxy", "*", "--max-time", "3"])
                    .arg(format!("http://127.0.0.1:{port}/proxies/{group}"))
                    .arg("-d")
                    .arg(format!(r#"{{"name":"{proxy}"}}"#))
                    .output()
                    .await;
                serde_json::json!({"ok": output.map(|o| o.status.success()).unwrap_or(false)})
            }
            "stats.current" => {
                let core = self.db.lock().await.settings.preferred_core;
                let port = self.db.lock().await.settings.local_port.saturating_add(5);
                let core = if core == rayarchy_core::protocol::Core::Auto {
                    let profile_id = *self.connected.lock().await;
                    let db = self.db.lock().await;
                    profile_id
                        .and_then(|id| db.profiles.iter().find(|p| p.id == id))
                        .map(|p| configgen::choose_core(p, db.settings.preferred_core))
                        .unwrap_or(rayarchy_core::protocol::Core::Xray)
                } else {
                    core
                };
                let path = if core == rayarchy_core::protocol::Core::SingBox {
                    "/traffic"
                } else {
                    "/debug/vars"
                };
                let output = tokio::process::Command::new("curl")
                    .args(["-fsS", "--noproxy", "*", "--max-time", "3"])
                    .arg(format!("http://127.0.0.1:{port}{path}"))
                    .output()
                    .await;
                match output {
                    Ok(o) if o.status.success() => parse_traffic(core, &o.stdout)
                        .unwrap_or_else(|| serde_json::json!({"up":0,"down":0})),
                    _ => serde_json::json!({"up":0,"down":0}),
                }
            }
            "test.proxy" => {
                let port = self.db.lock().await.settings.local_port;
                let start = std::time::Instant::now();
                let result = tokio::process::Command::new("curl")
                    .args([
                        "-fsS",
                        "-o",
                        "/dev/null",
                        "--noproxy",
                        "",
                        "--max-time",
                        "8",
                        "--proxy",
                    ])
                    .arg(format!("http://127.0.0.1:{port}"))
                    .arg("https://www.gstatic.com/generate_204")
                    .status()
                    .await;
                let row = serde_json::json!({"kind":"proxy","ok":result.map(|s|s.success()).unwrap_or(false),"latencyMs":start.elapsed().as_millis()});
                self.record_test(row.clone()).await;
                row
            }
            "test.ip" => {
                let port = self.db.lock().await.settings.local_port;
                let target = "https://api.ipify.org";
                let proxy = tokio::process::Command::new("curl")
                    .args(["-fsS", "--noproxy", "", "--max-time", "8", "--proxy"])
                    .arg(format!("http://127.0.0.1:{port}"))
                    .arg(target)
                    .output()
                    .await;
                let direct = tokio::process::Command::new("curl")
                    .args(["-fsS", "--noproxy", "*", "--max-time", "8", target])
                    .output()
                    .await;
                let proxy_ip = proxy
                    .ok()
                    .filter(|o| o.status.success())
                    .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
                    .filter(|s| !s.is_empty());
                let direct_ip = direct
                    .ok()
                    .filter(|o| o.status.success())
                    .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
                    .filter(|s| !s.is_empty());
                let row = serde_json::json!({"proxyIp":proxy_ip,"directIp":direct_ip,"protected":proxy_ip.is_some() && proxy_ip != direct_ip});
                *self.last_ip.lock().await = Some(row.clone());
                row
            }
            "test.speed" => {
                let port = self.db.lock().await.settings.local_port;
                let start = std::time::Instant::now();
                let result = tokio::process::Command::new("curl")
                    .args([
                        "-fsS",
                        "-o",
                        "/dev/null",
                        "--noproxy",
                        "",
                        "--max-time",
                        "20",
                        "--proxy",
                    ])
                    .arg(format!("http://127.0.0.1:{port}"))
                    .arg("https://speed.cloudflare.com/__down?bytes=25000000")
                    .status()
                    .await;
                let seconds = start.elapsed().as_secs_f64();
                let ok = result.map(|s| s.success()).unwrap_or(false);
                let mbps = if ok && seconds > 0.0 {
                    200.0 / seconds
                } else {
                    0.0
                };
                let row = serde_json::json!({"kind":"speed","ok":ok,"megabitsPerSecond":mbps,"durationMs":start.elapsed().as_millis()});
                self.record_test(row.clone()).await;
                row
            }
            "routing.list" => {
                serde_json::to_value(&self.db.lock().await.routing).unwrap_or_default()
            }
            "routing.create" => {
                let rule: RoutingRule = match serde_json::from_value(params["rule"].clone()) {
                    Ok(v) => v,
                    Err(e) => return serde_json::json!({"error":e.to_string()}),
                };
                if let Err(error) = validate_rule(&rule) {
                    return serde_json::json!({"error":error});
                }
                let id = rule.id;
                self.db.lock().await.routing.push(rule);
                let _ = self.save().await;
                serde_json::json!({"ruleId":id})
            }
            "routing.delete" => {
                let id = params["ruleId"]
                    .as_str()
                    .and_then(|s| uuid::Uuid::parse_str(s).ok());
                self.db.lock().await.routing.retain(|r| Some(r.id) != id);
                let _ = self.save().await;
                serde_json::json!({"ok":true})
            }
            "profile.list" => {
                let query = params["query"].as_str().unwrap_or("").trim().to_lowercase();
                let group = params["group"].as_str().unwrap_or("");
                let favorites_only = params["favoritesOnly"].as_bool().unwrap_or(false);
                let enabled_only = params["enabledOnly"].as_bool().unwrap_or(false);
                let sort = params["sort"].as_str().unwrap_or("manual");
                let db = self.db.lock().await;
                let history = db.test_history.clone();
                let default_id = db.settings.default_profile_id;
                let retention = i64::from(db.settings.health_retention_hours.max(1)) * 60 * 60;
                let mut profiles: Vec<_> = db
                    .profiles
                    .iter()
                    .filter(|profile| {
                        (query.is_empty()
                            || profile.name.to_lowercase().contains(&query)
                            || profile
                                .server
                                .as_deref()
                                .unwrap_or("")
                                .to_lowercase()
                                .contains(&query))
                            && (group.is_empty() || profile.group == group)
                            && (!favorites_only || profile.favorite)
                            && (!enabled_only || profile.enabled)
                    })
                    .cloned()
                    .collect();
                drop(db);
                match sort {
                    "name" => profiles.sort_by_key(|profile| profile.name.to_lowercase()),
                    "server" => profiles.sort_by_key(|profile| {
                        profile.server.as_deref().unwrap_or("").to_lowercase()
                    }),
                    "favorites" => profiles.sort_by_key(|profile| !profile.favorite),
                    _ => {}
                }
                let mut output = Vec::with_capacity(profiles.len());
                for profile in profiles {
                    let profile_id = profile.id;
                    let mut value = serde_json::to_value(profile).unwrap_or_default();
                    value["default"] = serde_json::Value::Bool(
                        value["id"]
                            .as_str()
                            .and_then(|s| uuid::Uuid::parse_str(s).ok())
                            == default_id,
                    );
                    let stats = self.profile_stats(profile_id).await;
                    for (key, stat_value) in stats.as_object().unwrap_or(&serde_json::Map::new()) {
                        value[key] = stat_value.clone();
                    }
                    if let Some(test) = history.iter().rev().find(|row| {
                        let fresh = row
                            .get("timestamp")
                            .and_then(|v| v.as_i64())
                            .map(|ts| {
                                chrono::Utc::now().timestamp().saturating_sub(ts) <= retention
                            })
                            .unwrap_or(true);
                        fresh
                            && row.get("profileId").and_then(|id| id.as_str())
                                == value.get("id").and_then(|id| id.as_str())
                    }) {
                        value["lastTest"] = test.clone();
                    }
                    output.push(value);
                }
                serde_json::Value::Array(output)
            }
            "profile.get" => {
                let id = params["profileId"]
                    .as_str()
                    .and_then(|s| uuid::Uuid::parse_str(s).ok());
                self.db
                    .lock()
                    .await
                    .profiles
                    .iter()
                    .find(|p| Some(p.id) == id)
                    .map(|p| serde_json::to_value(p).unwrap_or_default())
                    .unwrap_or_else(|| serde_json::json!({"error":"profile not found"}))
            }
            "profile.schema" => {
                let protocol = params["protocol"].as_str().unwrap_or("vless");
                let fields: &[&str] = match protocol {
                    "vless" => &["user", "security", "sni", "type", "host", "path"],
                    "vmess" => &["user", "aid", "security", "tls", "type", "host", "path"],
                    "trojan" => &["password", "security", "sni", "type", "host", "path"],
                    "shadowsocks" => &["method", "password"],
                    "hysteria2" => &["password", "sni", "obfs", "obfs-password"],
                    "tuic" => &["user", "password", "congestion_control", "sni"],
                    "wireguard" => &["private_key", "public_key", "local_address", "mtu"],
                    "anytls" => &["user", "password", "sni", "idle_session_check_interval"],
                    "naive" => &["user", "password"],
                    "policy-group" => &["members", "strategy"],
                    "proxy-chain" => &["members"],
                    "custom" => &["raw"],
                    "outbound" => &["raw"],
                    "socks" | "http" => &["user", "password"],
                    _ => &[],
                };
                serde_json::json!({"protocol":protocol,"fields":fields})
            }
            "profile.export" => {
                let id = params["profileId"]
                    .as_str()
                    .and_then(|s| uuid::Uuid::parse_str(s).ok());
                self.db.lock().await.profiles.iter().find(|p| Some(p.id) == id)
                    .map(|p| serde_json::json!({"profileId":p.id,"name":p.name,"payload":p.raw.clone().unwrap_or_else(|| serde_json::to_string(p).unwrap_or_default())}))
                    .unwrap_or_else(|| serde_json::json!({"error":"profile not found"}))
            }
            "profile.qr" => {
                let id = params["profileId"]
                    .as_str()
                    .and_then(|s| uuid::Uuid::parse_str(s).ok());
                self.db.lock().await.profiles.iter().find(|p| Some(p.id) == id)
                    .map(|p| serde_json::json!({"payload":p.raw.clone().unwrap_or_else(|| serde_json::to_string(p).unwrap_or_default()),"format":"text"}))
                    .unwrap_or_else(|| serde_json::json!({"error":"profile not found"}))
            }
            "profile.inner" => {
                let id = params["profileId"]
                    .as_str()
                    .and_then(|s| uuid::Uuid::parse_str(s).ok());
                self.db
                    .lock()
                    .await
                    .profiles
                    .iter()
                    .find(|p| Some(p.id) == id)
                    .map(|p| serde_json::json!({"innerUri":rayarchy_core::import::to_inner_uri(p)}))
                    .unwrap_or_else(|| serde_json::json!({"error":"profile not found"}))
            }
            "profile.qr.image" => {
                let id = params["profileId"]
                    .as_str()
                    .and_then(|s| uuid::Uuid::parse_str(s).ok());
                let payload = self
                    .db
                    .lock()
                    .await
                    .profiles
                    .iter()
                    .find(|p| Some(p.id) == id)
                    .map(|p| {
                        p.raw
                            .clone()
                            .unwrap_or_else(|| serde_json::to_string(p).unwrap_or_default())
                    });
                let Some(payload) = payload else {
                    return serde_json::json!({"error":"profile not found"});
                };
                let path =
                    std::env::temp_dir().join(format!("rayarchy-qr-{}.png", uuid::Uuid::new_v4()));
                let output = tokio::process::Command::new("qrencode")
                    .args(["-o"])
                    .arg(&path)
                    .arg(&payload)
                    .output()
                    .await;
                match output {
                    Ok(result) if result.status.success() => {
                        #[cfg(unix)]
                        {
                            use std::os::unix::fs::PermissionsExt;
                            let _ = std::fs::set_permissions(
                                &path,
                                std::fs::Permissions::from_mode(0o600),
                            );
                        }
                        serde_json::json!({"imagePath":path,"format":"png"})
                    }
                    Ok(_) => {
                        let _ = std::fs::remove_file(&path);
                        serde_json::json!({"error":"qrencode could not generate an image"})
                    }
                    Err(_) => {
                        serde_json::json!({"error":"qrencode is not installed; install it to generate QR images"})
                    }
                }
            }
            "import.preview" => {
                let input = params["input"].as_str().unwrap_or("");
                match rayarchy_core::import::parse_input(input) {
                    Ok(profiles) => serde_json::json!({"profiles":profiles,"errors":[]}),
                    Err(error) => serde_json::json!({"profiles":[],"errors":[error]}),
                }
            }
            "import.clipboard" => {
                let output = tokio::process::Command::new("wl-paste")
                    .args(["--no-newline", "--type", "text"])
                    .output()
                    .await;
                match output {
                    Ok(output) if output.status.success() => {
                        let input = String::from_utf8_lossy(&output.stdout);
                        match rayarchy_core::import::parse_input(&input) {
                            Ok(profiles) => serde_json::json!({"input":input,"profiles":profiles}),
                            Err(error) => serde_json::json!({"error":error}),
                        }
                    }
                    Ok(_) => serde_json::json!({"error":"clipboard does not contain text"}),
                    Err(_) => serde_json::json!({"error":"wl-paste is not installed"}),
                }
            }
            "import.qr.image" => {
                let Some(path) = params["path"].as_str().map(std::path::PathBuf::from) else {
                    return serde_json::json!({"error":"image path is required"});
                };
                let Ok(metadata) = std::fs::metadata(&path) else {
                    return serde_json::json!({"error":"image was not found"});
                };
                if !metadata.is_file() || metadata.len() > 20 * 1024 * 1024 {
                    return serde_json::json!({"error":"QR image must be a regular file no larger than 20 MiB"});
                }
                let output = tokio::process::Command::new("zbarimg")
                    .args(["--quiet", "--raw"])
                    .arg(&path)
                    .output()
                    .await;
                match output {
                    Ok(output) if output.status.success() => {
                        let input = String::from_utf8_lossy(&output.stdout).trim().to_string();
                        match rayarchy_core::import::parse_input(&input) {
                            Ok(profiles) => serde_json::json!({"input":input,"profiles":profiles}),
                            Err(error) => serde_json::json!({"error":error}),
                        }
                    }
                    Ok(_) => {
                        serde_json::json!({"error":"no supported QR payload was found in the image"})
                    }
                    Err(_) => serde_json::json!({"error":"zbarimg is not installed"}),
                }
            }
            "import.commit" => {
                let input = params["input"].as_str().unwrap_or("");
                match rayarchy_core::import::parse_input(input) {
                    Ok(profiles) => {
                        let ids: Vec<_> = profiles.iter().map(|p| p.id).collect();
                        let mut db = self.db.lock().await;
                        for profile in profiles {
                            if !db
                                .profiles
                                .iter()
                                .any(|existing| profiles_equivalent(existing, &profile))
                            {
                                db.profiles.push(profile);
                            }
                        }
                        drop(db);
                        let _ = self.save().await;
                        serde_json::json!({"profileIds":ids})
                    }
                    Err(error) => serde_json::json!({"error":error}),
                }
            }
            "profile.create" => {
                let mut p: Profile = match serde_json::from_value(params["profile"].clone()) {
                    Ok(v) => v,
                    Err(e) => return serde_json::json!({"error":e.to_string()}),
                };
                if p.name.trim().is_empty() {
                    p.name = format!("{:?} profile", p.protocol);
                }
                if let Err(error) = validate_profile(&p) {
                    return serde_json::json!({"error":error});
                }
                if let Err(error) = validate_profile_members(&p, &self.db.lock().await.profiles) {
                    return serde_json::json!({"error":error});
                }
                let id = p.id;
                if self
                    .db
                    .lock()
                    .await
                    .profiles
                    .iter()
                    .any(|existing| profiles_equivalent(existing, &p))
                {
                    return serde_json::json!({"error":"duplicate profile"});
                }
                self.db.lock().await.profiles.push(p);
                let _ = self.save().await;
                serde_json::json!({"profileId":id})
            }
            "profile.delete" => {
                let id = params["profileId"]
                    .as_str()
                    .and_then(|s| uuid::Uuid::parse_str(s).ok());
                if id.is_some() && *self.connected.lock().await == id {
                    return serde_json::json!({"error":"disconnect the active profile before deleting it"});
                }
                let mut db = self.db.lock().await;
                if let Some(id) = id {
                    if let Some(container) = db
                        .profiles
                        .iter()
                        .find(|profile| profile.members.contains(&id))
                    {
                        return serde_json::json!({"error":format!("profile is used by {}", container.name)});
                    }
                }
                db.profiles.retain(|p| Some(p.id) != id);
                drop(db);
                let _ = self.save().await;
                serde_json::json!({"ok":true})
            }
            "profile.update" => {
                let p: Profile = match serde_json::from_value(params["profile"].clone()) {
                    Ok(v) => v,
                    Err(e) => return serde_json::json!({"error":e.to_string()}),
                };
                if let Err(error) = validate_profile(&p) {
                    return serde_json::json!({"error":error});
                }
                let mut db = self.db.lock().await;
                if let Err(error) = validate_profile_members(&p, &db.profiles) {
                    return serde_json::json!({"error":error});
                }
                if let Some(existing) = db.profiles.iter_mut().find(|x| x.id == p.id) {
                    *existing = p;
                } else {
                    return serde_json::json!({"error":"profile not found"});
                }
                drop(db);
                let _ = self.save().await;
                serde_json::json!({"ok":true})
            }
            "profile.raw.update" => {
                let id = params["profileId"]
                    .as_str()
                    .and_then(|s| uuid::Uuid::parse_str(s).ok());
                let raw = params["raw"].as_str().map(str::to_string);
                let Some(raw) = raw else {
                    return serde_json::json!({"error":"raw payload is required"});
                };
                let trimmed = raw.trim();
                let valid = if trimmed.starts_with('{') || trimmed.starts_with('[') {
                    serde_json::from_str::<serde_json::Value>(trimmed).is_ok()
                } else {
                    rayarchy_core::import::parse_input(trimmed).is_ok()
                };
                if !valid {
                    return serde_json::json!({"error":"raw payload is not valid JSON or a supported profile format"});
                }
                let mut db = self.db.lock().await;
                let Some(profile) = db.profiles.iter_mut().find(|p| Some(p.id) == id) else {
                    return serde_json::json!({"error":"profile not found"});
                };
                profile.raw = (!raw.trim().is_empty()).then_some(raw);
                drop(db);
                let _ = self.save().await;
                serde_json::json!({"ok":true})
            }
            "profile.fields.update" => {
                let id = params["profileId"]
                    .as_str()
                    .and_then(|s| uuid::Uuid::parse_str(s).ok());
                let fields = params
                    .get("fields")
                    .cloned()
                    .unwrap_or_else(|| serde_json::json!({}));
                if !fields.is_object() {
                    return serde_json::json!({"error":"profile fields must be a JSON object"});
                }
                let mut db = self.db.lock().await;
                let Some(profile) = db.profiles.iter_mut().find(|p| Some(p.id) == id) else {
                    return serde_json::json!({"error":"profile not found"});
                };
                profile.fields = fields;
                drop(db);
                let _ = self.save().await;
                serde_json::json!({"ok":true})
            }
            "profile.favorite" => {
                let id = params["profileId"]
                    .as_str()
                    .and_then(|s| uuid::Uuid::parse_str(s).ok());
                let favorite = params["favorite"].as_bool().unwrap_or(true);
                let mut db = self.db.lock().await;
                if let Some(p) = db.profiles.iter_mut().find(|x| Some(x.id) == id) {
                    p.favorite = favorite;
                } else {
                    return serde_json::json!({"error":"profile not found"});
                }
                drop(db);
                let _ = self.save().await;
                serde_json::json!({"ok":true})
            }
            "profile.enable" => {
                let id = params["profileId"]
                    .as_str()
                    .and_then(|s| uuid::Uuid::parse_str(s).ok());
                let enabled = params["enabled"].as_bool().unwrap_or(true);
                let mut db = self.db.lock().await;
                let Some(profile) = db.profiles.iter_mut().find(|p| Some(p.id) == id) else {
                    return serde_json::json!({"error":"profile not found"});
                };
                profile.enabled = enabled;
                drop(db);
                let _ = self.save().await;
                serde_json::json!({"ok":true})
            }
            "profile.reorder" => {
                let ids = params["profileIds"].as_array().cloned().unwrap_or_default();
                let order: Vec<_> = ids
                    .iter()
                    .filter_map(|v| v.as_str().and_then(|s| uuid::Uuid::parse_str(s).ok()))
                    .collect();
                let mut db = self.db.lock().await;
                let mut reordered = Vec::with_capacity(db.profiles.len());
                for id in order {
                    if let Some(pos) = db.profiles.iter().position(|p| p.id == id) {
                        reordered.push(db.profiles.remove(pos));
                    }
                }
                reordered.append(&mut db.profiles);
                db.profiles = reordered;
                drop(db);
                let _ = self.save().await;
                serde_json::json!({"ok":true})
            }
            "profile.duplicate" => {
                let id = params["profileId"]
                    .as_str()
                    .and_then(|s| uuid::Uuid::parse_str(s).ok());
                let mut db = self.db.lock().await;
                let Some(mut copy) = db.profiles.iter().find(|x| Some(x.id) == id).cloned() else {
                    return serde_json::json!({"error":"profile not found"});
                };
                copy.id = uuid::Uuid::new_v4();
                copy.name = format!("{} (copy)", copy.name);
                copy.source_id = None;
                db.profiles.push(copy.clone());
                drop(db);
                let _ = self.save().await;
                serde_json::json!({"profileId":copy.id})
            }
            "profile.duplicates.remove" => {
                if self.connected.lock().await.is_some() {
                    return serde_json::json!({"error":"disconnect before removing duplicate profiles"});
                }
                let mut db = self.db.lock().await;
                let before = db.profiles.len();
                let mut unique: Vec<Profile> = Vec::with_capacity(before);
                for profile in db.profiles.drain(..) {
                    if !unique
                        .iter()
                        .any(|existing| profiles_equivalent(existing, &profile))
                    {
                        unique.push(profile);
                    }
                }
                db.profiles = unique;
                let removed = before - db.profiles.len();
                drop(db);
                let _ = self.save().await;
                serde_json::json!({"removed":removed})
            }
            "profile.setDefault" => {
                let id = params["profileId"]
                    .as_str()
                    .and_then(|s| uuid::Uuid::parse_str(s).ok());
                let mut db = self.db.lock().await;
                if let Some(id) = id {
                    if !db.profiles.iter().any(|p| p.id == id) {
                        return serde_json::json!({"error":"profile not found"});
                    }
                }
                db.settings.default_profile_id = id;
                drop(db);
                let _ = self.save().await;
                serde_json::json!({"ok":true})
            }
            "profile.default" => {
                let db = self.db.lock().await;
                db.profiles
                    .iter()
                    .find(|p| Some(p.id) == db.settings.default_profile_id)
                    .map(|p| serde_json::to_value(p).unwrap_or_default())
                    .unwrap_or(serde_json::Value::Null)
            }
            "profile.connect.cancel" => {
                let _ = self.disconnect_profile().await;
                self.log("connection attempt cancelled by user".to_string())
                    .await;
                serde_json::json!({"ok":true,"state":"DISCONNECTED"})
            }
            "profile.connect" | "profile.switch" => {
                let id = params["profileId"]
                    .as_str()
                    .and_then(|s| uuid::Uuid::parse_str(s).ok());
                if self
                    .db
                    .lock()
                    .await
                    .profiles
                    .iter()
                    .all(|p| Some(p.id) != id)
                {
                    return serde_json::json!({"error":"profile not found"});
                }
                match self.connect_profile(id.unwrap()).await {
                    Ok(()) => {
                        self.log(format!("connected profile {id:?}")).await;
                        serde_json::json!({"accepted":true,"state":"CONNECTED","profileId":id})
                    }
                    Err(error) => {
                        self.log(format!("connection failed: {error}")).await;
                        serde_json::json!({"error":error})
                    }
                }
            }
            "profile.disconnect" => match self.disconnect_profile().await {
                Ok(()) => {
                    self.log("disconnected").await;
                    serde_json::json!({"accepted":true,"state":"DISCONNECTED"})
                }
                Err(error) => serde_json::json!({"error":error}),
            },
            "system.reload" => {
                let active = *self.connected.lock().await;
                if let Some(id) = active {
                    if let Err(error) = self.disconnect_profile().await {
                        return serde_json::json!({"error":error});
                    }
                    match self.connect_profile(id).await {
                        Ok(()) => serde_json::json!({"ok":true,"reloaded":true,"profileId":id}),
                        Err(error) => serde_json::json!({"ok":false,"error":error,"profileId":id}),
                    }
                } else {
                    serde_json::json!({"ok":true,"reloaded":false})
                }
            }
            "ui.get" => {
                let db = self.db.lock().await;
                db.settings.ui.clone()
            }
            "ui.set" => {
                let ui = params
                    .get("ui")
                    .cloned()
                    .unwrap_or_else(|| serde_json::json!({}));
                if !ui.is_object() {
                    return serde_json::json!({"error":"ui state must be a JSON object"});
                }
                self.db.lock().await.settings.ui = ui;
                let _ = self.save().await;
                serde_json::json!({"ok":true})
            }
            "statistics.clear" => {
                let profile_id = params["profileId"]
                    .as_str()
                    .and_then(|s| uuid::Uuid::parse_str(s).ok());
                let mut db = self.db.lock().await;
                match profile_id {
                    Some(id) => {
                        db.statistics.remove(&id.to_string());
                    }
                    None => db.statistics.clear(),
                }
                drop(db);
                let _ = self.save().await;
                serde_json::json!({"ok":true})
            }
            "update.check" => {
                let installed_xray = command_version("xray", &self.bin_dir)
                    .await
                    .unwrap_or_default();
                let installed_sing = command_version("sing-box", &self.bin_dir)
                    .await
                    .unwrap_or_default();
                let installed_geoip = self.bin_dir.join("geoip.dat").is_file();
                let installed_geosite = self.bin_dir.join("geosite.dat").is_file();
                let mut result = serde_json::json!({
                    "installed": {
                        "xray": installed_xray,
                        "sing-box": installed_sing,
                        "geoip.dat": installed_geoip,
                        "geosite.dat": installed_geosite
                    },
                    "latest": {}
                });
                for core in update::CORES {
                    let Some(repo) = update::core_repo(core) else {
                        continue;
                    };
                    let url = update::latest_release_api(repo);
                    if let Ok(output) = tokio::process::Command::new("curl")
                        .args([
                            "-fsSL",
                            "--noproxy",
                            "*",
                            "--max-time",
                            "8",
                            "-H",
                            "Accept: application/vnd.github+json",
                            "-H",
                            "User-Agent: rayarchy",
                        ])
                        .arg(&url)
                        .output()
                        .await
                    {
                        if output.status.success() {
                            if let Some(tag) =
                                update::tag_from_latest(&String::from_utf8_lossy(&output.stdout))
                            {
                                result["latest"][core] = serde_json::json!(tag);
                            }
                        }
                    }
                }
                let geo_url = update::latest_release_api(update::geo_repo());
                if let Ok(output) = tokio::process::Command::new("curl")
                    .args([
                        "-fsSL",
                        "--noproxy",
                        "*",
                        "--max-time",
                        "8",
                        "-H",
                        "Accept: application/vnd.github+json",
                        "-H",
                        "User-Agent: rayarchy",
                    ])
                    .arg(&geo_url)
                    .output()
                    .await
                {
                    if output.status.success() {
                        if let Some(tag) =
                            update::tag_from_latest(&String::from_utf8_lossy(&output.stdout))
                        {
                            result["latest"]["geo"] = serde_json::json!(tag);
                        }
                    }
                }
                result
            }
            "update.install" => {
                let target = params["target"].as_str().unwrap_or("").to_string();
                let tag = params["version"].as_str().unwrap_or("").to_string();
                let bin_dir = self.bin_dir.clone();
                if target == "geoip.dat" || target == "geosite.dat" {
                    let url = format!(
                        "https://github.com/{}/releases/latest/download/{target}",
                        update::geo_repo()
                    );
                    let sha_url = format!(
                        "https://github.com/{}/releases/latest/download/sha256sum",
                        update::geo_repo()
                    );
                    let bytes = match tokio::process::Command::new("curl")
                        .args(["-fsSL", "--noproxy", "*", "--max-time", "60", "-L"])
                        .arg(&url)
                        .output()
                        .await
                    {
                        Ok(o) if o.status.success() => o,
                        _ => {
                            return serde_json::json!({"error":format!("could not download {target}")})
                        }
                    };
                    let expected = tokio::process::Command::new("curl")
                        .args(["-fsSL", "--noproxy", "*", "--max-time", "15"])
                        .arg(&sha_url)
                        .output()
                        .await
                        .ok()
                        .filter(|o| o.status.success())
                        .map(|o| {
                            let entries =
                                update::parse_sha256sums(&String::from_utf8_lossy(&o.stdout));
                            update::checksum_for(&entries, &target).map(str::to_string)
                        })
                        .and_then(|v| v);
                    if let Some(expected) = expected {
                        if !update::verify_sha256(&bytes.stdout, &expected) {
                            return serde_json::json!({"error":format!("sha256 mismatch for {target}")});
                        }
                    }
                    match update::write_bin(&bin_dir, &target, &bytes.stdout) {
                        Ok(_) => return serde_json::json!({"ok":true,"target":target}),
                        Err(e) => return serde_json::json!({"error":e.to_string()}),
                    }
                }
                let Some(repo) = update::core_repo(&target) else {
                    return serde_json::json!({"error":"unsupported update target"});
                };
                let Some(asset) = update::core_asset_name(&target, &tag) else {
                    return serde_json::json!({"error":"unsupported core asset"});
                };
                let download_url =
                    format!("https://github.com/{repo}/releases/download/{tag}/{asset}");
                let archive = match tokio::process::Command::new("curl")
                    .args(["-fsSL", "--noproxy", "*", "--max-time", "180", "-L"])
                    .arg(&download_url)
                    .output()
                    .await
                {
                    Ok(o) if o.status.success() => o,
                    Ok(_) => {
                        return serde_json::json!({"error":format!("could not download {asset}")})
                    }
                    Err(e) => return serde_json::json!({"error":e.to_string()}),
                };
                let binary = update::core_binary_name(&target);
                let extracted = extract_archive(&asset, &archive.stdout);
                let Some(extracted) = extracted else {
                    return serde_json::json!({"error":"could not extract core archive"});
                };
                let Some(path) = extracted.iter().find(|p| p.ends_with(binary.as_bytes())) else {
                    return serde_json::json!({"error":format!("{binary} not found in archive")});
                };
                match update::write_bin(&bin_dir, binary, path) {
                    Ok(_) => serde_json::json!({"ok":true,"target":target,"version":tag}),
                    Err(e) => serde_json::json!({"error":e.to_string()}),
                }
            }
            "settings.get" => {
                serde_json::to_value(&self.db.lock().await.settings).unwrap_or_default()
            }
            "settings.update" => {
                let value = params.get("settings").cloned().unwrap_or_default();
                match serde_json::from_value::<Settings>(value) {
                    Ok(mut s) => {
                        if s.local_port == 0 {
                            return serde_json::json!({"error":"local port must be between 1 and 65535"});
                        }
                        if !(1..=720).contains(&s.health_retention_hours) {
                            return serde_json::json!({"error":"health retention must be between 1 and 720 hours"});
                        }
                        if self.connected.lock().await.is_some() {
                            return serde_json::json!({"error":"disconnect before changing connection settings"});
                        }
                        if s.kill_switch {
                            return serde_json::json!({"error":"kill switch requires the privileged helper and is not enabled in this build"});
                        }
                        {
                            let mut db = self.db.lock().await;
                            // default_profile_id and ui are owned by other RPCs
                            // (profile.setDefault / ui.set); an option-settings
                            // save must not silently clear them.
                            s.default_profile_id = db.settings.default_profile_id;
                            s.ui = db.settings.ui.clone();
                            db.settings = s;
                        }
                        let _ = self.save().await;
                        serde_json::json!({"ok":true})
                    }
                    Err(e) => serde_json::json!({"error":e.to_string()}),
                }
            }
            "subscription.list" => {
                serde_json::to_value(&self.db.lock().await.subscriptions).unwrap_or_default()
            }
            "subscription.create" => {
                let s: Subscription = match serde_json::from_value(params["subscription"].clone()) {
                    Ok(v) => v,
                    Err(e) => return serde_json::json!({"error":e.to_string()}),
                };
                if !valid_subscription_url(&s.url) {
                    return serde_json::json!({"error":"subscription URL must use http or https"});
                }
                let id = s.id;
                self.db.lock().await.subscriptions.push(s);
                let _ = self.save().await;
                serde_json::json!({"subscriptionId":id})
            }
            "subscription.update" => {
                let sub: Subscription = match serde_json::from_value(params["subscription"].clone())
                {
                    Ok(v) => v,
                    Err(e) => return serde_json::json!({"error":e.to_string()}),
                };
                if !valid_subscription_url(&sub.url) {
                    return serde_json::json!({"error":"subscription URL must use http or https"});
                }
                let mut db = self.db.lock().await;
                let Some(existing) = db.subscriptions.iter_mut().find(|s| s.id == sub.id) else {
                    return serde_json::json!({"error":"subscription not found"});
                };
                // Refresh metadata is daemon-owned state; a UI edit must not erase it.
                let mut updated = sub;
                if updated.last_error.is_none() {
                    updated.last_error = existing.last_error.clone();
                }
                if updated.last_refresh_at.is_none() {
                    updated.last_refresh_at = existing.last_refresh_at;
                }
                *existing = updated;
                drop(db);
                let _ = self.save().await;
                serde_json::json!({"ok":true})
            }
            "subscription.delete" => {
                let id = params["subscriptionId"]
                    .as_str()
                    .and_then(|s| uuid::Uuid::parse_str(s).ok());
                let Some(id) = id else {
                    return serde_json::json!({"error":"invalid subscription id"});
                };
                let mut db = self.db.lock().await;
                if !db.subscriptions.iter().any(|s| s.id == id) {
                    return serde_json::json!({"error":"subscription not found"});
                }
                db.subscriptions.retain(|s| s.id != id);
                db.profiles.retain(|p| p.source_id != Some(id));
                drop(db);
                let _ = self.save().await;
                serde_json::json!({"ok":true})
            }
            "subscription.refresh" => {
                let id = params["subscriptionId"]
                    .as_str()
                    .and_then(|s| uuid::Uuid::parse_str(s).ok());
                let Some(id) = id else {
                    return serde_json::json!({"error":"invalid subscription id"});
                };
                let (url, more_url, filter, user_agent, convert_target, convert_url) = {
                    let db = self.db.lock().await;
                    match db.subscriptions.iter().find(|s| s.id == id) {
                        Some(s) if s.enabled => (
                            s.url.clone(),
                            s.more_url.clone(),
                            s.filter.clone(),
                            s.user_agent.clone(),
                            s.convert_target.clone(),
                            db.settings.sub_convert_url.clone(),
                        ),
                        Some(_) => return serde_json::json!({"error":"subscription is disabled"}),
                        None => return serde_json::json!({"error":"subscription not found"}),
                    }
                };
                let effective_url = if let Some(converter) = convert_url.as_deref() {
                    if let Some(target) = convert_target.as_deref() {
                        let encoded = urlencoding(&url);
                        format!("{converter}sub?target={target}&url={encoded}")
                    } else {
                        url.clone()
                    }
                } else {
                    url.clone()
                };
                let mut command = tokio::process::Command::new("curl");
                command.args(["-fsSL", "--max-time", "20"]);
                if let Some(ua) = user_agent.as_deref() {
                    if !ua.trim().is_empty() {
                        command.arg("-A").arg(ua);
                    }
                }
                let output = match command.arg(&effective_url).output().await {
                    Ok(v) if v.status.success() => v,
                    Ok(_) => {
                        self.set_subscription_error(
                            id,
                            Some("subscription download failed".into()),
                        )
                        .await;
                        return serde_json::json!({"error":"subscription download failed"});
                    }
                    Err(e) => {
                        let error = e.to_string();
                        self.set_subscription_error(id, Some(error.clone())).await;
                        return serde_json::json!({"error":error});
                    }
                };
                let mut bodies = String::from_utf8_lossy(&output.stdout).to_string();
                if let Some(extra) = more_url.as_deref() {
                    for extra_url in extra.split(',').map(str::trim).filter(|u| !u.is_empty()) {
                        let effective_extra = if let Some(converter) = convert_url.as_deref() {
                            if let Some(target) = convert_target.as_deref() {
                                format!(
                                    "{converter}sub?target={target}&url={}",
                                    urlencoding(extra_url)
                                )
                            } else {
                                extra_url.to_string()
                            }
                        } else {
                            extra_url.to_string()
                        };
                        let mut extra_command = tokio::process::Command::new("curl");
                        extra_command.args(["-fsSL", "--max-time", "20"]);
                        if let Some(ua) = user_agent.as_deref() {
                            if !ua.trim().is_empty() {
                                extra_command.arg("-A").arg(ua);
                            }
                        }
                        if let Ok(output) = extra_command.arg(&effective_extra).output().await {
                            if output.status.success() {
                                bodies.push('\n');
                                bodies.push_str(&String::from_utf8_lossy(&output.stdout));
                            }
                        }
                    }
                }
                let mut parsed: Vec<Profile> = rayarchy_core::import::parse_input(&bodies)
                    .unwrap_or_default()
                    .into_iter()
                    .map(|mut p| {
                        p.source_id = Some(id);
                        p
                    })
                    .collect();
                if let Some(pattern) = filter.as_deref() {
                    if let Ok(regex) = regex::Regex::new(pattern) {
                        parsed.retain(|profile| {
                            regex.is_match(profile.name.as_str())
                                || profile
                                    .server
                                    .as_deref()
                                    .map(|s| regex.is_match(s))
                                    .unwrap_or(false)
                        });
                    }
                }
                if parsed.is_empty() {
                    self.set_subscription_error(
                        id,
                        Some("subscription contained no supported profiles".into()),
                    )
                    .await;
                    return serde_json::json!({"error":"subscription contained no supported profiles"});
                }
                let count = parsed.len();
                let mut db = self.db.lock().await;
                db.profiles.retain(|p| p.source_id != Some(id));
                db.profiles.extend(parsed);
                drop(db);
                let _ = self.save().await;
                self.set_subscription_error(id, None).await;
                serde_json::json!({"updated":count})
            }
            _ => serde_json::json!({"error":"method not found"}),
        }
    }

    async fn record_test(&self, result: serde_json::Value) {
        let mut db = self.db.lock().await;
        let mut result = result;
        if let Some(object) = result.as_object_mut() {
            object
                .entry("timestamp")
                .or_insert_with(|| serde_json::json!(chrono::Utc::now().timestamp()));
        }
        db.test_history.push(result);
        let cutoff = chrono::Utc::now().timestamp() - 30 * 24 * 60 * 60;
        db.test_history.retain(|row| {
            row.get("timestamp")
                .and_then(|v| v.as_i64())
                .map(|timestamp| timestamp >= cutoff)
                .unwrap_or(true)
        });
        if db.test_history.len() > 100 {
            db.test_history.remove(0);
        }
        drop(db);
        let _ = self.save().await;
    }

    fn core_available(&self, name: &str) -> bool {
        resolve_bin(&self.bin_dir, name).is_file() || command_exists(name)
    }

    /// Sample the connected core's cumulative traffic and fold the deltas into
    /// the profile's today/total counters. Runs until the connection drops.
    fn spawn_statistics_poller(self: &Arc<Self>) {
        let daemon = Arc::clone(self);
        tokio::spawn(async move {
            let mut last_up = 0u64;
            let mut last_down = 0u64;
            loop {
                let profile_id = *daemon.connected.lock().await;
                let Some(profile_id) = profile_id else { break };
                let (port, core) = {
                    let db = daemon.db.lock().await;
                    let port = db.settings.local_port.saturating_add(5);
                    let core = db
                        .profiles
                        .iter()
                        .find(|p| p.id == profile_id)
                        .map(|p| configgen::choose_core(p, db.settings.preferred_core))
                        .unwrap_or(rayarchy_core::protocol::Core::Xray);
                    (port, core)
                };
                let path = if core == rayarchy_core::protocol::Core::SingBox {
                    "/traffic"
                } else {
                    "/debug/vars"
                };
                let output = tokio::process::Command::new("curl")
                    .args(["-fsS", "--noproxy", "*", "--max-time", "2"])
                    .arg(format!("http://127.0.0.1:{port}{path}"))
                    .output()
                    .await;
                let parsed = output
                    .ok()
                    .filter(|o| o.status.success())
                    .and_then(|o| parse_traffic(core, &o.stdout));
                let (up, down) = parsed
                    .map(|v| {
                        (
                            v["up"].as_u64().unwrap_or(0),
                            v["down"].as_u64().unwrap_or(0),
                        )
                    })
                    .unwrap_or((last_up, last_down));
                if up >= last_up && down >= last_down {
                    let up_delta = up - last_up;
                    let down_delta = down - last_down;
                    last_up = up;
                    last_down = down;
                    if up_delta > 0 || down_delta > 0 {
                        daemon
                            .accumulate_stats(profile_id, up_delta, down_delta)
                            .await;
                    }
                } else {
                    last_up = up;
                    last_down = down;
                }
                tokio::time::sleep(std::time::Duration::from_secs(2)).await;
            }
        });
    }

    async fn accumulate_stats(&self, profile_id: uuid::Uuid, up: u64, down: u64) {
        let day = chrono::Utc::now().format("%Y-%m-%d").to_string();
        let key = profile_id.to_string();
        let mut db = self.db.lock().await;
        let stats = db.statistics.entry(key).or_default();
        if stats.day != day {
            stats.today_up = 0;
            stats.today_down = 0;
            stats.day = day;
        }
        stats.today_up = stats.today_up.saturating_add(up);
        stats.today_down = stats.today_down.saturating_add(down);
        stats.total_up = stats.total_up.saturating_add(up);
        stats.total_down = stats.total_down.saturating_add(down);
        drop(db);
        let _ = self.save().await;
    }

    async fn profile_stats(&self, profile_id: uuid::Uuid) -> serde_json::Value {
        let db = self.db.lock().await;
        db.statistics
            .get(&profile_id.to_string())
            .map(|s| {
                serde_json::json!({
                    "todayUp": s.today_up,
                    "todayDown": s.today_down,
                    "totalUp": s.total_up,
                    "totalDown": s.total_down
                })
            })
            .unwrap_or_else(
                || serde_json::json!({"todayUp":0,"todayDown":0,"totalUp":0,"totalDown":0}),
            )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]
    async fn profile_lifecycle_is_persistent_and_safe() {
        let path =
            std::env::temp_dir().join(format!("rayarchy-test-{}.json", uuid::Uuid::new_v4()));
        let daemon = Daemon::new(path.clone()).unwrap();
        let profile = Profile {
            name: "Example".into(),
            server: Some("example.com".into()),
            port: Some(443),
            ..Default::default()
        };
        let created = daemon
            .dispatch("profile.create", serde_json::json!({"profile":profile}))
            .await;
        let id = created["profileId"].as_str().unwrap().to_string();
        assert_eq!(
            daemon
                .dispatch("profile.list", serde_json::json!({}))
                .await
                .as_array()
                .unwrap()
                .len(),
            1
        );
        let edited = Profile {
            id: uuid::Uuid::parse_str(&id).unwrap(),
            name: "Edited".into(),
            server: Some("example.com".into()),
            port: Some(443),
            ..Default::default()
        };
        assert_eq!(
            daemon
                .dispatch("profile.update", serde_json::json!({"profile":edited}))
                .await["ok"],
            true
        );
        assert_eq!(
            daemon
                .dispatch("profile.get", serde_json::json!({"profileId":id}))
                .await["name"],
            "Edited"
        );
        let _ = std::fs::remove_file(path);
    }

    #[tokio::test]
    async fn policy_groups_and_proxy_chains_validate_members() {
        let path =
            std::env::temp_dir().join(format!("rayarchy-test-{}.json", uuid::Uuid::new_v4()));
        let daemon = Daemon::new(path.clone()).unwrap();
        let first = Profile {
            name: "Entry".into(),
            protocol: rayarchy_core::protocol::Protocol::Socks,
            server: Some("entry.example".into()),
            port: Some(1080),
            ..Default::default()
        };
        let second = Profile {
            name: "Exit".into(),
            protocol: rayarchy_core::protocol::Protocol::Trojan,
            server: Some("exit.example".into()),
            port: Some(443),
            ..Default::default()
        };
        for profile in [&first, &second] {
            assert!(daemon
                .dispatch("profile.create", serde_json::json!({"profile":profile}))
                .await
                .get("error")
                .is_none());
        }
        let chain = Profile {
            name: "Two hop".into(),
            protocol: rayarchy_core::protocol::Protocol::ProxyChain,
            members: vec![first.id, second.id],
            ..Default::default()
        };
        assert!(daemon
            .dispatch("profile.create", serde_json::json!({"profile":chain}))
            .await["profileId"]
            .is_string());
        let invalid = Profile {
            name: "Broken group".into(),
            protocol: rayarchy_core::protocol::Protocol::PolicyGroup,
            members: vec![uuid::Uuid::new_v4()],
            strategy: Some("latency".into()),
            ..Default::default()
        };
        assert_eq!(
            daemon
                .dispatch("profile.create", serde_json::json!({"profile":invalid}))
                .await["error"],
            format!("member profile {} was not found", invalid.members[0])
        );
        let _ = std::fs::remove_file(path);
    }

    #[tokio::test]
    async fn duplicate_cleanup_and_qr_input_validation_are_safe() {
        let path =
            std::env::temp_dir().join(format!("rayarchy-test-{}.json", uuid::Uuid::new_v4()));
        let daemon = Daemon::new(path.clone()).unwrap();
        let profile = Profile {
            name: "Duplicate".into(),
            server: Some("duplicate.example".into()),
            port: Some(443),
            ..Default::default()
        };
        let mut copy = profile.clone();
        copy.id = uuid::Uuid::new_v4();
        daemon.db.lock().await.profiles.extend([profile, copy]);
        assert_eq!(
            daemon
                .dispatch("profile.duplicates.remove", serde_json::json!({}))
                .await["removed"],
            1
        );
        assert_eq!(daemon.db.lock().await.profiles.len(), 1);
        assert!(daemon
            .dispatch(
                "import.qr.image",
                serde_json::json!({"path":"/definitely/missing/rayarchy.png"})
            )
            .await["error"]
            .is_string());
        let _ = std::fs::remove_file(path);
    }

    #[tokio::test]
    async fn profile_list_includes_latest_persisted_test_result() {
        let path =
            std::env::temp_dir().join(format!("rayarchy-test-{}.json", uuid::Uuid::new_v4()));
        let daemon = Daemon::new(path.clone()).unwrap();
        let profile = Profile {
            name: "Health".into(),
            server: Some("health.example".into()),
            port: Some(443),
            ..Default::default()
        };
        let id = profile.id;
        daemon
            .dispatch("profile.create", serde_json::json!({"profile":profile}))
            .await;
        daemon
            .record_test(
                serde_json::json!({"kind":"bulk-proxy","profileId":id,"ok":true,"latencyMs":42}),
            )
            .await;
        let listed = daemon.dispatch("profile.list", serde_json::json!({})).await;
        assert_eq!(listed[0]["lastTest"]["ok"], true);
        assert_eq!(listed[0]["lastTest"]["latencyMs"], 42);
        let _ = std::fs::remove_file(path);
    }

    #[tokio::test]
    async fn clearing_profile_health_removes_only_that_profile_history() {
        let path =
            std::env::temp_dir().join(format!("rayarchy-test-{}.json", uuid::Uuid::new_v4()));
        let daemon = Daemon::new(path.clone()).unwrap();
        let first = uuid::Uuid::new_v4();
        let second = uuid::Uuid::new_v4();
        daemon
            .record_test(serde_json::json!({"profileId":first,"ok":true}))
            .await;
        daemon
            .record_test(serde_json::json!({"profileId":second,"ok":true}))
            .await;
        assert_eq!(
            daemon
                .dispatch("test.history.clear", serde_json::json!({"profileId":first}))
                .await["ok"],
            true
        );
        let history = daemon.dispatch("test.history", serde_json::json!({})).await;
        assert_eq!(history.as_array().unwrap().len(), 1);
        assert_eq!(history[0]["profileId"], second.to_string());
        let _ = std::fs::remove_file(path);
    }

    #[tokio::test]
    async fn stale_profile_health_is_not_exposed_in_listing() {
        let path =
            std::env::temp_dir().join(format!("rayarchy-test-{}.json", uuid::Uuid::new_v4()));
        let daemon = Daemon::new(path.clone()).unwrap();
        let profile = Profile {
            name: "Stale".into(),
            server: Some("stale.example".into()),
            port: Some(443),
            ..Default::default()
        };
        let id = profile.id;
        daemon
            .dispatch("profile.create", serde_json::json!({"profile":profile}))
            .await;
        daemon.record_test(serde_json::json!({"profileId":id,"ok":true,"timestamp":chrono::Utc::now().timestamp() - 3 * 24 * 60 * 60})).await;
        let listed = daemon.dispatch("profile.list", serde_json::json!({})).await;
        assert!(listed[0].get("lastTest").is_none());
        let _ = std::fs::remove_file(path);
    }

    #[tokio::test]
    async fn old_timestamped_test_history_is_pruned() {
        let path =
            std::env::temp_dir().join(format!("rayarchy-test-{}.json", uuid::Uuid::new_v4()));
        let daemon = Daemon::new(path.clone()).unwrap();
        daemon.db.lock().await.test_history.push(
            serde_json::json!({"timestamp": chrono::Utc::now().timestamp() - 31 * 24 * 60 * 60}),
        );
        daemon
            .record_test(serde_json::json!({"kind":"proxy","ok":true}))
            .await;
        let history = daemon.dispatch("test.history", serde_json::json!({})).await;
        assert_eq!(history.as_array().unwrap().len(), 1);
        let _ = std::fs::remove_file(path);
    }

    #[tokio::test]
    async fn profile_list_filters_sorts_and_reorders() {
        let path =
            std::env::temp_dir().join(format!("rayarchy-test-{}.json", uuid::Uuid::new_v4()));
        let daemon = Daemon::new(path.clone()).unwrap();
        let alpha = Profile {
            name: "Alpha".into(),
            group: "Work".into(),
            server: Some("alpha.example".into()),
            ..Default::default()
        };
        let alpha_id = alpha.id;
        let beta = Profile {
            name: "Beta".into(),
            group: "Home".into(),
            server: Some("beta.example".into()),
            ..Default::default()
        };
        let beta_id = beta.id;
        daemon
            .dispatch("profile.create", serde_json::json!({"profile":beta}))
            .await;
        daemon
            .dispatch("profile.create", serde_json::json!({"profile":alpha}))
            .await;
        assert_eq!(
            daemon
                .dispatch(
                    "profile.favorite",
                    serde_json::json!({"profileId":alpha_id,"favorite":true}),
                )
                .await["ok"],
            true
        );
        assert_eq!(
            daemon
                .dispatch(
                    "profile.enable",
                    serde_json::json!({"profileId":beta_id,"enabled":false}),
                )
                .await["ok"],
            true
        );

        let filtered = daemon
            .dispatch(
                "profile.list",
                serde_json::json!({"group":"Work","favoritesOnly":true}),
            )
            .await;
        assert_eq!(filtered.as_array().unwrap().len(), 1);
        assert_eq!(filtered[0]["name"], "Alpha");

        let sorted = daemon
            .dispatch("profile.list", serde_json::json!({"sort":"name"}))
            .await;
        assert_eq!(sorted[0]["name"], "Alpha");
        daemon
            .dispatch(
                "profile.reorder",
                serde_json::json!({"profileIds":[alpha_id, beta_id]}),
            )
            .await;
        let reordered = daemon.dispatch("profile.list", serde_json::json!({})).await;
        assert_eq!(reordered[0]["id"], alpha_id.to_string());
        let _ = std::fs::remove_file(path);
    }

    #[tokio::test]
    async fn active_profile_cannot_be_deleted() {
        let path =
            std::env::temp_dir().join(format!("rayarchy-test-{}.json", uuid::Uuid::new_v4()));
        let daemon = Daemon::new(path.clone()).unwrap();
        let profile = Profile {
            name: "Active".into(),
            server: Some("active.example".into()),
            ..Default::default()
        };
        let id = profile.id;
        daemon
            .dispatch("profile.create", serde_json::json!({"profile":profile}))
            .await;
        *daemon.connected.lock().await = Some(id);
        let result = daemon
            .dispatch("profile.delete", serde_json::json!({"profileId":id}))
            .await;
        assert!(result.get("error").is_some());
        assert_eq!(
            daemon
                .dispatch("profile.list", serde_json::json!({}))
                .await
                .as_array()
                .unwrap()
                .len(),
            1
        );
        let _ = std::fs::remove_file(path);
    }

    #[tokio::test]
    async fn subscription_urls_are_validated_before_persistence() {
        let path =
            std::env::temp_dir().join(format!("rayarchy-test-{}.json", uuid::Uuid::new_v4()));
        let daemon = Daemon::new(path.clone()).unwrap();
        let result = daemon
            .dispatch(
                "subscription.create",
                serde_json::json!({"subscription":{"name":"bad","url":"file:///tmp/list"}}),
            )
            .await;
        assert!(result.get("error").is_some());
        assert!(daemon
            .dispatch("subscription.list", serde_json::json!({}))
            .await
            .as_array()
            .unwrap()
            .is_empty());
        assert!(daemon
            .dispatch(
                "subscription.delete",
                serde_json::json!({"subscriptionId":"not-a-uuid"}),
            )
            .await
            .get("error")
            .is_some());
        let _ = std::fs::remove_file(path);
    }

    #[tokio::test]
    async fn subscription_update_preserves_refresh_metadata() {
        let path =
            std::env::temp_dir().join(format!("rayarchy-test-{}.json", uuid::Uuid::new_v4()));
        let daemon = Daemon::new(path.clone()).unwrap();
        let created = daemon
            .dispatch(
                "subscription.create",
                serde_json::json!({"subscription":{"name":"source","url":"https://example.com/list"}}),
            )
            .await;
        let id = created["subscriptionId"].clone();
        {
            let mut db = daemon.db.lock().await;
            let subscription = db
                .subscriptions
                .iter_mut()
                .find(|s| Some(s.id.to_string()) == id.as_str().map(str::to_owned))
                .unwrap();
            subscription.last_error = Some("temporary failure".into());
            subscription.last_refresh_at = Some(1234);
        }
        daemon
            .dispatch(
                "subscription.update",
                serde_json::json!({"subscription":{"id":id,"name":"renamed","url":"https://example.com/list","enabled":true,"autoUpdate":"daily"}}),
            )
            .await;
        let listed = daemon
            .dispatch("subscription.list", serde_json::json!({}))
            .await;
        assert_eq!(listed[0]["name"], "renamed");
        assert_eq!(listed[0]["lastError"], "temporary failure");
        assert_eq!(listed[0]["lastRefreshAt"], 1234);
        let _ = std::fs::remove_file(path);
    }

    #[tokio::test]
    async fn profile_create_rejects_missing_endpoint() {
        let path =
            std::env::temp_dir().join(format!("rayarchy-test-{}.json", uuid::Uuid::new_v4()));
        let daemon = Daemon::new(path.clone()).unwrap();
        let result = daemon
            .dispatch(
                "profile.create",
                serde_json::json!({"profile":{"name":"broken","protocol":"vless","fields":{}}}),
            )
            .await;
        assert!(result.get("error").is_some());
        let _ = std::fs::remove_file(path);
    }

    #[tokio::test]
    async fn raw_profile_updates_require_supported_syntax() {
        let path =
            std::env::temp_dir().join(format!("rayarchy-test-{}.json", uuid::Uuid::new_v4()));
        let daemon = Daemon::new(path.clone()).unwrap();
        let profile = Profile {
            name: "Raw".into(),
            server: Some("raw.example".into()),
            ..Default::default()
        };
        let id = profile.id;
        daemon
            .dispatch("profile.create", serde_json::json!({"profile":profile}))
            .await;
        let bad = daemon
            .dispatch(
                "profile.raw.update",
                serde_json::json!({"profileId":id,"raw":"not a profile"}),
            )
            .await;
        assert!(bad.get("error").is_some());
        let good = daemon
            .dispatch(
                "profile.raw.update",
                serde_json::json!({"profileId":id,"raw":"vless://id@raw.example:443"}),
            )
            .await;
        assert_eq!(good["ok"], true);
        let _ = std::fs::remove_file(path);
    }

    #[tokio::test]
    async fn protocol_schema_lists_required_editor_fields() {
        let path =
            std::env::temp_dir().join(format!("rayarchy-test-{}.json", uuid::Uuid::new_v4()));
        let daemon = Daemon::new(path.clone()).unwrap();
        let schema = daemon
            .dispatch("profile.schema", serde_json::json!({"protocol":"vless"}))
            .await;
        assert!(schema["fields"]
            .as_array()
            .unwrap()
            .iter()
            .any(|field| field == "user"));
        let _ = std::fs::remove_file(path);
    }

    #[tokio::test]
    async fn capabilities_report_effective_safe_features() {
        let path =
            std::env::temp_dir().join(format!("rayarchy-test-{}.json", uuid::Uuid::new_v4()));
        let daemon = Daemon::new(path.clone()).unwrap();
        let capabilities = daemon
            .dispatch("system.capabilities", serde_json::json!({}))
            .await;
        assert_eq!(capabilities["tun"], false);
        assert!(capabilities.get("dnsProtection").is_some());
        let _ = std::fs::remove_file(path);
    }

    #[tokio::test]
    async fn dns_and_lan_settings_persist_across_restart() {
        let path =
            std::env::temp_dir().join(format!("rayarchy-test-{}.json", uuid::Uuid::new_v4()));
        let daemon = Daemon::new(path.clone()).unwrap();
        let result = daemon.dispatch("settings.update", serde_json::json!({"settings":{"connectionMode":"local","preferredCore":"auto","localPort":1080,"killSwitch":false,"dnsLeakProtection":false,"lanBypass":false}})).await;
        assert_eq!(result["ok"], true);
        let restarted = Daemon::new(path.clone()).unwrap();
        let settings = restarted
            .dispatch("settings.get", serde_json::json!({}))
            .await;
        assert_eq!(settings["dnsLeakProtection"], false);
        assert_eq!(settings["lanBypass"], false);
        let _ = std::fs::remove_file(path);
    }

    #[tokio::test]
    async fn legacy_state_without_new_sections_migrates() {
        let path =
            std::env::temp_dir().join(format!("rayarchy-test-{}.json", uuid::Uuid::new_v4()));
        std::fs::write(&path, br#"{"profiles":[]}"#).unwrap();
        let daemon = Daemon::new(path.clone()).unwrap();
        let settings = daemon.dispatch("settings.get", serde_json::json!({})).await;
        assert_eq!(settings["localPort"], 1080);
        assert!(daemon
            .dispatch("profile.list", serde_json::json!({}))
            .await
            .as_array()
            .unwrap()
            .is_empty());
        let _ = std::fs::remove_file(path);
    }

    #[tokio::test]
    async fn backup_round_trip_restores_profiles_and_settings() {
        let source_path =
            std::env::temp_dir().join(format!("rayarchy-test-{}.json", uuid::Uuid::new_v4()));
        let target_path =
            std::env::temp_dir().join(format!("rayarchy-test-{}.json", uuid::Uuid::new_v4()));
        let source = Daemon::new(source_path.clone()).unwrap();
        let profile = Profile {
            name: "Backup".into(),
            server: Some("backup.example".into()),
            ..Default::default()
        };
        source
            .dispatch("profile.create", serde_json::json!({"profile":profile}))
            .await;
        let exported = source
            .dispatch("backup.export", serde_json::json!({}))
            .await;
        let target = Daemon::new(target_path.clone()).unwrap();
        let restored = target
            .dispatch(
                "backup.import",
                serde_json::json!({"state":exported["state"]}),
            )
            .await;
        assert_eq!(restored["ok"], true);
        assert_eq!(
            target
                .dispatch("profile.list", serde_json::json!({}))
                .await
                .as_array()
                .unwrap()
                .len(),
            1
        );
        let _ = std::fs::remove_file(source_path);
        let _ = std::fs::remove_file(target_path);
    }

    #[tokio::test]
    async fn invalid_backup_is_rejected_without_mutating_state() {
        let path =
            std::env::temp_dir().join(format!("rayarchy-test-{}.json", uuid::Uuid::new_v4()));
        let daemon = Daemon::new(path.clone()).unwrap();
        let profile = Profile {
            name: "Keep".into(),
            server: Some("keep.example".into()),
            port: Some(443),
            ..Default::default()
        };
        daemon
            .dispatch("profile.create", serde_json::json!({"profile":profile}))
            .await;
        let missing = daemon
            .dispatch("backup.import", serde_json::json!({}))
            .await;
        assert!(missing["error"]
            .as_str()
            .unwrap()
            .contains("missing backup state"));
        let malformed = daemon
            .dispatch(
                "backup.import",
                serde_json::json!({"state":{"profiles":"bad"}}),
            )
            .await;
        assert!(malformed["error"]
            .as_str()
            .unwrap()
            .contains("invalid backup"));
        let profiles = daemon.dispatch("profile.list", serde_json::json!({})).await;
        assert_eq!(profiles.as_array().unwrap().len(), 1);
        assert_eq!(profiles[0]["name"], "Keep");
        let _ = std::fs::remove_file(path);
    }

    #[tokio::test]
    async fn unsupported_tun_mode_never_reports_connected() {
        let path =
            std::env::temp_dir().join(format!("rayarchy-test-{}.json", uuid::Uuid::new_v4()));
        let daemon = Daemon::new(path.clone()).unwrap();
        let profile = Profile {
            name: "Tun test".into(),
            server: Some("tun.example".into()),
            port: Some(443),
            ..Default::default()
        };
        let id = profile.id;
        daemon
            .dispatch("profile.create", serde_json::json!({"profile":profile}))
            .await;
        let settings = daemon
            .dispatch(
                "settings.update",
                serde_json::json!({"settings":{"connectionMode":"tun","preferredCore":"auto","localPort":1080,"killSwitch":false,"dnsLeakProtection":false,"lanBypass":false}}),
            )
            .await;
        assert_eq!(settings["ok"], true);
        let result = daemon
            .dispatch("profile.connect", serde_json::json!({"profileId":id}))
            .await;
        assert!(result.get("error").is_some());
        let status = daemon
            .dispatch("system.status", serde_json::json!({}))
            .await;
        assert_eq!(status["connected"], false);
        let _ = std::fs::remove_file(path);
    }

    #[tokio::test]
    async fn status_includes_latest_profile_health() {
        let path =
            std::env::temp_dir().join(format!("rayarchy-test-{}.json", uuid::Uuid::new_v4()));
        let daemon = Daemon::new(path.clone()).unwrap();
        let profile = Profile {
            name: "Healthy".into(),
            server: Some("healthy.example".into()),
            port: Some(443),
            ..Default::default()
        };
        let id = profile.id;
        daemon
            .dispatch("profile.create", serde_json::json!({"profile":profile}))
            .await;
        *daemon.connected.lock().await = Some(id);
        daemon
            .db
            .lock()
            .await
            .test_history
            .push(serde_json::json!({"kind":"proxy","profileId":id,"ok":true,"latencyMs":42}));
        let status = daemon
            .dispatch("system.status", serde_json::json!({}))
            .await;
        assert_eq!(status["profileName"], "Healthy");
        assert_eq!(status["lastHealth"]["latencyMs"], 42);
        let _ = std::fs::remove_file(path);
    }

    #[tokio::test]
    async fn test_history_supports_profile_and_kind_filters() {
        let path =
            std::env::temp_dir().join(format!("rayarchy-test-{}.json", uuid::Uuid::new_v4()));
        let daemon = Daemon::new(path.clone()).unwrap();
        let first = uuid::Uuid::new_v4();
        let second = uuid::Uuid::new_v4();
        {
            let mut db = daemon.db.lock().await;
            db.test_history = vec![
                serde_json::json!({"profileId":first,"kind":"tcp"}),
                serde_json::json!({"profileId":first,"kind":"proxy"}),
                serde_json::json!({"profileId":second,"kind":"proxy"}),
            ];
        }
        let rows = daemon
            .dispatch(
                "test.history",
                serde_json::json!({"profileId":first,"kind":"proxy"}),
            )
            .await;
        assert_eq!(rows.as_array().unwrap().len(), 1);
        assert_eq!(rows[0]["profileId"], first.to_string());
        let _ = std::fs::remove_file(path);
    }

    #[tokio::test]
    async fn bulk_proxy_test_requires_disconnected_state() {
        let path =
            std::env::temp_dir().join(format!("rayarchy-test-{}.json", uuid::Uuid::new_v4()));
        let daemon = Daemon::new(path.clone()).unwrap();
        let profile = Profile {
            name: "Bulk guard".into(),
            server: Some("bulk.example".into()),
            port: Some(443),
            ..Default::default()
        };
        daemon
            .dispatch("profile.create", serde_json::json!({"profile":profile}))
            .await;
        let result = daemon
            .dispatch("test.bulk.proxy", serde_json::json!({"profileIds":[]}))
            .await;
        assert!(result.get("results").is_some());
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn routing_rules_are_compiled_into_core_config() {
        let profile = Profile {
            server: Some("example.com".into()),
            port: Some(443),
            ..Default::default()
        };
        let rule = RoutingRule {
            id: uuid::Uuid::new_v4(),
            name: "LAN".into(),
            match_type: "cidr".into(),
            value: "192.168.0.0/16".into(),
            action: "direct".into(),
            enabled: true,
        };
        let mut config = configgen::build(
            &profile,
            rayarchy_core::protocol::Core::SingBox,
            "127.0.0.1",
            1080,
        );
        configgen::apply_rules(&mut config, rayarchy_core::protocol::Core::SingBox, &[rule]);
        assert_eq!(config["route"]["rules"].as_array().unwrap().len(), 1);
    }

    #[tokio::test]
    async fn default_profile_can_be_set_queried_and_survives_restart() {
        let path =
            std::env::temp_dir().join(format!("rayarchy-test-{}.json", uuid::Uuid::new_v4()));
        let daemon = Daemon::new(path.clone()).unwrap();
        let profile = Profile {
            name: "Default".into(),
            server: Some("default.example".into()),
            ..Default::default()
        };
        let id = profile.id;
        daemon
            .dispatch("profile.create", serde_json::json!({"profile":profile}))
            .await;
        let result = daemon
            .dispatch("profile.setDefault", serde_json::json!({"profileId":id}))
            .await;
        assert_eq!(result["ok"], true);
        let listed = daemon.dispatch("profile.list", serde_json::json!({})).await;
        assert_eq!(listed[0]["default"], true);
        let queried = daemon
            .dispatch("profile.default", serde_json::json!({}))
            .await;
        assert_eq!(queried["id"], id.to_string());
        let missing = daemon
            .dispatch(
                "profile.setDefault",
                serde_json::json!({"profileId":"00000000-0000-0000-0000-000000000000"}),
            )
            .await;
        assert!(missing.get("error").is_some());
        let restarted = Daemon::new(path.clone()).unwrap();
        let queried = restarted
            .dispatch("profile.default", serde_json::json!({}))
            .await;
        assert_eq!(queried["id"], id.to_string());
        let _ = std::fs::remove_file(path);
    }

    #[tokio::test]
    async fn ui_state_round_trips_and_migrates_from_legacy_state() {
        let path =
            std::env::temp_dir().join(format!("rayarchy-test-{}.json", uuid::Uuid::new_v4()));
        let daemon = Daemon::new(path.clone()).unwrap();
        let stored = daemon.dispatch("ui.get", serde_json::json!({})).await;
        assert_eq!(stored, serde_json::json!({}));
        let result = daemon
            .dispatch(
                "ui.set",
                serde_json::json!({"ui":{"windowWidth":1280,"columns":{"delay":true}}}),
            )
            .await;
        assert_eq!(result["ok"], true);
        let reloaded = Daemon::new(path.clone()).unwrap();
        let stored = reloaded.dispatch("ui.get", serde_json::json!({})).await;
        assert_eq!(stored["windowWidth"], 1280);
        let invalid = reloaded
            .dispatch("ui.set", serde_json::json!({"ui":"nope"}))
            .await;
        assert!(invalid.get("error").is_some());
        let _ = std::fs::remove_file(path);
    }

    #[tokio::test]
    async fn reload_without_connection_is_a_safe_noop() {
        let path =
            std::env::temp_dir().join(format!("rayarchy-test-{}.json", uuid::Uuid::new_v4()));
        let daemon = Daemon::new(path.clone()).unwrap();
        let result = daemon
            .dispatch("system.reload", serde_json::json!({}))
            .await;
        assert_eq!(result["ok"], true);
        assert_eq!(result["reloaded"], false);
        let _ = std::fs::remove_file(path);
    }

    #[tokio::test]
    async fn settings_update_preserves_default_and_ui_state() {
        let path =
            std::env::temp_dir().join(format!("rayarchy-test-{}.json", uuid::Uuid::new_v4()));
        let daemon = Daemon::new(path.clone()).unwrap();
        let profile = Profile {
            name: "Keep".into(),
            server: Some("keep.example".into()),
            ..Default::default()
        };
        daemon
            .dispatch("profile.create", serde_json::json!({"profile":profile}))
            .await;
        daemon
            .dispatch(
                "profile.setDefault",
                serde_json::json!({"profileId":profile.id}),
            )
            .await;
        daemon
            .dispatch(
                "ui.set",
                serde_json::json!({"ui":{"columns":[{"key":"delay","width":90}]}}),
            )
            .await;
        let result = daemon.dispatch("settings.update", serde_json::json!({"settings":{"connectionMode":"local","preferredCore":"auto","localPort":1081,"killSwitch":false,"dnsLeakProtection":false,"lanBypass":false,"healthRetentionHours":24}})).await;
        assert_eq!(result["ok"], true);
        let settings = daemon.dispatch("settings.get", serde_json::json!({})).await;
        assert_eq!(settings["localPort"], 1081);
        assert_eq!(settings["defaultProfileId"], profile.id.to_string());
        assert_eq!(settings["ui"]["columns"][0]["key"], "delay");
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn urlencoding_escapes_query_safe_way() {
        assert_eq!(
            urlencoding("https://a.example/sub?x=1&y=two"),
            "https%3A%2F%2Fa.example%2Fsub%3Fx%3D1%26y%3Dtwo"
        );
        assert_eq!(urlencoding("plain"), "plain");
    }

    #[test]
    fn parses_traffic_from_both_cores() {
        let sing = parse_traffic(
            rayarchy_core::protocol::Core::SingBox,
            br#"{"up":123,"down":456}"#,
        )
        .unwrap();
        assert_eq!(sing["up"], 123);
        assert_eq!(sing["down"], 456);
        let xray = parse_traffic(
            rayarchy_core::protocol::Core::Xray,
            br#"{"proxy|outbound|direct|traffic|uplink":"100","proxy|outbound|proxy|traffic|downlink":"200","other":"x"}"#,
        )
        .unwrap();
        assert_eq!(xray["up"], 100);
        assert_eq!(xray["down"], 200);
    }

    #[tokio::test]
    async fn statistics_accumulate_per_profile_and_rotate_daily() {
        let path =
            std::env::temp_dir().join(format!("rayarchy-test-{}.json", uuid::Uuid::new_v4()));
        let daemon = Daemon::new(path.clone()).unwrap();
        let profile = Profile {
            name: "Stats".into(),
            server: Some("stats.example".into()),
            ..Default::default()
        };
        daemon
            .dispatch("profile.create", serde_json::json!({"profile":profile}))
            .await;
        daemon.accumulate_stats(profile.id, 500, 900).await;
        daemon.accumulate_stats(profile.id, 100, 100).await;
        let listed = daemon.dispatch("profile.list", serde_json::json!({})).await;
        assert_eq!(listed[0]["todayUp"], 600);
        assert_eq!(listed[0]["totalDown"], 1000);
        let cleared = daemon
            .dispatch(
                "statistics.clear",
                serde_json::json!({"profileId":profile.id}),
            )
            .await;
        assert_eq!(cleared["ok"], true);
        let listed = daemon.dispatch("profile.list", serde_json::json!({})).await;
        assert_eq!(listed[0]["totalUp"], 0);
        let _ = std::fs::remove_file(path);
    }

    #[tokio::test]
    async fn subscription_advanced_fields_persist() {
        let path =
            std::env::temp_dir().join(format!("rayarchy-test-{}.json", uuid::Uuid::new_v4()));
        let daemon = Daemon::new(path.clone()).unwrap();
        let sub = Subscription {
            name: "Adv".into(),
            url: "https://adv.example/sub".into(),
            more_url: Some("https://a.example/m,https://b.example/m".into()),
            filter: Some(r"US|DE".into()),
            convert_target: Some("clash".into()),
            user_agent: Some("v2rayN/7".into()),
            sort: Some(5),
            memo: Some("notes".into()),
            ..Default::default()
        };
        let created = daemon
            .dispatch(
                "subscription.create",
                serde_json::json!({"subscription":sub}),
            )
            .await;
        let id = created["subscriptionId"].as_str().unwrap();
        let restarted = Daemon::new(path.clone()).unwrap();
        let listed = restarted
            .dispatch("subscription.list", serde_json::json!({}))
            .await;
        assert_eq!(listed[0]["id"], id);
        assert_eq!(listed[0]["filter"], r"US|DE");
        assert_eq!(listed[0]["convertTarget"], "clash");
        assert_eq!(listed[0]["sort"], 5);
        let _ = std::fs::remove_file(path);
    }

    #[tokio::test]
    async fn inner_uri_export_round_trips_through_import() {
        let path =
            std::env::temp_dir().join(format!("rayarchy-test-{}.json", uuid::Uuid::new_v4()));
        let daemon = Daemon::new(path.clone()).unwrap();
        let profile = Profile {
            name: "Inner".into(),
            protocol: rayarchy_core::protocol::Protocol::Vless,
            server: Some("inner.example".into()),
            port: Some(443),
            fields: serde_json::json!({"user":"00000000-0000-0000-0000-000000000004","security":"tls"}),
            ..Default::default()
        };
        daemon
            .dispatch("profile.create", serde_json::json!({"profile":profile}))
            .await;
        let exported = daemon
            .dispatch("profile.inner", serde_json::json!({"profileId":profile.id}))
            .await;
        let uri = exported["innerUri"].as_str().unwrap();
        assert!(uri.starts_with("v2rayn://vless/"));
        let reimported = daemon
            .dispatch("import.commit", serde_json::json!({"input":uri}))
            .await;
        assert!(reimported.get("profileIds").is_some());
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn outbound_profiles_generate_singbox_configs() {
        let profile = Profile {
            protocol: rayarchy_core::protocol::Protocol::Outbound,
            server: Some("o.example".into()),
            port: Some(443),
            raw: Some(
                r#"{"type":"vless","server":"o.example","server_port":443,"uuid":"00000000-0000-0000-0000-000000000003"}"#
                    .into(),
            ),
            ..Default::default()
        };
        let config = configgen::build(
            &profile,
            rayarchy_core::protocol::Core::SingBox,
            "127.0.0.1",
            1080,
        );
        assert_eq!(config["outbounds"][0]["type"], "vless");
        assert_eq!(config["route"]["final"], "proxy");
    }
}
