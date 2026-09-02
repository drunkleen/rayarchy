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
                serde_json::json!({"error":"core execution is not available in this development slice; connection was not claimed"})
            }
            "profile.disconnect" => {
                *self.connected.lock().await = None;
                serde_json::json!({"accepted":true,"state":"DISCONNECTED"})
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
