use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Barrier};

use ubaa_core::domain::ConnectionMode;
use ubaa_core::session::{
    FileSessionStore, SessionMutation, SessionSnapshot, SessionStore, SessionValidation,
    StoredCookie,
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
    let root = test_root("round-trip");
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
    assert_eq!(
        std::fs::read_to_string(root.join(".session.lock")).unwrap(),
        "0000000000000001\n"
    );

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
        assert_eq!(
            std::fs::metadata(root.join(".session.lock"))
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
}

#[cfg(unix)]
#[test]
fn loading_an_existing_session_restores_owner_only_permissions() {
    use std::os::unix::fs::PermissionsExt;

    let root = test_root("load-permissions");
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store.save(&snapshot(1)).unwrap();
    std::fs::set_permissions(store.path(), std::fs::Permissions::from_mode(0o644)).unwrap();

    store.load().unwrap().expect("session remains readable");

    assert_eq!(
        std::fs::metadata(store.path())
            .unwrap()
            .permissions()
            .mode()
            & 0o777,
        0o600
    );
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn session_store_rejects_non_regular_session_targets() {
    let root = test_root("non-regular-target");
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    std::fs::create_dir(store.path()).unwrap();

    let error = store
        .save(&snapshot(1))
        .expect_err("a directory cannot be used as session.json");

    assert_eq!(error.message, "session path is not a regular file");
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn concurrent_saves_use_unique_temporary_files_and_leave_one_complete_snapshot() {
    let root = test_root("concurrent-save");
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    std::fs::create_dir(root.join("session.json.tmp")).unwrap();
    let barrier = Arc::new(Barrier::new(8));
    let shared_root = Arc::new(root.clone());

    let handles = (0..8)
        .map(|index| {
            let barrier = Arc::clone(&barrier);
            let root = Arc::clone(&shared_root);
            std::thread::spawn(move || {
                let store = FileSessionStore::new(root.as_path())?;
                barrier.wait();
                store.save(&snapshot(index)).map(|()| index)
            })
        })
        .collect::<Vec<_>>();
    let completed = handles
        .into_iter()
        .map(|handle| handle.join().expect("save thread did not panic"))
        .collect::<Result<Vec<_>, _>>()
        .expect("every concurrent save succeeds");

    let loaded = store.load().unwrap().expect("one snapshot remains");
    assert!(
        completed.iter().any(|index| snapshot(*index) == loaded),
        "session must equal one complete submitted snapshot"
    );
    let leftovers = std::fs::read_dir(&root)
        .unwrap()
        .filter_map(Result::ok)
        .filter_map(|entry| entry.file_name().into_string().ok())
        .filter(|name| {
            name.starts_with(".session.json.")
                && std::path::Path::new(name)
                    .extension()
                    .is_some_and(|extension| extension.eq_ignore_ascii_case("tmp"))
        })
        .collect::<Vec<_>>();
    assert!(
        leftovers.is_empty(),
        "temporary files remain: {leftovers:?}"
    );
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn stale_revision_cannot_recreate_or_clear_a_replaced_session() {
    let root = test_root("stale-revision");
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    let original = snapshot(0);
    store.save(&original).unwrap();
    let stale = store.load_versioned().unwrap();

    store.clear().unwrap();
    let stale_save = store
        .compare_exchange(stale.revision, Some(&snapshot(1)))
        .unwrap();
    assert_eq!(stale_save, SessionMutation::Conflict);
    assert!(store.load().unwrap().is_none());

    store.save(&original).unwrap();
    let stale_clear = store.compare_exchange(stale.revision, None).unwrap();
    assert_eq!(stale_clear, SessionMutation::Conflict);
    assert_eq!(store.load().unwrap(), Some(original));
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn concurrent_compare_exchange_applies_exactly_one_file_session_mutation() {
    let root = test_root("concurrent-cas");
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store.save(&snapshot(0)).unwrap();
    let revision = store.load_versioned().unwrap().revision;
    let barrier = Arc::new(Barrier::new(2));

    let handles = (1..=2)
        .map(|index| {
            let root = root.clone();
            let barrier = Arc::clone(&barrier);
            std::thread::spawn(move || {
                let store = FileSessionStore::new(&root).unwrap();
                let candidate = snapshot(index);
                barrier.wait();
                let mutation = store.compare_exchange(revision, Some(&candidate)).unwrap();
                (candidate, mutation)
            })
        })
        .collect::<Vec<_>>();
    let results = handles
        .into_iter()
        .map(|handle| handle.join().unwrap())
        .collect::<Vec<_>>();

    let winners = results
        .iter()
        .filter(|(_, mutation)| matches!(mutation, SessionMutation::Applied { .. }))
        .collect::<Vec<_>>();
    assert_eq!(winners.len(), 1);
    assert_eq!(store.load().unwrap(), Some(winners[0].0.clone()));
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn oversized_session_file_is_rejected_before_json_parsing() {
    let root = test_root("oversized");
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    std::fs::write(store.path(), vec![b' '; 1024 * 1024 + 1]).unwrap();

    let error = store
        .load()
        .expect_err("oversized session must be rejected");

    assert_eq!(error.message, "session file exceeds the allowed size");
    let _ = std::fs::remove_dir_all(root);
}

#[cfg(unix)]
#[test]
fn session_store_rejects_config_and_session_symlinks_without_touching_targets() {
    use std::os::unix::fs::{PermissionsExt, symlink};

    let root = test_root("symlink");
    let _ = std::fs::remove_dir_all(&root);
    std::fs::create_dir_all(&root).unwrap();

    let actual_config = root.join("actual-config");
    std::fs::create_dir(&actual_config).unwrap();
    let linked_config = root.join("linked-config");
    symlink(&actual_config, &linked_config).unwrap();
    let original_mode = std::fs::metadata(&actual_config)
        .unwrap()
        .permissions()
        .mode();

    let error = FileSessionStore::new(&linked_config)
        .expect_err("config directory symlink must be rejected");
    assert_eq!(error.message, "config path is not a directory");
    assert_eq!(
        std::fs::metadata(&actual_config)
            .unwrap()
            .permissions()
            .mode(),
        original_mode,
        "rejecting a symlink must not chmod its target"
    );

    let store = FileSessionStore::new(root.join("safe-config")).unwrap();
    let victim = root.join("victim.json");
    std::fs::write(&victim, b"victim-must-not-change").unwrap();
    symlink(&victim, store.path()).unwrap();

    for error in [
        store.load().expect_err("load must reject a symlink"),
        store
            .save(&snapshot(9))
            .expect_err("save must reject a symlink"),
        store.clear().expect_err("clear must reject a symlink"),
    ] {
        assert_eq!(error.message, "session path is not a regular file");
    }
    assert_eq!(std::fs::read(&victim).unwrap(), b"victim-must-not-change");
    let _ = std::fs::remove_dir_all(root);
}

fn snapshot(index: i64) -> SessionSnapshot {
    SessionSnapshot {
        mode: if index % 2 == 0 {
            ConnectionMode::Direct
        } else {
            ConnectionMode::WebVpn
        },
        cookies: vec![StoredCookie::fixture(
            format!("SESSION-{index}"),
            format!("fixture-cookie-{index}"),
        )],
        authenticated_at: 1_000 + index,
        last_activity: 2_000 + index,
    }
}

fn test_root(label: &str) -> std::path::PathBuf {
    static NEXT_TEST_ROOT: AtomicU64 = AtomicU64::new(0);
    std::env::temp_dir().join(format!(
        "ubaa-session-{label}-{}-{}",
        std::process::id(),
        NEXT_TEST_ROOT.fetch_add(1, Ordering::Relaxed)
    ))
}
