use hbb_common::{config::Config, log};
use serde_json::{json, Value};
use std::{
    io::{BufRead, BufReader, Read, Write},
    net::{IpAddr, TcpListener, TcpStream},
    path::PathBuf,
    process::Command,
    sync::Mutex,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

pub const HELP_PORT: u16 = 21120;
const MAX_NOTE: usize = 280;
const HOST_TAG: &str = "tag:hand-host";

lazy_static::lazy_static! {
    static ref FILE_LOCK: Mutex<()> = Mutex::new(());
}

fn requests_path() -> PathBuf {
    Config::path("hand_requests.json")
}

fn load() -> Vec<Value> {
    std::fs::read_to_string(requests_path())
        .ok()
        .and_then(|s| serde_json::from_str::<Vec<Value>>(&s).ok())
        .unwrap_or_default()
}

fn save(list: &[Value]) {
    if let Ok(text) = serde_json::to_string(list) {
        if let Err(e) = std::fs::write(requests_path(), text) {
            log::error!("Hand: failed to save help requests: {}", e);
        }
    }
}

pub fn requests_json() -> String {
    let _guard = FILE_LOCK.lock();
    Value::Array(load()).to_string()
}

pub fn clear(ip: &str) {
    let _guard = FILE_LOCK.lock();
    let mut list = load();
    let before = list.len();
    list.retain(|r| r["ip"].as_str() != Some(ip));
    if list.len() != before {
        save(&list);
    }
}

fn upsert(ip: &str, note: &str) {
    let _guard = FILE_LOCK.lock();
    let mut list = load();
    list.retain(|r| r["ip"].as_str() != Some(ip));
    let at = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or_default();
    list.push(json!({ "ip": ip, "note": note, "at": at }));
    save(&list);
}

fn tailscale_status() -> Option<Value> {
    let exe = std::env::var("ProgramFiles")
        .map(|p| format!("{p}\\Tailscale\\tailscale.exe"))
        .unwrap_or_else(|_| "tailscale".to_owned());
    let mut cmd = Command::new(exe);
    cmd.args(["status", "--json"]);
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(0x0800_0000);
    }
    let out = cmd.output().ok()?;
    if !out.status.success() {
        return None;
    }
    serde_json::from_slice(&out.stdout).ok()
}

fn self_is_host(status: &Value) -> bool {
    status["Self"]["Tags"]
        .as_array()
        .map_or(false, |tags| tags.iter().any(|t| t.as_str() == Some(HOST_TAG)))
}

fn display_name(status: Option<&Value>, ip: &str) -> String {
    let Some(peers) = status.and_then(|s| s["Peer"].as_object()) else {
        return ip.to_owned();
    };
    for peer in peers.values() {
        let has_ip = peer["TailscaleIPs"]
            .as_array()
            .map_or(false, |ips| ips.iter().any(|i| i.as_str() == Some(ip)));
        if !has_ip {
            continue;
        }
        let host = peer["HostName"].as_str().unwrap_or(ip);
        let Some(rest) = host.strip_prefix("hand-") else {
            return host.to_owned();
        };
        return rest
            .split('-')
            .filter(|w| !w.is_empty())
            .map(|w| {
                let mut c = w.chars();
                match c.next() {
                    Some(f) => f.to_uppercase().collect::<String>() + c.as_str(),
                    None => String::new(),
                }
            })
            .collect::<Vec<_>>()
            .join(" ");
    }
    ip.to_owned()
}

fn is_tailnet(ip: &IpAddr) -> bool {
    match ip {
        IpAddr::V4(v4) => {
            let o = v4.octets();
            o[0] == 100 && (o[1] & 0xC0) == 64
        }
        IpAddr::V6(_) => false,
    }
}

fn notify(name: &str, note: &str) {
    #[cfg(windows)]
    {
        use tauri_winrt_notification::{Duration as ToastDuration, Sound, Toast};
        let body = if note.is_empty() {
            "Open H&nd to help."
        } else {
            note
        };
        if let Err(e) = Toast::new(Toast::POWERSHELL_APP_ID)
            .title(&format!("{name} needs a hand"))
            .text1(body)
            .sound(Some(Sound::Default))
            .duration(ToastDuration::Long)
            .show()
        {
            log::error!("Hand: notification failed: {:?}", e);
        }
    }
    #[cfg(not(windows))]
    let _ = (name, note);
}

fn handle(stream: TcpStream) {
    let Ok(peer) = stream.peer_addr() else {
        return;
    };
    if !is_tailnet(&peer.ip()) {
        return;
    }
    let ip = peer.ip().to_string();
    stream.set_read_timeout(Some(Duration::from_secs(5))).ok();
    let mut line = String::new();
    let mut reader = BufReader::new((&stream).take(4096));
    if reader.read_line(&mut line).is_err() {
        return;
    }
    let Ok(msg) = serde_json::from_str::<Value>(line.trim()) else {
        return;
    };
    match msg["type"].as_str() {
        Some("help") => {
            let note: String = msg["note"]
                .as_str()
                .unwrap_or_default()
                .trim()
                .chars()
                .take(MAX_NOTE)
                .collect();
            upsert(&ip, &note);
            let status = tailscale_status();
            notify(&display_name(status.as_ref(), &ip), &note);
        }
        Some("cancel") => clear(&ip),
        _ => return,
    }
    (&stream).write_all(b"ok\n").ok();
}

pub fn start_listener() {
    std::thread::spawn(|| loop {
        let host = tailscale_status().map_or(true, |s| self_is_host(&s));
        if host {
            std::thread::sleep(Duration::from_secs(60));
            continue;
        }
        match TcpListener::bind(("0.0.0.0", HELP_PORT)) {
            Ok(listener) => {
                log::info!("Hand: listening for help requests on {}", HELP_PORT);
                for stream in listener.incoming().flatten() {
                    std::thread::spawn(move || handle(stream));
                }
            }
            Err(e) => {
                log::warn!("Hand: help listener unavailable: {}", e);
                std::thread::sleep(Duration::from_secs(30));
            }
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn staff_names_are_readable() {
        let status = json!({"Peer": {"a": {"TailscaleIPs": ["100.64.1.2"], "HostName": "hand-amaka-accounts"}}});
        assert_eq!(display_name(Some(&status), "100.64.1.2"), "Amaka Accounts");
        assert_eq!(display_name(Some(&status), "100.64.9.9"), "100.64.9.9");
    }

    #[test]
    fn only_tailnet_addresses_are_accepted() {
        assert!(is_tailnet(&"100.103.37.77".parse().unwrap()));
        assert!(!is_tailnet(&"192.168.1.5".parse().unwrap()));
    }
}
