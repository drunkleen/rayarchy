use std::path::PathBuf;
use std::process::Command;

// Rayarchy privileged helper. Runs as root via `pkexec` and is narrowly
// scoped to starting/stopping the sing-box TUN core and applying/removing the
// optional kill-switch firewall rules. It only ever runs `sing-box run -c`
// against a config file path the daemon generated; it accepts no other
// commands from its arguments.
//
// The pidfile doubles as a small JSON state file so `stop` can tear down both
// the child core and this helper and remove the firewall rules without
// depending on signal handlers inside this process.

const TUN_IFACE: &str = "ray0";
const KS_CHAIN: &str = "RAYARCHY_KS";

#[derive(serde::Deserialize)]
struct State {
    helper_pid: u32,
    child_pid: u32,
    killswitch: bool,
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let result = match args.get(1).map(String::as_str) {
        Some("start") => start(&args[2..]),
        Some("stop") => stop(&args[2..]),
        Some("status") => status(&args[2..]),
        _ => {
            eprintln!("usage: rayarchy-helper <start tun|stop|status> --config <path> --pidfile <path> [--killswitch]");
            std::process::exit(2);
        }
    };
    if let Err(error) = result {
        eprintln!("rayarchy-helper: {error}");
        std::process::exit(1);
    }
}

fn flag_value(args: &[String], name: &str) -> Option<String> {
    let mut iter = args.iter();
    while let Some(arg) = iter.next() {
        if arg == name {
            if let Some(value) = iter.next() {
                return Some(value.clone());
            }
        }
    }
    None
}

fn has_flag(args: &[String], name: &str) -> bool {
    args.iter().any(|arg| arg == name)
}

fn read_state(pidfile: &PathBuf) -> Option<State> {
    let bytes = std::fs::read(pidfile).ok()?;
    serde_json::from_slice(&bytes).ok()
}

fn kill(pid: u32) {
    let _ = Command::new("kill").arg(pid.to_string()).status();
}

fn pid_alive(pid: u32) -> bool {
    Command::new("kill")
        .args(["-0", &pid.to_string()])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn apply_killswitch_rules() -> Result<(), String> {
    run_iptables(&["-N", KS_CHAIN])?;
    // Chain may already exist from a stale run; ignore that error and flush.
    let _ = run_iptables(&["-F", KS_CHAIN]);
    run_iptables(&["-A", KS_CHAIN, "-o", "lo", "-j", "ACCEPT"])?;
    run_iptables(&[
        "-A",
        KS_CHAIN,
        "-m",
        "state",
        "--state",
        "ESTABLISHED,RELATED",
        "-j",
        "ACCEPT",
    ])?;
    run_iptables(&["-A", KS_CHAIN, "-o", TUN_IFACE, "-j", "ACCEPT"])?;
    run_iptables(&["-A", KS_CHAIN, "-j", "REJECT"])?;
    run_iptables(&["-I", "OUTPUT", "-j", KS_CHAIN])
}

fn remove_killswitch_rules() {
    let _ = run_iptables(&["-D", "OUTPUT", "-j", KS_CHAIN]);
    let _ = run_iptables(&["-F", KS_CHAIN]);
    let _ = run_iptables(&["-X", KS_CHAIN]);
}

fn run_iptables(args: &[&str]) -> Result<(), String> {
    let output = Command::new("iptables")
        .args(args)
        .output()
        .map_err(|e| format!("iptables unavailable: {e}"))?;
    if output.status.success() {
        Ok(())
    } else {
        Err(String::from_utf8_lossy(&output.stderr).trim().to_string())
    }
}

fn start(args: &[String]) -> Result<(), String> {
    let config = flag_value(args, "--config").ok_or("missing --config")?;
    let pidfile = PathBuf::from(flag_value(args, "--pidfile").ok_or("missing --pidfile")?);
    let killswitch = has_flag(args, "--killswitch");

    // Clean up any stale run first so a crash never leaves the firewall up
    // without a live core.
    if let Some(state) = read_state(&pidfile) {
        if state.killswitch {
            remove_killswitch_rules();
        }
        kill(state.child_pid);
        kill(state.helper_pid);
    }
    let _ = std::fs::remove_file(&pidfile);

    let config_bytes = std::fs::read(&config).map_err(|e| format!("cannot read config: {e}"))?;
    let parsed: serde_json::Value = serde_json::from_slice(&config_bytes)
        .map_err(|e| format!("config is not valid JSON: {e}"))?;
    if parsed.get("inbounds").is_none() {
        return Err("config must contain inbounds".into());
    }

    let helper_pid = std::process::id();
    let child = Command::new("sing-box")
        .args(["run", "-c", &config])
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
        .map_err(|e| format!("could not start sing-box: {e}"))?;
    let child_pid = child.id();

    let state = serde_json::json!({
        "helper_pid": helper_pid,
        "child_pid": child_pid,
        "killswitch": killswitch,
    });
    std::fs::write(&pidfile, serde_json::to_vec(&state).unwrap_or_default())
        .map_err(|e| format!("could not write state: {e}"))?;

    if killswitch {
        apply_killswitch_rules().map_err(|e| {
            let _ = Command::new("kill").arg(child_pid.to_string()).status();
            format!("kill-switch setup failed: {e}")
        })?;
    }

    // Wait for the core; on exit tear down rules and state.
    let mut child = child;
    let _ = child.wait();
    if killswitch {
        remove_killswitch_rules();
    }
    let _ = std::fs::remove_file(&pidfile);
    Ok(())
}

fn stop(args: &[String]) -> Result<(), String> {
    let pidfile = PathBuf::from(flag_value(args, "--pidfile").ok_or("missing --pidfile")?);
    if let Some(state) = read_state(&pidfile) {
        kill(state.child_pid);
        kill(state.helper_pid);
        if state.killswitch {
            remove_killswitch_rules();
        }
    }
    let _ = std::fs::remove_file(&pidfile);
    Ok(())
}

fn status(args: &[String]) -> Result<(), String> {
    let pidfile = PathBuf::from(flag_value(args, "--pidfile").ok_or("missing --pidfile")?);
    match read_state(&pidfile) {
        Some(state) if pid_alive(state.child_pid) => {
            println!("running");
            Ok(())
        }
        _ => {
            println!("stopped");
            Ok(())
        }
    }
}
