use std::sync::atomic::{AtomicU64, Ordering};

use ubaa_core::domain::ConnectionMode;
use ubaa_core::facade::UbaaClient;
use ubaa_core::session::{FileSessionStore, SessionSnapshot, SessionStore};

#[test]
fn facade_opens_saved_mode_without_host_session_inspection() {
    let root = test_root("saved-mode");
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::WebVpn,
            cookies: Vec::new(),
            authenticated_at: 1_000,
            last_activity: 1_001,
        })
        .unwrap();

    let client = UbaaClient::open(None, &root)
        .unwrap()
        .expect("saved session selects a mode");

    assert_eq!(client.mode(), ConnectionMode::WebVpn);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn facade_reports_missing_mode_and_session_without_constructing_a_client() {
    let root = test_root("missing");
    let _ = std::fs::remove_dir_all(&root);

    assert!(UbaaClient::open(None, &root).unwrap().is_none());

    let _ = std::fs::remove_dir_all(root);
}

fn test_root(label: &str) -> std::path::PathBuf {
    static NEXT_TEST_ROOT: AtomicU64 = AtomicU64::new(0);
    std::env::temp_dir().join(format!(
        "ubaa-facade-{label}-{}-{}",
        std::process::id(),
        NEXT_TEST_ROOT.fetch_add(1, Ordering::Relaxed)
    ))
}
