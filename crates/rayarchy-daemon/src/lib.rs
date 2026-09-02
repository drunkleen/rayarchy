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

fn command_exists(name: &str) -> bool {
    std::env::var_os("PATH")
        .map(|path| std::env::split_paths(&path).any(|dir| dir.join(name).is_file()))
        .unwrap_or(false)
}

fn valid_subscription_url(url: &str) -> bool {
    let trimmed = url.trim();
    (trimmed.starts_with("https://") || trimmed.starts_with("http://")) && trimmed.len() > 8
}

fn validate_profile(profile: &Profile) -> Result<(), String> {
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
        if !network.is_empty() && !matches!(network, "tcp" | "ws" | "grpc" | "http" | "h2") {
            return Err("unsupported transport network".into());
        }
    }
    Ok(())
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
) -> Result<(), String> {
    let bin = if core == rayarchy_core::protocol::Core::SingBox {
        "sing-box"
    } else {
        "xray"
    };
    let args: &[&str] = if core == rayarchy_core::protocol::Core::SingBox {
        &["check", "-c"]
    } else {
        &["run", "-test", "-c"]
    };
    let output = tokio::process::Command::new(bin)
        .args(args)
        .arg(path)
        .output()
        .await
        .map_err(|e| format!("could not validate {bin} config: {e}"))?;
    if output.status.success() {
        Ok(())
    } else {
        let detail = String::from_utf8_lossy(&output.stderr).trim().to_string();
        Err(if detail.is_empty() {
            format!("{bin} rejected the generated configuration")
        } else {
            format!("{bin} rejected the generated configuration: {detail}")
        })
    }
}

async fn command_version(name: &str) -> Option<String> {
    let output = tokio::process::Command::new(name)
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
}

