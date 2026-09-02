use std::process::Command;

#[derive(Clone, Debug)]
pub struct Backup {
    pub mode: String,
    pub http_host: String,
    pub http_port: String,
    pub socks_host: String,
    pub socks_port: String,
    pub ignore_hosts: String,
}

fn get(schema: &str, key: &str) -> String {
    Command::new("gsettings")
        .args(["get", schema, key])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| {
            String::from_utf8_lossy(&o.stdout)
                .trim()
                .trim_matches('\'')
                .to_string()
        })
        .unwrap_or_default()
}
fn set(schema: &str, key: &str, value: &str) -> Result<(), String> {
    let out = Command::new("gsettings")
        .args(["set", schema, key, value])
        .output()
        .map_err(|e| e.to_string())?;
    if out.status.success() {
        Ok(())
    } else {
        Err(format!("gsettings failed for {schema} {key}"))
    }
}

pub fn apply(host: &str, port: u16) -> Result<Backup, String> {
    let backup = Backup {
        mode: get("org.gnome.system.proxy", "mode"),
        http_host: get("org.gnome.system.proxy.http", "host"),
        http_port: get("org.gnome.system.proxy.http", "port"),
        socks_host: get("org.gnome.system.proxy.socks", "host"),
        socks_port: get("org.gnome.system.proxy.socks", "port"),
        ignore_hosts: get("org.gnome.system.proxy", "ignore-hosts"),
    };
    set("org.gnome.system.proxy.http", "host", host)?;
    set("org.gnome.system.proxy.http", "port", &port.to_string())?;
    set("org.gnome.system.proxy.socks", "host", host)?;
    set("org.gnome.system.proxy.socks", "port", &port.to_string())?;
    set("org.gnome.system.proxy", "ignore-hosts", "[]")?;
    set("org.gnome.system.proxy", "mode", "manual")?;
    Ok(backup)
}
pub fn restore(backup: &Backup) -> Result<(), String> {
    set("org.gnome.system.proxy.http", "host", &backup.http_host)?;
    set("org.gnome.system.proxy.http", "port", &backup.http_port)?;
    set("org.gnome.system.proxy.socks", "host", &backup.socks_host)?;
    set("org.gnome.system.proxy.socks", "port", &backup.socks_port)?;
    set(
        "org.gnome.system.proxy",
        "ignore-hosts",
        &backup.ignore_hosts,
    )?;
    set("org.gnome.system.proxy", "mode", &backup.mode)
}
