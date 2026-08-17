use std::time::{SystemTime, UNIX_EPOCH};

use ubaa_core::domain::ConnectionMode;
use ubaa_core::session::{
    FileSessionStore, SessionSnapshot, SessionStore, SessionValidation, StoredCookie,
};

#[test]
fn explicit_invalidation_clears_but_timeout_and_server_errors_preserve_session() {
    assert!(SessionValidation::Invalid.should_clear());
    assert!(!SessionValidation::Valid.should_clear());
    assert!(!SessionValidation::ServerError.should_clear());
    assert!(!SessionValidation::Timeout.should_clear());
}

#[test]
fn file_session_store_round_trips_mode_cookies_and_timestamps_without_passwords() {
    let root = std::env::temp_dir().join(format!("ubaa-session-fixture-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    let snapshot = SessionSnapshot {
        mode: ConnectionMode::WebVpn,
        cookies: vec![StoredCookie::fixture("SESSION", "fixture-cookie")],
        authenticated_at: 1_000,
        last_activity: 1_001,
    };

    store.save(&snapshot).unwrap();
    let loaded = store.load().unwrap().expect("session persisted");
    assert_eq!(loaded, snapshot);
    let raw = std::fs::read_to_string(store.path()).unwrap();
    assert!(!raw.contains("password"));
    assert!(!raw.contains("username"));

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        assert_eq!(
            std::fs::metadata(store.path())
                .unwrap()
                .permissions()
                .mode()
                & 0o777,
            0o600
        );
    }

    store.clear().unwrap();
    assert!(store.load().unwrap().is_none());
    let _ = std::fs::remove_dir_all(root);
    let _ = SystemTime::now().duration_since(UNIX_EPOCH);
}
