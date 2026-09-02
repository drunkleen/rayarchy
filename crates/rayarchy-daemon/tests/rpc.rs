use rayarchy_daemon::{server, Daemon};
use serde_json::Value;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::UnixStream;

async fn call(stream: &mut UnixStream, request: Value) -> Value {
    stream
        .write_all(request.to_string().as_bytes())
        .await
        .unwrap();
    stream.write_all(b"\n").await.unwrap();
    let mut line = String::new();
    BufReader::new(stream).read_line(&mut line).await.unwrap();
    serde_json::from_str(&line).unwrap()
}

#[tokio::test]
async fn rpc_server_roundtrips_core_workflows() {
    let root = std::env::temp_dir().join(format!("rayarchy-rpc-{}", uuid::Uuid::new_v4()));
    let socket = root.join("rayarchy.sock");
    let state = root.join("state.json");
    let daemon = Daemon::new(state).unwrap();
    let task = tokio::spawn(server::serve(daemon, socket.clone()));
    for _ in 0..20 {
        if socket.exists() {
            break;
        }
        tokio::time::sleep(std::time::Duration::from_millis(10)).await;
    }
    let mut stream = UnixStream::connect(&socket).await.unwrap();
    let ping = call(
        &mut stream,
        serde_json::json!({"jsonrpc":"2.0","id":1,"method":"system.ping","params":{}}),
    )
    .await;
    assert_eq!(ping["result"]["ok"], true);
    let profile = serde_json::json!({"name":"RPC","protocol":"vless","server":"rpc.example","port":443,"fields":{}});
    let created = call(&mut stream, serde_json::json!({"jsonrpc":"2.0","id":2,"method":"profile.create","params":{"profile":profile}})).await;
    let profile_id = created["result"]["profileId"].as_str().unwrap();
    let listed = call(
        &mut stream,
        serde_json::json!({"jsonrpc":"2.0","id":3,"method":"profile.list","params":{}}),
    )
    .await;
    assert_eq!(listed["result"].as_array().unwrap().len(), 1);
    let schema = call(&mut stream, serde_json::json!({"jsonrpc":"2.0","id":4,"method":"profile.schema","params":{"protocol":"vless"}})).await;
    assert!(schema["result"]["fields"]
        .as_array()
        .unwrap()
        .iter()
        .any(|v| v == "user"));
    let settings = call(&mut stream, serde_json::json!({"jsonrpc":"2.0","id":5,"method":"settings.update","params":{"settings":{"connectionMode":"local","preferredCore":"auto","localPort":1080,"killSwitch":false,"dnsLeakProtection":true,"lanBypass":true}}})).await;
    assert_eq!(settings["result"]["ok"], true);
    let diagnostics = call(
        &mut stream,
        serde_json::json!({"jsonrpc":"2.0","id":6,"method":"system.diagnostics","params":{}}),
    )
    .await;
    assert!(diagnostics["result"]["cores"].is_object());
    let bulk = call(
        &mut stream,
        serde_json::json!({"jsonrpc":"2.0","id":7,"method":"test.bulk","params":{"profileIds":[]}}),
    )
    .await;
    assert_eq!(bulk["result"]["cancelled"], false);
    let cancel = call(
        &mut stream,
        serde_json::json!({"jsonrpc":"2.0","id":8,"method":"test.bulk.cancel","params":{}}),
    )
    .await;
    assert_eq!(cancel["result"]["ok"], true);
    let deleted = call(&mut stream, serde_json::json!({"jsonrpc":"2.0","id":9,"method":"profile.delete","params":{"profileId":profile_id}})).await;
    assert_eq!(deleted["result"]["ok"], true);
    task.abort();
    let _ = tokio::fs::remove_dir_all(root).await;
}
