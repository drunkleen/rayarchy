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
        "import" => {
            let input = args.collect::<Vec<_>>().join(" ");
            print_json(
                daemon
                    .dispatch("import.commit", serde_json::json!({"input":input}))
                    .await,
            );
        }
        "help" | "--help" | "-h" => {
            println!("rayarchy [status|profiles|connect ID|disconnect|ip|history|import URI]")
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
