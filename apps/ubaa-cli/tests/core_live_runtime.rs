use std::io::Write as _;
use std::process::{Command, Stdio};

fn temp_dir(label: &str) -> std::path::PathBuf {
    let path = std::env::temp_dir().join(format!("ubaa-core-live-{label}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&path);
    std::fs::create_dir_all(&path).unwrap();
    path
}

fn core_live_binary() -> std::path::PathBuf {
    std::env::current_exe()
        .expect("test executable path is available")
        .parent()
        .and_then(std::path::Path::parent)
        .expect("workspace target directory is available")
        .join("core-live")
}

#[test]
fn core_live_rejects_auto_without_reading_credentials() {
    let config = temp_dir("auto");
    let mut child = Command::new(core_live_binary())
        .args([
            "--route",
            "auto",
            "--feature",
            "all",
            "--config-dir",
            config.to_str().unwrap(),
            "--date",
            "2026-08-31",
            "--username-stdin",
            "--password-stdin",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .take()
        .unwrap()
        .write_all(b"secret-user\nsecret-pass\n")
        .unwrap();
    let output = child.wait_with_output().unwrap();

    assert_eq!(output.status.code(), Some(2));
    assert!(String::from_utf8_lossy(&output.stdout).is_empty());
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("只允许 route=direct 或 route=webvpn"));
    assert!(!stderr.contains("secret-user"));
    assert!(!stderr.contains("secret-pass"));
    assert!(!config.join("session.json").exists());
    assert!(!config.join(".session.lock").exists());
    let _ = std::fs::remove_dir_all(config);
}

#[test]
fn core_live_rejects_incomplete_stdin_without_session_material() {
    let config = temp_dir("missing-credentials");
    let mut child = Command::new(core_live_binary())
        .args([
            "--route",
            "direct",
            "--feature",
            "auth",
            "--config-dir",
            config.to_str().unwrap(),
            "--date",
            "2026-08-31",
            "--username-stdin",
            "--password-stdin",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .take()
        .unwrap()
        .write_all(b"only-user\n")
        .unwrap();
    let output = child.wait_with_output().unwrap();

    assert_eq!(output.status.code(), Some(5));
    assert!(String::from_utf8_lossy(&output.stdout).is_empty());
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("core-live 启动失败"));
    assert!(!stderr.contains("only-user"));
    assert!(!config.join("session.json").exists());
    assert!(!config.join(".session.lock").exists());
    let _ = std::fs::remove_dir_all(config);
}
