use rayarchy_core::{Profile, RoutingRule, Settings, Subscription};
use std::{path::PathBuf, sync::Arc};
use tokio::sync::Mutex;
pub mod configgen;
pub mod server;
pub mod sysproxy;

fn command_exists(name: &str) -> bool {
    std::env::var_os("PATH")
        .map(|path| std::env::split_paths(&path).any(|dir| dir.join(name).is_file()))
        .unwrap_or(false)
}

#[derive(Default, serde::Serialize, serde::Deserialize)]
struct Database {
    profiles: Vec<Profile>,
    subscriptions: Vec<Subscription>,
    routing: Vec<RoutingRule>,
    #[serde(default)]
    test_history: Vec<serde_json::Value>,
    settings: Settings,
}

pub struct Daemon {
    db: Mutex<Database>,
    path: PathBuf,
    connected: Mutex<Option<uuid::Uuid>>,
    process: Mutex<Option<tokio::process::Child>>,
    config_path: PathBuf,
    proxy_backup: Mutex<Option<sysproxy::Backup>>,
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
            config_path: std::env::temp_dir().join("rayarchy/config.json"),
            proxy_backup: Mutex::new(None),
        }))
    }
    async fn save(&self) -> anyhow::Result<()> {
        let db = self.db.lock().await;
        let bytes = serde_json::to_vec_pretty(&*db)?;
        if let Some(p) = self.path.parent() {
            std::fs::create_dir_all(p)?;
        }
        std::fs::write(&self.path, bytes)?;
        Ok(())
    }

    async fn connect_profile(&self, id: uuid::Uuid) -> Result<(), String> {
        let (profile, settings) = {
            let db = self.db.lock().await;
            (
                db.profiles
                    .iter()
                    .find(|p| p.id == id)
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
        let config = configgen::build(&profile, core, "127.0.0.1", settings.local_port);
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
        let child = tokio::process::Command::new(bin)
            .args(["run", "-c"])
            .arg(&self.config_path)
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn()
            .map_err(|e| format!("could not start {bin}: {e}"))?;
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
        Ok(())
    }

    async fn disconnect_profile(&self) -> Result<(), String> {
        *self.connected.lock().await = None;
        if let Some(backup) = self.proxy_backup.lock().await.take() {
            let _ = sysproxy::restore(&backup);
        }
        if let Some(mut child) = self.process.lock().await.take() {
            let _ = child.kill().await;
        }
        let _ = std::fs::remove_file(&self.config_path);
        Ok(())
    }
    pub async fn dispatch(&self, method: &str, params: serde_json::Value) -> serde_json::Value {
        match method {
            "system.ping" => serde_json::json!({"ok":true}),
            "system.status" => {
                serde_json::json!({"connected": self.connected.lock().await.is_some(), "cores": {"xray": command_exists("xray"), "singBox": command_exists("sing-box")}})
            }
            "system.capabilities" => {
                serde_json::json!({"xray":command_exists("xray"),"singBox":command_exists("sing-box"),"systemProxy":true,"tun":false})
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
            "routing.list" => {
                serde_json::to_value(&self.db.lock().await.routing).unwrap_or_default()
            }
            "routing.create" => {
                let rule: RoutingRule = match serde_json::from_value(params["rule"].clone()) {
                    Ok(v) => v,
                    Err(e) => return serde_json::json!({"error":e.to_string()}),
                };
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
                serde_json::to_value(&self.db.lock().await.profiles).unwrap_or_default()
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
            "profile.export" => {
                let id = params["profileId"]
                    .as_str()
                    .and_then(|s| uuid::Uuid::parse_str(s).ok());
                self.db.lock().await.profiles.iter().find(|p| Some(p.id) == id)
                    .map(|p| serde_json::json!({"profileId":p.id,"name":p.name,"payload":p.raw.clone().unwrap_or_else(|| serde_json::to_string(p).unwrap_or_default())}))
                    .unwrap_or_else(|| serde_json::json!({"error":"profile not found"}))
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
                        self.db.lock().await.profiles.extend(profiles);
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
                let id = p.id;
                self.db.lock().await.profiles.push(p);
                let _ = self.save().await;
                serde_json::json!({"profileId":id})
            }
            "profile.delete" => {
                let id = params["profileId"]
                    .as_str()
                    .and_then(|s| uuid::Uuid::parse_str(s).ok());
                self.db.lock().await.profiles.retain(|p| Some(p.id) != id);
                let _ = self.save().await;
                serde_json::json!({"ok":true})
            }
            "profile.update" => {
                let p: Profile = match serde_json::from_value(params["profile"].clone()) {
                    Ok(v) => v,
                    Err(e) => return serde_json::json!({"error":e.to_string()}),
                };
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
                        serde_json::json!({"accepted":true,"state":"CONNECTED","profileId":id})
                    }
                    Err(error) => serde_json::json!({"error":error}),
                }
            }
            "profile.disconnect" => match self.disconnect_profile().await {
                Ok(()) => serde_json::json!({"accepted":true,"state":"DISCONNECTED"}),
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
                    Ok(_) => return serde_json::json!({"error":"subscription download failed"}),
                    Err(e) => return serde_json::json!({"error":e.to_string()}),
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
                    return serde_json::json!({"error":"subscription contained no supported profiles"});
                }
                let count = parsed.len();
                let mut db = self.db.lock().await;
                db.profiles.retain(|p| p.source_id != Some(id));
                db.profiles.extend(parsed);
                drop(db);
                let _ = self.save().await;
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
}
