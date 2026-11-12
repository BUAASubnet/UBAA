use super::{
    AppServiceError, Surface,
    sqlite::{DATABASE_NAME, Store},
};
use rusqlite::Connection;

#[cfg(unix)]
#[test]
fn 系统祖先目录链接可以首次建库并重开原安装() {
    use std::os::unix::fs::symlink;
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/app_service/test_sqlite")
        .join(uuid::Uuid::new_v4().to_string());
    std::fs::create_dir_all(&root).unwrap();
    let real = root.join("real");
    std::fs::create_dir(&real).unwrap();
    symlink(&real, root.join("system-alias")).unwrap();
    let config = root.join("system-alias/UBAA");
    let first = Store::open(&config, Some(1), Surface::Gui).unwrap();
    let install = first
        .read(|tx| {
            Ok(
                tx.query_row("SELECT install_id FROM app_service_state", [], |row| {
                    row.get::<_, String>(0)
                })?,
            )
        })
        .unwrap();
    drop(first);
    let reopened = Store::open(&real.join("UBAA"), Some(1), Surface::Gui).unwrap();
    assert_eq!(
        reopened
            .read(|tx| Ok(
                tx.query_row("SELECT install_id FROM app_service_state", [], |row| row
                    .get::<_, String>(
                    0
                ))?
            ))
            .unwrap(),
        install
    );
    assert!(std::fs::metadata(config.join(DATABASE_NAME)).unwrap().len() > 0);
    drop(reopened);
    std::fs::remove_dir_all(root).unwrap();
}

#[cfg(unix)]
#[test]
fn 应用目录和数据库文件链接仍然拒绝() {
    use std::os::unix::fs::symlink;
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/app_service/test_sqlite")
        .join(uuid::Uuid::new_v4().to_string());
    std::fs::create_dir_all(&root).unwrap();
    let real = root.join("real");
    std::fs::create_dir(&real).unwrap();
    let alias = root.join("UBAA");
    symlink(&real, &alias).unwrap();
    assert!(matches!(
        Store::open(&alias, None, Surface::Gui),
        Err(AppServiceError::StorageUnavailable)
    ));
    for suffix in ["", "-journal", "-wal", "-shm"] {
        let target = root.join("preserved");
        std::fs::write(&target, b"synthetic-preserved").unwrap();
        let file = real.join(format!("{DATABASE_NAME}{suffix}"));
        symlink(&target, &file).unwrap();
        assert!(matches!(
            Store::open(&real, None, Surface::Gui),
            Err(AppServiceError::StorageUnavailable)
        ));
        assert_eq!(std::fs::read(&target).unwrap(), b"synthetic-preserved");
        std::fs::remove_file(file).unwrap();
    }
    std::fs::remove_dir_all(root).unwrap();
}

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

    assert!(Store::open(&root, None, Surface::Gui).is_err());
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
        Store::open(&root, None, Surface::Gui),
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

