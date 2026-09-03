use rayarchy_daemon::Daemon;
use std::{env, path::PathBuf};
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    if env::args().nth(1).as_deref() == Some("--version")
        || env::args().nth(1).as_deref() == Some("-V")
    {
        println!(
            "rayarchy-daemon {}",
            option_env!("RAYARCHY_VERSION").unwrap_or(env!("CARGO_PKG_VERSION"))
        );
        return Ok(());
    }
    let base = env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".local/share")))
        .unwrap_or_else(|| PathBuf::from("/tmp"));
    let d = Daemon::new(base.join("rayarchy/state.json"))?;
    let runtime = env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp"));
    println!("rayarchy daemon ready");
    d.spawn_subscription_scheduler();
    rayarchy_daemon::server::serve(d, runtime.join("rayarchy/rayarchy.sock")).await
}