pub struct Daemon {
    db: Mutex<Database>,
    path: PathBuf,
    connected: Mutex<Option<uuid::Uuid>>,
    process: Mutex<Option<tokio::process::Child>>,
    child_pid: AtomicU32,
    config_path: PathBuf,
    proxy_backup: Mutex<Option<sysproxy::Backup>>,
    logs: Mutex<Vec<String>>,
    bulk_cancel: AtomicBool,
}
impl Daemon {
    pub fn new(path: PathBuf) -> anyhow::Result<Arc<Self>> {
        let db = if path.exists() {
            serde_json::from_slice(&std::fs::read(&path)?)?
        } else {
            Database::default()
        };
        Ok(Arc::new(Self {
            db: Mutex::new(db),
            path,
            connected: Mutex::new(None),
            process: Mutex::new(None),
            child_pid: AtomicU32::new(0),
            config_path: std::env::temp_dir().join("rayarchy/config.json"),
            proxy_backup: Mutex::new(None),
            logs: Mutex::new(Vec::new()),
            bulk_cancel: AtomicBool::new(false),
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
        let (profile, settings) = {
            let db = self.db.lock().await;
            (
                db.profiles
                    .iter()
                    .find(|p| p.id == id && p.enabled)
                    .cloned()
                    .ok_or("profile not found")?,
                db.settings.clone(),
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
        let core = configgen::choose_core(&profile, settings.preferred_core);
        let rules = {
            let db = self.db.lock().await;
            db.routing.clone()
        };
        let mut config = configgen::build(&profile, core, "127.0.0.1", settings.local_port);
        configgen::apply_rules(&mut config, core, &rules);
        configgen::apply_dns(&mut config, core, settings.dns_leak_protection);
        configgen::apply_lan_bypass(&mut config, core, settings.lan_bypass);
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
        validate_core_config(core, &self.config_path).await?;
        let child = tokio::process::Command::new(bin)
            .args(["run", "-c"])
            .arg(&self.config_path)
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::piped())
            .spawn()
            .map_err(|e| format!("could not start {bin}: {e}"))?;
        self.child_pid
            .store(child.id().unwrap_or(0), Ordering::Relaxed);
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
            .args(["-fsS", "--max-time", "8", "--proxy"])
            .arg(format!("http://127.0.0.1:{}", settings.local_port))
            .arg("https://www.gstatic.com/generate_204")
            .output()
            .await
            .map_err(|e| e.to_string())?;
        if !health.status.success() {
            let _ = self.disconnect_profile().await;
            return Err("proxy health check failed; connection was not activated".into());
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
                serde_json::json!({"connected": profile_id.is_some(), "profileId": profile_id, "cores": {"xray": command_exists("xray"), "singBox": command_exists("sing-box")}})
            }
            "system.capabilities" => {
                let settings = self.db.lock().await.settings.clone();
                serde_json::json!({"xray":command_exists("xray"),"singBox":command_exists("sing-box"),"systemProxy":true,"dnsProtection":settings.dns_leak_protection,"lanBypass":settings.lan_bypass,"tun":false,"transparent":false,"killSwitch":false})
            }
            "system.diagnostics" => {
                let status = serde_json::json!({"connected": self.connected.lock().await.is_some(), "socket": true});
                let xray = command_version("xray").await;
                let sing_box = command_version("sing-box").await;
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
                let path = std::env::temp_dir()
                    .join(format!("rayarchy-validate-{}.json", uuid::Uuid::new_v4()));
                if let Err(error) =
                    std::fs::write(&path, serde_json::to_vec(&config).unwrap_or_default())
                {
                    return serde_json::json!({"error":error.to_string()});
                }
                let result = validate_core_config(core, &path).await;
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
                serde_json::to_value(&self.db.lock().await.test_history).unwrap_or_default()
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
            "test.bulk.cancel" => {
                self.bulk_cancel.store(true, Ordering::Relaxed);
                serde_json::json!({"ok":true})
            }
            "test.proxy" => {
                let port = self.db.lock().await.settings.local_port;
                let start = std::time::Instant::now();
                let result = tokio::process::Command::new("curl")
                    .args(["-fsS", "-o", "/dev/null", "--max-time", "8", "--proxy"])
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
                    .args(["-fsS", "--max-time", "8", "--proxy"])
                    .arg(format!("http://127.0.0.1:{port}"))
                    .arg(target)
                    .output()
                    .await;
                let direct = tokio::process::Command::new("curl")
                    .args(["-fsS", "--max-time", "8", target])
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
                serde_json::json!({"proxyIp":proxy_ip,"directIp":direct_ip,"protected":proxy_ip.is_some() && proxy_ip != direct_ip})
            }
            "test.speed" => {
                let port = self.db.lock().await.settings.local_port;
                let start = std::time::Instant::now();
                let result = tokio::process::Command::new("curl")
                    .args(["-fsS", "-o", "/dev/null", "--max-time", "20", "--proxy"])
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
                let mut profiles: Vec<_> = self
                    .db
                    .lock()
                    .await
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
                match sort {
                    "name" => profiles.sort_by_key(|profile| profile.name.to_lowercase()),
                    "server" => profiles.sort_by_key(|profile| {
                        profile.server.as_deref().unwrap_or("").to_lowercase()
                    }),
                    "favorites" => profiles.sort_by_key(|profile| !profile.favorite),
                    _ => {}
                }
                serde_json::to_value(profiles).unwrap_or_default()
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
            "import.commit" => {
                let input = params["input"].as_str().unwrap_or("");
                match rayarchy_core::import::parse_input(input) {
                    Ok(profiles) => {
                        let ids: Vec<_> = profiles.iter().map(|p| p.id).collect();
                        let mut db = self.db.lock().await;
                        for profile in profiles {
                            if !db.profiles.iter().any(|existing| {
                                existing.server == profile.server
                                    && existing.port == profile.port
                                    && existing.fields == profile.fields
                            }) {
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
                let id = p.id;
                if self.db.lock().await.profiles.iter().any(|existing| {
                    existing.server == p.server
                        && existing.port == p.port
                        && existing.fields == p.fields
                }) {
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
                self.db.lock().await.profiles.retain(|p| Some(p.id) != id);
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
            "settings.get" => {
                serde_json::to_value(&self.db.lock().await.settings).unwrap_or_default()
            }
            "settings.update" => {
                let value = params.get("settings").cloned().unwrap_or_default();
                match serde_json::from_value::<Settings>(value) {
                    Ok(s) => {
                        if s.local_port == 0 {
                            return serde_json::json!({"error":"local port must be between 1 and 65535"});
                        }
                        if self.connected.lock().await.is_some() {
                            return serde_json::json!({"error":"disconnect before changing connection settings"});
                        }
                        if s.kill_switch {
                            return serde_json::json!({"error":"kill switch requires the privileged helper and is not enabled in this build"});
                        }
                        self.db.lock().await.settings = s;
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
                *existing = sub;
                drop(db);
                let _ = self.save().await;
                serde_json::json!({"ok":true})
            }
            "subscription.delete" => {
                let id = params["subscriptionId"]
                    .as_str()
                    .and_then(|s| uuid::Uuid::parse_str(s).ok());
                let mut db = self.db.lock().await;
                db.subscriptions.retain(|s| Some(s.id) != id);
                db.profiles.retain(|p| p.source_id != id);
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
                let url = {
                    let db = self.db.lock().await;
                    match db.subscriptions.iter().find(|s| s.id == id) {
                        Some(s) if s.enabled => s.url.clone(),
                        Some(_) => return serde_json::json!({"error":"subscription is disabled"}),
                        None => return serde_json::json!({"error":"subscription not found"}),
                    }
                };
                let output = match tokio::process::Command::new("curl")
                    .args(["-fsSL", "--max-time", "20"])
                    .arg(&url)
                    .output()
                    .await
                {
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
                let body = String::from_utf8_lossy(&output.stdout);
                let parsed: Vec<Profile> = rayarchy_core::import::parse_input(&body)
                    .unwrap_or_default()
                    .into_iter()
                    .map(|mut p| {
                        p.source_id = Some(id);
                        p
                    })
                    .collect();
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
        db.test_history.push(result);
        if db.test_history.len() > 100 {
            db.test_history.remove(0);
        }
        drop(db);
        let _ = self.save().await;
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
}
