use rayarchy_core::{Profile, Settings, Subscription};
use std::{path::PathBuf, sync::Arc};
use tokio::sync::Mutex;
pub mod server;

#[derive(Default, serde::Serialize, serde::Deserialize)]
struct Database {
    profiles: Vec<Profile>,
    subscriptions: Vec<Subscription>,
    settings: Settings,
}

pub struct Daemon {
    db: Mutex<Database>,
    path: PathBuf,
    connected: Mutex<Option<uuid::Uuid>>,
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
    pub async fn dispatch(&self, method: &str, params: serde_json::Value) -> serde_json::Value {
        match method {
            "system.ping" => serde_json::json!({"ok":true}),
            "system.status" => {
                serde_json::json!({"connected": self.connected.lock().await.is_some()})
            }
            "profile.list" => {
                serde_json::to_value(&self.db.lock().await.profiles).unwrap_or_default()
            }
            "import.preview" => {
                let input = params["input"].as_str().unwrap_or("");
                match rayarchy_core::import::parse_uri(input) {
                    Ok(profile) => serde_json::json!({"profiles":[profile],"errors":[]}),
                    Err(error) => serde_json::json!({"profiles":[],"errors":[error]}),
                }
            }
            "import.commit" => {
                let input = params["input"].as_str().unwrap_or("");
                match rayarchy_core::import::parse_uri(input) {
                    Ok(profile) => {
                        let id = profile.id;
                        self.db.lock().await.profiles.push(profile);
                        let _ = self.save().await;
                        serde_json::json!({"profileIds":[id]})
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
                    p.name = format!("{} profile", format!("{:?}", p.protocol));
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
            "settings.get" => {
                serde_json::to_value(&self.db.lock().await.settings).unwrap_or_default()
            }
            "settings.update" => {
                let value = params.get("settings").cloned().unwrap_or_default();
                match serde_json::from_value(value) {
                    Ok(s) => {
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
            _ => serde_json::json!({"error":"method not found"}),
        }
    }
}