#[test]
fn 校园午夜后原会话再次登记同一用户和年级() {
    use crate::facade::{SharedAccountGuard, UbaaClient, app_service::*};
    use chrono::{DateTime, TimeDelta, Utc};
    use std::sync::{Arc, Mutex};

    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/app_service/test_sqlite")
        .join(uuid::Uuid::new_v4().to_string());
    {
        let client = UbaaClient::open(&root).unwrap();
        let config = AppServiceConfig::from_build(
            Some("http://[::1]:8787"),
            Some("github"),
            Some("2.0.0"),
            Platform::Macos,
            false,
        );
        let clock = Arc::new(Mutex::new(
            "2026-11-10T15:59:59Z".parse::<DateTime<Utc>>().unwrap(),
        ));
        let gui_clock = Arc::clone(&clock);
        let gui = client
            .open_app_service(config.clone(), Surface::Gui, 1)
            .unwrap()
            .with_runtime(move || *gui_clock.lock().unwrap(), false);
        gui.agree(1).unwrap();
        for (name, value) in [
            ("materials.lock", ""),
            ("transaction.v1", "UBAA1:C"),
            ("account-generation.v1", "UBAA1:1"),
        ] {
            std::fs::write(root.join(name), value).unwrap();
        }
        let confirmed = ConfirmedAccount::from_bound_account(
            SharedAccountGuard::new(&root, 1).unwrap(),
            format!("TQ{}{:04}", 24, 1),
        );
        let event = TelemetryEvent::Counter(CounterDimensions {
            event: CounterEvent::FeatureLoaded,
            feature: Feature::Schedule,
            route: Route::None,
            result: CounterResult::Success,
        });
        assert!(gui.enqueue(&event, Some(&confirmed)).unwrap());

        // 不重新登录：前台句柄继续使用原绑定，另一宿主也复用已确认会话。
        *clock.lock().unwrap() += TimeDelta::seconds(1);
        assert!(gui.enqueue(&event, Some(&confirmed)).unwrap());
        let reopened = UbaaClient::open(&root).unwrap();
        let command = reopened
            .open_app_service(config, Surface::Command, 1)
            .unwrap()
            .with_runtime(move || *clock.lock().unwrap(), false);
        assert!(command.enqueue(&event, Some(&confirmed)).unwrap());

        let batch = command.freeze_next().unwrap().unwrap();
        let body: serde_json::Value = serde_json::from_slice(batch.body()).unwrap();
        let days = body["days"].as_array().unwrap();
        assert_eq!(days.len(), 2);
        for (day, date, count) in [(&days[0], "2026-11-10", 1), (&days[1], "2026-11-11", 2)] {
            assert_eq!(day["day"], date);
            assert_eq!(day["counters"][0]["count"], count);
            assert_eq!(day["users"].as_array().unwrap().len(), 1);
            assert_eq!(day["users"][0]["cohort_type"], "TQ");
            assert_eq!(day["users"][0]["cohort_year"], 2024);
        }
        // 派生标识不进入失败输出。
        assert!(days[0]["users"][0]["key"] == days[1]["users"][0]["key"]);
    }
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 既有安装数据库迁移保留同意开关和交付时间() {
    for version in [1, 2, 3] {
        check_migration(version);
    }
}

fn check_migration(version: u32) {
    use super::{
        AppService, AppServiceConfig, BatchDisposition, Consent, Surface, bootstrap, queue, state,
    };

    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/app_service/test_sqlite")
        .join(uuid::Uuid::new_v4().to_string());
    std::fs::create_dir_all(&root).unwrap();
    let installation = Connection::open(root.join(DATABASE_NAME)).unwrap();
    installation.execute_batch(state::SCHEMA).unwrap();
    installation.execute_batch(queue::SCHEMA).unwrap();
    if version >= 2 {
        installation
            .execute_batch(
                "ALTER TABLE app_service_state ADD COLUMN last_delivery_attempt INTEGER;
             UPDATE app_service_state SET last_delivery_attempt = 7",
            )
            .unwrap();
    }
    if version == 3 {
        installation.execute_batch(bootstrap::SCHEMA).unwrap();
    }
    installation
        .pragma_update(None, "user_version", version)
        .unwrap();
    let previous = uuid::Uuid::new_v4();
    installation.execute(
        "UPDATE app_service_state SET accepted_policy = 1, telemetry_enabled = 0, install_id = ?1 WHERE id = 1",
        [previous.to_string()],
    ).unwrap();
    let batch_id = uuid::Uuid::new_v4();
    let old_body = serde_json::to_vec(&serde_json::json!({
        "schema": 1,
        "batch_id": batch_id,
        "install_id": previous,
        "platform": "macos",
        "channel": "github",
        "days": [{
            "day": "2026-11-11", "app_version": "2.0.0", "surfaces": ["gui"],
            "users": [], "counters": [], "errors": [], "timings": []
        }]
    }))
    .unwrap();
    if version == 3 {
        installation.execute(
            "INSERT INTO app_service_batches(id,install_id,last_day,body) VALUES(?1,?2,'2026-11-11',?3)",
            rusqlite::params![batch_id.to_string(), previous.to_string(), old_body],
        ).unwrap();
    }
    let service = AppService::open(
        &root,
        AppServiceConfig::from_build(
            Some("http://127.0.0.1:8787"),
            Some("github"),
            Some("2.0.0"),
            super::Platform::Macos,
            false,
        ),
        Surface::Gui,
        1,
    )
    .unwrap()
    .with_runtime(|| "2026-11-11T00:00:00Z".parse().unwrap(), false);
    let snapshot = service.snapshot().unwrap();
    assert_eq!(snapshot.consent, Consent::Agreed(1));
    assert_eq!(snapshot.telemetry_enabled, Some(false));
    assert_eq!(snapshot.install_id, Some(previous));
    assert_eq!(
        installation
            .pragma_query_value(None, "user_version", |row| row.get::<_, u32>(0))
            .unwrap(),
        4
    );
    let attempt: Option<i64> = installation
        .query_row(
            "SELECT last_delivery_attempt FROM app_service_state WHERE id = 1",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(attempt, (version >= 2).then_some(7));
    assert!(service.set_telemetry(true).unwrap());
    if version == 3 {
        let batch = service.freeze_next().unwrap().unwrap();
        assert_eq!(batch.id(), batch_id);
        assert!(batch.body() == old_body);
        assert!(
            service
                .finish_batch(batch_id, BatchDisposition::Accepted)
                .unwrap()
        );
    }
    assert!(service.freeze_next().unwrap().is_none());
    drop(service);
    drop(installation);
    std::fs::remove_dir_all(root).unwrap();
}
