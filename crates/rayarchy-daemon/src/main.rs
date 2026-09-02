use rayarchy_daemon::Daemon;
use std::{env, path::PathBuf};
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let base = env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp"));
    let d = Daemon::new(base.join("rayarchy/state.json"))?;
    println!("rayarchy daemon ready");
    let _ = d.dispatch("system.ping", serde_json::json!({})).await;
    tokio::signal::ctrl_c().await?;
    Ok(())
}
