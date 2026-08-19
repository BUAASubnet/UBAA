use std::io::Write as _;
use std::net::TcpListener;
use std::process::Command;
use std::time::{Duration, Instant};

use ubaa_core::domain::ConnectionMode;
use ubaa_core::session::{FileSessionStore, SessionSnapshot, SessionStore};

#[test]
fn repository_gate_include_uses_tracked_justfile_case() {
    let source = include_str!("binary_e2e.rs");
    let include = source
        .lines()
        .find(|line| line.trim_start().starts_with("let justfile = include_str!"))
        .expect("repository gate must embed the tracked justfile");

    assert_eq!(
        include.trim(),
        r#"let justfile = include_str!("../../../justfile");"#
    );
}

#[test]
fn repository_cargo_gates_lock_dependency_resolution() {
    let justfile = include_str!("../../../justfile");
    let repository_root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let tracked = Command::new("git")
        .current_dir(&repository_root)
        .args([
            "ls-files",
            "-z",
            "--",
            "justfile",
            "*.md",
            ".github/workflows/*",
            "scripts/*.sh",
        ])
        .output()
        .expect("git must enumerate tracked command sources");
    assert!(tracked.status.success());
    let tracked = String::from_utf8(tracked.stdout).expect("tracked paths must be UTF-8");

    assert!(
        justfile.contains("cargo metadata --locked --no-deps --format-version 1"),
        "justfile must validate Cargo.lock before running deterministic gates"
    );

    for source_name in tracked.split('\0').filter(|path| !path.is_empty()) {
        let source = std::fs::read_to_string(repository_root.join(source_name))
            .unwrap_or_else(|_| panic!("could not read tracked command source {source_name}"));
        for line in source.lines().map(str::trim) {
            let Some(cargo_index) = line.find("cargo ") else {
                continue;
            };
            let cargo_command = &line[cargo_index..];
            if cargo_command.starts_with("cargo fmt ") {
                continue;
            }
            assert!(
                cargo_command.contains("--locked"),
                "{source_name} has an unlocked Cargo command: {cargo_command}"
            );
        }
    }
}

#[test]
fn binary_host_does_not_reach_through_the_facade_for_session_state() {
    let main_source = include_str!("../src/main.rs");

    assert!(!main_source.contains("ubaa_core::session"));
    assert!(!main_source.contains("FileSessionStore"));
    assert!(!main_source.contains("SessionStore"));
}

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
fn binary_json_readonly_without_session_uses_schema_v2_route_diagnostics() {
    let config = std::env::temp_dir().join(format!("ubaa-cli-readonly-e2e-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&config);
    std::fs::create_dir_all(&config).unwrap();
    std::fs::write(
        config.join("config.toml"),
        "schema_version = 1\n\n[route]\ndefault = \"direct\"\n",
    )
    .unwrap();

    let output = Command::new(env!("CARGO_BIN_EXE_ubaa"))
        .arg("--json")
        .arg("--config-dir")
        .arg(&config)
        .arg("schedule")
        .arg("terms")
        .output()
        .unwrap();
    let value: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();

    assert_eq!(output.status.code(), Some(3));
    assert_eq!(value["schemaVersion"], 2);
    assert_eq!(value["error"]["code"], "authentication_required");
    assert_eq!(value["meta"]["feature"], "schedule");
    assert_eq!(value["meta"]["routePolicy"], "direct");
    assert_eq!(value["meta"]["networkState"], "unknown");
    assert_eq!(value["meta"]["initialRoute"], "direct");
    assert_eq!(value["meta"]["resolvedRoute"], "direct");
    assert_eq!(value["meta"]["usedFallback"], false);
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
fn binary_json_argument_errors_use_a_safe_parseable_envelope() {
    let output = Command::new(env!("CARGO_BIN_EXE_ubaa"))
        .arg("--json")
        .arg("auth")
        .arg("login")
        .arg("--mode")
        .arg("MODE-SENTINEL")
        .output()
        .unwrap();

    let value: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(output.status.code(), Some(2));
    assert_eq!(value["ok"], false);
    assert_eq!(value["error"]["code"], "invalid_input");
    assert_eq!(value["error"]["retryable"], false);
    assert!(output.stderr.is_empty());
    assert!(!String::from_utf8_lossy(&output.stdout).contains("MODE-SENTINEL"));
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

#[test]
fn binary_json_logout_clears_a_saved_session_when_remote_logout_fails() {
    let config =
        std::env::temp_dir().join(format!("ubaa-cli-saved-logout-e2e-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&config);
    let store = FileSessionStore::new(&config).unwrap();
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: Vec::new(),
            authenticated_at: 1_000,
            last_activity: 1_001,
        })
        .unwrap();

    let proxy = TcpListener::bind("127.0.0.1:0").unwrap();
    proxy.set_nonblocking(true).unwrap();
    let proxy_address = proxy.local_addr().unwrap();
    let proxy_thread = std::thread::spawn(move || {
        let deadline = Instant::now() + Duration::from_secs(5);
        loop {
            match proxy.accept() {
                Ok((connection, _)) => {
                    drop(connection);
                    return true;
                }
                Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                    if Instant::now() >= deadline {
                        return false;
                    }
                    std::thread::sleep(Duration::from_millis(10));
                }
                Err(_) => return false,
            }
        }
    });
    let proxy_url = format!("http://{proxy_address}");

    let output = Command::new(env!("CARGO_BIN_EXE_ubaa"))
        .arg("--json")
        .arg("--config-dir")
        .arg(&config)
        .arg("auth")
        .arg("logout")
        .env("HTTPS_PROXY", &proxy_url)
        .env("https_proxy", &proxy_url)
        .env("ALL_PROXY", &proxy_url)
        .env("all_proxy", &proxy_url)
        .env_remove("NO_PROXY")
        .env_remove("no_proxy")
        .output()
        .unwrap();

    let value: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert!(output.status.success());
    assert_eq!(value["data"]["loggedOut"], true);
    assert_eq!(value["meta"]["connectionMode"], "direct");
    assert!(output.stderr.is_empty());
    assert!(
        proxy_thread.join().unwrap(),
        "logout request did not use the deterministic local proxy"
    );
    assert!(store.load().unwrap().is_none());
    let _ = std::fs::remove_dir_all(config);
}
