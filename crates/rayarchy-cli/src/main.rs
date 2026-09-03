use rayarchy_daemon::Daemon;
use std::{env, path::PathBuf, sync::Arc};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::UnixStream;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let base = env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp"));
    let daemon = Client::new(base.join("rayarchy/state.json"))?;
    let mut args = env::args().skip(1);
    match args.next().as_deref().unwrap_or("status") {
        "status" => print_json(
            daemon
                .dispatch("system.status", serde_json::json!({}))
                .await,
        ),
        "profiles" => print_json(daemon.dispatch("profile.list", serde_json::json!({})).await),
        "connect" => {
            let id = args.next().unwrap_or_default();
            print_json(
                daemon
                    .dispatch("profile.connect", serde_json::json!({"profileId":id}))
                    .await,
            );
        }
        "disconnect" => print_json(
            daemon
                .dispatch("profile.disconnect", serde_json::json!({}))
                .await,
        ),
        "set-default" => {
            let id = args.next().unwrap_or_default();
            print_json(
                daemon
                    .dispatch("profile.setDefault", serde_json::json!({"profileId":id}))
                    .await,
            );
        }
        "default" => print_json(
            daemon
                .dispatch("profile.default", serde_json::json!({}))
                .await,
        ),
        "reload" => print_json(
            daemon
                .dispatch("system.reload", serde_json::json!({}))
                .await,
        ),
        "ui-get" => print_json(daemon.dispatch("ui.get", serde_json::json!({})).await),
        "ip" => print_json(daemon.dispatch("test.ip", serde_json::json!({})).await),
        "history" => print_json(daemon.dispatch("test.history", serde_json::json!({})).await),
        "bulk" => {
            let ids = args.map(serde_json::Value::String).collect::<Vec<_>>();
            print_json(
                daemon
                    .dispatch("test.bulk", serde_json::json!({"profileIds":ids}))
                    .await,
            );
        }
        "bulk-proxy" => {
            let ids = args.map(serde_json::Value::String).collect::<Vec<_>>();
            let mut result = daemon
                .dispatch("test.bulk.proxy", serde_json::json!({"profileIds":ids}))
                .await;
            if let Some(rows) = result.get("results").and_then(|v| v.as_array()) {
                let passing = rows
                    .iter()
                    .filter(|row| row["ok"].as_bool() == Some(true))
                    .count();
                let fastest = rows
                    .iter()
                    .filter(|row| row["ok"].as_bool() == Some(true))
                    .min_by_key(|row| row["latencyMs"].as_u64().unwrap_or(u64::MAX));
                result["summary"] = serde_json::json!({"total":rows.len(),"passing":passing,"failing":rows.len()-passing,"fastestProfileId":fastest.and_then(|row| row["profileId"].clone().as_str().map(str::to_owned))});
            }
            print_json(result);
        }
        "best" => {
            let connect = args.any(|arg| arg == "--connect");
            let profiles = daemon.dispatch("profile.list", serde_json::json!({})).await;
            let best = profiles.as_array().and_then(|rows| {
                rows.iter()
                    .filter(|row| row["lastTest"]["ok"].as_bool() == Some(true))
                    .min_by_key(|row| row["lastTest"]["latencyMs"].as_u64().unwrap_or(u64::MAX))
            });
            let Some(best) = best else {
                print_json(serde_json::json!({"error":"no recently verified profile"}));
                return Ok(());
            };
            if connect {
                let connection = daemon
                    .dispatch(
                        "profile.connect",
                        serde_json::json!({"profileId":best["id"]}),
                    )
                    .await;
                print_json(serde_json::json!({"profile":best,"connection":connection}));
            } else {
                print_json(best.clone());
            }
        }
        "diagnostics" => {
            print_json(
                daemon
                    .dispatch("system.diagnostics", serde_json::json!({}))
                    .await,
            );
        }
        "validate" => {
            let id = args.next().unwrap_or_default();
            print_json(
                daemon
                    .dispatch("core.validate", serde_json::json!({"profileId":id}))
                    .await,
            );
        }
        "import" => {
            let input = args.collect::<Vec<_>>().join(" ");
            print_json(
                daemon
                    .dispatch("import.commit", serde_json::json!({"input":input}))
                    .await,
            );
        }
        "help" | "--help" | "-h" => {
            println!("rayarchy [status|profiles|connect ID|disconnect|set-default ID|default|reload|ip|history|bulk ID...|bulk-proxy ID...|best [--connect]|diagnostics|validate ID|import URI|ui-get]")
        }
        command => {
            eprintln!("unknown command: {command}");
            std::process::exit(2);
        }
    }
    Ok(())
}

fn print_json(value: serde_json::Value) {
    println!(
        "{}",
        serde_json::to_string_pretty(&value).unwrap_or_else(|_| value.to_string())
    );
}

struct Client {
    socket: PathBuf,
    fallback: Arc<Daemon>,
}

impl Client {
    fn new(state: PathBuf) -> anyhow::Result<Self> {
        let runtime = env::var_os("XDG_RUNTIME_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("/tmp"));
        Ok(Self {
            socket: runtime.join("rayarchy/rayarchy.sock"),
            fallback: Daemon::new(state)?,
        })
    }

    async fn dispatch(&self, method: &str, params: serde_json::Value) -> serde_json::Value {
        if let Ok(stream) = UnixStream::connect(&self.socket).await {
            let (read, mut write) = stream.into_split();
            let request =
                serde_json::json!({"jsonrpc":"2.0","id":1,"method":method,"params":params});
            if write
                .write_all(format!("{}\n", request).as_bytes())
                .await
                .is_ok()
            {
                let mut lines = BufReader::new(read).lines();
                if let Ok(Some(line)) = lines.next_line().await {
                    if let Ok(response) = serde_json::from_str::<serde_json::Value>(&line) {
                        if let Some(error) = response.get("error") {
                            return serde_json::json!({"error":error["message"].clone()});
                        }
                        if let Some(result) = response.get("result") {
                            return result.clone();
                        }
                    }
                }
            }
        }
        self.fallback.dispatch(method, params).await
    }
}
