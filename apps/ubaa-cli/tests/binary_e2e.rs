use std::io::Write as _;
use std::process::Command;

#[test]
fn binary_help_lists_required_commands_without_password_option() {
    let output = Command::new(env!("CARGO_BIN_EXE_ubaa"))
        .arg("auth")
        .arg("login")
        .arg("--help")
        .output()
        .unwrap();
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(output.status.success());
    assert!(stdout.contains("--password-stdin"));
    assert!(!stdout.contains("--password <"));
}

#[test]
fn binary_json_status_without_session_exits_three_with_parseable_error() {
    let config = std::env::temp_dir().join(format!("ubaa-cli-e2e-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&config);
    let output = Command::new(env!("CARGO_BIN_EXE_ubaa"))
        .arg("--json")
        .arg("--config-dir")
        .arg(&config)
        .arg("auth")
        .arg("status")
        .output()
        .unwrap();
    let value: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(output.status.code(), Some(3));
    assert_eq!(value["ok"], false);
    assert_eq!(value["error"]["code"], "authentication_required");
    assert!(output.stderr.is_empty());
    let _ = std::fs::remove_dir_all(config);
}

#[test]
fn binary_json_login_without_mode_or_session_exits_two_before_network() {
    let config = std::env::temp_dir().join(format!("ubaa-cli-mode-e2e-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&config);
    let mut child = Command::new(env!("CARGO_BIN_EXE_ubaa"))
        .arg("--json")
        .arg("--config-dir")
        .arg(&config)
        .arg("auth")
        .arg("login")
        .arg("--username")
        .arg("fixture-user")
        .arg("--password-stdin")
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .as_mut()
        .unwrap()
        .write_all(b"fixture-password\n")
        .unwrap();
    let output = child.wait_with_output().unwrap();
    let value: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(output.status.code(), Some(2));
    assert_eq!(value["error"]["code"], "invalid_input");
    assert!(output.stderr.is_empty());
    let _ = std::fs::remove_dir_all(config);
}

#[test]
fn binary_json_logout_without_session_has_no_invented_connection_mode() {
    let config = std::env::temp_dir().join(format!("ubaa-cli-logout-e2e-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&config);
    let output = Command::new(env!("CARGO_BIN_EXE_ubaa"))
        .arg("--json")
        .arg("--config-dir")
        .arg(&config)
        .arg("auth")
        .arg("logout")
        .output()
        .unwrap();
    let value: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert!(output.status.success());
    assert!(value["meta"].get("connectionMode").is_none());
    assert!(output.stderr.is_empty());
    let _ = std::fs::remove_dir_all(config);
}
