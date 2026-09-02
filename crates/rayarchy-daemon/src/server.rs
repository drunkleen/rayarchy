use crate::Daemon;
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};

pub async fn serve(daemon: Arc<Daemon>, socket: std::path::PathBuf) -> anyhow::Result<()> {
    if let Some(parent) = socket.parent() {
        tokio::fs::create_dir_all(parent).await?;
    }
    let _ = tokio::fs::remove_file(&socket).await;
    let listener = UnixListener::bind(&socket)?;
    loop {
        let (stream, _) = listener.accept().await?;
        let d = Arc::clone(&daemon);
        tokio::spawn(async move {
            let _ = handle(d, stream).await;
        });
    }
}

async fn handle(daemon: Arc<Daemon>, stream: UnixStream) -> anyhow::Result<()> {
    let (read, mut write) = stream.into_split();
    let mut lines = BufReader::new(read).lines();
    while let Some(line) = lines.next_line().await? {
        let request: serde_json::Value = match serde_json::from_str(&line) {
            Ok(v) => v,
            Err(_) => continue,
        };
        let id = request
            .get("id")
            .cloned()
            .unwrap_or(serde_json::Value::Null);
        let method = request.get("method").and_then(|v| v.as_str()).unwrap_or("");
        let result = daemon
            .dispatch(method, request.get("params").cloned().unwrap_or_default())
            .await;
        let response = if result.get("error").is_some() {
            serde_json::json!({"jsonrpc":"2.0","id":id,"error":{"code":-32600,"message":result["error"]}})
        } else {
            serde_json::json!({"jsonrpc":"2.0","id":id,"result":result})
        };
        write
            .write_all(serde_json::to_string(&response)?.as_bytes())
            .await?;
        write.write_all(b"\n").await?;
    }
    Ok(())
}
