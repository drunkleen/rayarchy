use rayarchy_daemon::Daemon;
use std::{env, path::PathBuf};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let base = env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp"));
    let daemon = Daemon::new(base.join("rayarchy/state.json"))?;
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
            let profiles = daemon.dispatch("profile.list", serde_json::json!({})).await;
            let best = profiles.as_array().and_then(|rows| {
                rows.iter()
                    .filter(|row| row["lastTest"]["ok"].as_bool() == Some(true))
                    .min_by_key(|row| row["lastTest"]["latencyMs"].as_u64().unwrap_or(u64::MAX))
            });
            print_json(
                best.cloned()
                    .unwrap_or_else(|| serde_json::json!({"error":"no recently verified profile"})),
            );
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
            println!("rayarchy [status|profiles|connect ID|disconnect|ip|history|bulk ID...|bulk-proxy ID...|best|diagnostics|validate ID|import URI]")
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
