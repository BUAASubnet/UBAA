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
