use super::{
    AppServiceError,
    sqlite::{DATABASE_NAME, Store},
};
use rusqlite::Connection;

#[test]
fn failed_migration_leaves_both_databases_intact() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/app_service/test_sqlite")
        .join(uuid::Uuid::new_v4().to_string());
    std::fs::create_dir_all(&root).unwrap();
    let business = Connection::open(root.join("business.sqlite3")).unwrap();
    business
        .execute_batch("CREATE TABLE existing (value INTEGER); INSERT INTO existing VALUES (7)")
        .unwrap();
    let installation = Connection::open(root.join(DATABASE_NAME)).unwrap();
    installation.execute_batch("CREATE TABLE app_service_pending (value INTEGER); INSERT INTO app_service_pending VALUES (9)").unwrap();

    assert!(Store::open(&root).is_err());
    assert_eq!(
        installation
            .pragma_query_value(None, "user_version", |row| row.get::<_, u32>(0))
            .unwrap(),
        0
    );
    assert_eq!(
        installation
            .query_row("SELECT value FROM app_service_pending", [], |row| row
                .get::<_, i32>(0))
            .unwrap(),
        9
    );
    assert!(
        !installation
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM sqlite_schema WHERE name = 'app_service_state')",
                [],
                |row| row.get::<_, bool>(0)
            )
            .unwrap()
    );
    installation
        .pragma_update(None, "user_version", 99)
        .unwrap();
    assert!(matches!(
        Store::open(&root),
        Err(AppServiceError::UnsupportedSchema)
    ));
    assert_eq!(
        installation
            .pragma_query_value(None, "user_version", |row| row.get::<_, u32>(0))
            .unwrap(),
        99
    );
    assert_eq!(
        business
            .query_row("SELECT value FROM existing", [], |row| row.get::<_, i32>(0))
            .unwrap(),
        7
    );
    drop(installation);
    drop(business);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn facade_uses_shared_install_and_discards_revoked_account() {
    use crate::facade::{SharedAccountGuard, UbaaClient, app_service::*};

    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/app_service/test_sqlite")
        .join(uuid::Uuid::new_v4().to_string());
    {
        let gui_client = UbaaClient::open(&root).unwrap();
        let command_client = UbaaClient::open(&root).unwrap();
        let cfg = AppServiceConfig::from_build(
            Some("http://[::1]:8787"),
            Some("github"),
            Some("2.0.0"),
            Platform::Macos,
            false,
        );
        let on_first_day = || "2026-11-10T15:59:59Z".parse().unwrap();
        let on_second_day = || "2026-11-10T16:00:00Z".parse().unwrap();
        let gui = gui_client
            .open_app_service(cfg.clone(), Surface::Gui, 1)
            .unwrap()
            .with_runtime(on_first_day, false);
        let command = command_client
            .open_app_service(cfg, Surface::Command, 1)
            .unwrap()
            .with_runtime(on_second_day, false);
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt as _;
            let mode = std::fs::metadata(root.join(DATABASE_NAME))
                .unwrap()
                .permissions()
                .mode();
            assert_eq!(mode & 0o777, 0o600);
        }
        gui.agree(1).unwrap();
        let install = gui.snapshot().unwrap().install_id;
        assert!(install.is_some() && command.snapshot().unwrap().install_id == install);

        for (name, value) in [
            ("materials.lock", ""),
            ("transaction.v1", "UBAA1:C"),
            ("account-generation.v1", "UBAA1:1"),
        ] {
            std::fs::write(root.join(name), value).unwrap();
        }
        let bound = ConfirmedAccount::from_bound_account(
            SharedAccountGuard::new(&root, 1).unwrap(),
            format!("{}{:04}", 24, 1),
        );
        let event = TelemetryEvent::Counter(CounterDimensions {
            event: CounterEvent::FeatureLoaded,
            feature: Feature::Schedule,
            route: Route::None,
            result: CounterResult::Success,
        });
        assert!(gui.enqueue(&event, Some(&bound)).unwrap());
        assert!(command.enqueue(&event, Some(&bound)).unwrap());

        // 另一端切换账号后，旧绑定不再用于登记，设备计数仍然可用。
        std::fs::write(root.join("account-generation.v1"), "UBAA1:2").unwrap();
        let second = ConfirmedAccount::from_bound_account(
            SharedAccountGuard::new(&root, 2).unwrap(),
            format!("{}{:04}", 24, 2),
        );
        assert!(command.enqueue(&event, Some(&bound)).unwrap());
        assert!(command.enqueue(&event, Some(&second)).unwrap());

        let batch = gui.freeze_next().unwrap().unwrap();
        let body: serde_json::Value = serde_json::from_slice(batch.body()).expect("合法冻结载荷");
        let days = body["days"].as_array().unwrap();
        assert_eq!(days.len(), 2);
        assert_eq!(days[0]["day"].as_str(), Some("2026-11-10"));
        assert_eq!(days[1]["day"].as_str(), Some("2026-11-11"));
        assert_eq!(days[0]["users"].as_array().unwrap().len(), 1);
        assert_eq!(days[1]["users"].as_array().unwrap().len(), 2);
        assert_eq!(days[1]["counters"][0]["count"].as_u64(), Some(3));

        assert!(
            gui.finish_batch(batch.id(), BatchDisposition::Accepted)
                .unwrap()
        );
        // 次日版本没有保留旧账号对象：即使错误传入旧绑定，也只记设备活跃。
        let day_three = gui.with_runtime(|| "2026-11-11T16:00:00Z".parse().unwrap(), false);
        assert!(day_three.enqueue(&event, Some(&bound)).unwrap());
        let batch = day_three.freeze_next().unwrap().unwrap();
        let body: serde_json::Value = serde_json::from_slice(batch.body()).expect("合法冻结载荷");
        assert_eq!(body["days"][0]["users"].as_array().unwrap().len(), 0);
    }
    std::fs::remove_dir_all(root).unwrap();
}
