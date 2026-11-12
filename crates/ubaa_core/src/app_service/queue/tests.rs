use super::*;
use crate::{
    app_service::types::{
        CounterDimensions, CounterEvent, CounterResult, ErrorDimensions, ErrorEvent, Feature,
        Route, TimingBucket, TimingDimensions, TimingMetric,
    },
    error::ErrorKind,
};
use rusqlite::{Connection, TransactionBehavior};

mod minutes;

const VERSION: &str = "2.1.0-rc.1+15";

fn day() -> NaiveDate {
    NaiveDate::from_ymd_opt(2026, 11, 11).unwrap()
}

fn database() -> Connection {
    let db = Connection::open_in_memory().unwrap();
    db.execute_batch(SCHEMA).unwrap();
    db.execute_batch(MINUTE_SCHEMA).unwrap();
    db
}

fn enqueue(
    tx: &Transaction<'_>,
    day: NaiveDate,
    version: &str,
    surface: Surface,
    event: &TelemetryEvent,
    user: Option<&TelemetryUser>,
) -> AppServiceResult<bool> {
    super::enqueue(
        tx,
        day.and_hms_opt(0, 0, 0).unwrap(),
        version,
        surface,
        event,
        user,
    )
}

fn transaction(db: &mut Connection) -> Transaction<'_> {
    db.transaction_with_behavior(TransactionBehavior::Immediate)
        .unwrap()
}

fn counter() -> TelemetryEvent {
    TelemetryEvent::Counter(CounterDimensions {
        event: CounterEvent::FeatureLoaded,
        feature: Feature::Schedule,
        route: Route::Direct,
        result: CounterResult::Success,
    })
}

fn detailed_error(index: usize) -> TelemetryEvent {
    TelemetryEvent::Error(ErrorDimensions {
        event: ErrorEvent::FeatureFailed,
        feature: Feature::Schedule,
        route: Route::Direct,
        error_code: format!("parse_error_{index}"),
        error_kind: ErrorKind::Upstream,
        retryable: false,
        source: Some(format!(
            "crates/ubaa_core/src/{}/{index}.rs:120",
            "a".repeat(90)
        )),
    })
}

fn user(index: usize) -> TelemetryUser {
    TelemetryUser::from_confirmed_username(&format!("{:02}{index:06}", 24), 2026).unwrap()
}

fn frozen(tx: &Transaction<'_>, today: NaiveDate, install: Uuid) -> FrozenBatch {
    freeze(tx, today, install, Platform::Android, Channel::Github)
        .unwrap()
        .expect("应存在可冻结或可重发的批次")
}

fn days(batch: &FrozenBatch) -> Vec<serde_json::Value> {
    let payload: serde_json::Value = serde_json::from_slice(batch.body()).unwrap();
    payload["days"].as_array().unwrap().clone()
}

fn counts(days: &[serde_json::Value]) -> u64 {
    days.iter()
        .flat_map(|day| ["counters", "errors", "timings"].map(|field| &day[field]))
        .flat_map(|field| field.as_array().unwrap())
        .map(|item| item["count"].as_u64().unwrap())
        .sum()
}

#[test]
fn app_service_queue_stores_only_whitelisted_aggregate_dimensions() {
    let mut db = database();
    let tx = transaction(&mut db);
    let mut invalid = detailed_error(0);
    let TelemetryEvent::Error(dimensions) = &mut invalid else {
        unreachable!()
    };
    dimensions.source = Some("file:///tmp/invalid.dart:2".to_owned());
    assert!(!enqueue(&tx, day(), VERSION, Surface::Gui, &invalid, Some(&user(0))).unwrap());
    assert_eq!(queued_bytes(&tx).unwrap(), 0);

    let timing = TelemetryEvent::Timing(TimingDimensions {
        metric: TimingMetric::FeatureLoad,
        feature: Feature::Schedule,
        route: Route::Direct,
        bucket: TimingBucket::Lt1000,
    });
    for surface in [Surface::Gui, Surface::Command] {
        assert!(enqueue(&tx, day(), VERSION, surface, &timing, None).unwrap());
    }
    let batch = frozen(&tx, day(), Uuid::new_v4());
    let groups = days(&batch);
    assert_eq!(groups[0]["timings"].as_array().unwrap().len(), 1);
    assert_eq!(groups[0]["timings"][0]["bucket"], "lt_1000");
    assert_eq!(groups[0]["timings"][0]["count"], 2);
    assert_eq!(groups[0]["users"].as_array().unwrap().len(), 0);
    assert_eq!(groups[0]["errors"].as_array().unwrap().len(), 0);
    assert!(!String::from_utf8_lossy(batch.body()).contains("\"minutes\""));
}

#[test]
fn app_service_splits_nine_date_versions_without_losing_counts() {
    let mut db = database();
    let tx = transaction(&mut db);
    for offset in 0..8 {
        let date = day() - Days::new(offset);
        assert!(enqueue(&tx, date, VERSION, Surface::Gui, &counter(), None).unwrap());
    }
    assert!(enqueue(&tx, day(), "2.1.0+16", Surface::Command, &counter(), None).unwrap());

    let install = Uuid::new_v4();
    let first = frozen(&tx, day(), install);
    let first_days = days(&first);
    assert_eq!(first_days.len(), 8);
    assert_eq!(first_days[0]["day"], (day() - Days::new(7)).to_string());
    assert_eq!(counts(&first_days), 8);
    assert!(finish(&tx, first.id(), BatchDisposition::Accepted).unwrap());
    let second = frozen(&tx, day(), install);
    assert_ne!(first.id(), second.id());
    assert_eq!(counts(&days(&second)), 1);
    assert!(finish(&tx, second.id(), BatchDisposition::Accepted).unwrap());
    assert!(
        freeze(&tx, day(), install, Platform::Android, Channel::Github)
            .unwrap()
            .is_none()
    );
}

#[test]
fn app_service_enforces_body_and_total_capacity_with_a_retained_batch() {
    let mut db = database();
    let tx = transaction(&mut db);
    let mut accepted = 0;
    for index in 0..1100 {
        if enqueue(
            &tx,
            day(),
            VERSION,
            Surface::Gui,
            &detailed_error(index),
            None,
        )
        .unwrap()
        {
            accepted += 1;
        }
    }
    assert!(accepted > 512 && accepted < 1100);

    let install = Uuid::new_v4();
    let first = frozen(&tx, day(), install);
    assert!(queued_bytes(&tx).unwrap() <= CAPACITY_BYTES);
    assert!(first.body().len() > 110 * 1024);
    assert!(first.body().len() <= 120 * 1024);
    assert!(days(&first)[0]["errors"].as_array().unwrap().len() < 512);
    assert!(finish(&tx, first.id(), BatchDisposition::Retry).unwrap());
    let retry = frozen(&tx, day(), install);
    assert_eq!(first.id(), retry.id());
    assert!(first.body() == retry.body());
    // 冻结正文的 count 可能比待发区预留的六位短，允许填回实际腾出的少量空间。
    let mut refilled = 0;
    for index in 1200..1264 {
        if enqueue(
            &tx,
            day(),
            VERSION,
            Surface::Gui,
            &detailed_error(index),
            None,
        )
        .unwrap()
        {
            refilled += 1;
        }
    }
    assert!(refilled < 64);
    assert!(queued_bytes(&tx).unwrap() <= CAPACITY_BYTES);

    let mut sent = counts(&days(&first));
    assert!(finish(&tx, first.id(), BatchDisposition::Accepted).unwrap());
    while let Some(batch) = freeze(&tx, day(), install, Platform::Android, Channel::Github).unwrap()
    {
        assert!(batch.body().len() <= 120 * 1024);
        sent += counts(&days(&batch));
        assert!(finish(&tx, batch.id(), BatchDisposition::Accepted).unwrap());
    }
    assert_eq!(sent, accepted + refilled);
}

#[test]
fn app_service_respects_array_and_count_limits() {
    let mut db = database();
    let tx = transaction(&mut db);
    for index in 0..513 {
        let mut event = detailed_error(index);
        let TelemetryEvent::Error(dimensions) = &mut event else {
            unreachable!()
        };
        dimensions.source = None;
        assert!(enqueue(&tx, day(), VERSION, Surface::Gui, &event, None).unwrap());
    }
    assert!(enqueue(&tx, day(), VERSION, Surface::Gui, &counter(), None).unwrap());
    tx.execute(
        "UPDATE app_service_pending SET count=100000 WHERE category=0",
        [],
    )
    .unwrap();
    assert!(enqueue(&tx, day(), VERSION, Surface::Command, &counter(), None).unwrap());

    let install = Uuid::new_v4();
    let first = frozen(&tx, day(), install);
    let first_days = days(&first);
    assert_eq!(first_days[0]["errors"].as_array().unwrap().len(), 512);
    assert_eq!(first_days[0]["counters"][0]["count"], 100_000);
    assert_eq!(
        first_days[0]["surfaces"],
        serde_json::json!(["gui", "command"])
    );
    assert!(finish(&tx, first.id(), BatchDisposition::Accepted).unwrap());
    let second = frozen(&tx, day(), install);
    assert_eq!(counts(&days(&second)), 2);
}

#[test]
fn app_service_daily_account_limit_survives_version_changes_and_confirmation() {
    let mut db = database();
    let tx = transaction(&mut db);
    let install = Uuid::new_v4();
    let person = user(0);
    for version in [VERSION, "2.1.0+16"] {
        assert!(enqueue(&tx, day(), version, Surface::Gui, &counter(), Some(&person)).unwrap());
    }
    let first = frozen(&tx, day(), install);
    for group in days(&first) {
        assert_eq!(group["users"].as_array().unwrap().len(), 1);
        assert!(group["users"][0]["key"].as_str() == Some(person.key()));
    }
    assert!(finish(&tx, first.id(), BatchDisposition::Accepted).unwrap());
    for index in 0..4 {
        assert!(
            enqueue(
                &tx,
                day(),
                VERSION,
                Surface::Gui,
                &counter(),
                Some(&user(index))
            )
            .unwrap()
        );
    }
    let second = frozen(&tx, day(), install);
    let groups = days(&second);
    let registered = groups[0]["users"].as_array().unwrap();
    assert_eq!(registered.len(), 2);
    for index in 1..3 {
        assert!(
            registered
                .iter()
                .any(|entry| entry["key"].as_str() == Some(user(index).key()))
        );
    }
    assert_eq!(counts(&groups), 4);
    assert!(finish(&tx, second.id(), BatchDisposition::Accepted).unwrap());

    let tomorrow = day() + Days::new(1);
    assert!(
        enqueue(
            &tx,
            tomorrow,
            VERSION,
            Surface::Command,
            &counter(),
            Some(&person)
        )
        .unwrap()
    );
    let next = frozen(&tx, tomorrow, install);
    assert!(days(&next)[0]["users"][0]["key"].as_str() == Some(person.key()));
}

#[test]
fn app_service_clearing_pending_counts_preserves_daily_quota() {
    let mut db = database();
    let tx = transaction(&mut db);
    for index in 0..3 {
        assert!(
            enqueue(
                &tx,
                day(),
                VERSION,
                Surface::Gui,
                &counter(),
                Some(&user(index))
            )
            .unwrap()
        );
    }
    clear(&tx).unwrap();
    assert_eq!(queued_bytes(&tx).unwrap(), 0);
    assert!(
        enqueue(
            &tx,
            day(),
            VERSION,
            Surface::Gui,
            &counter(),
            Some(&user(3))
        )
        .unwrap()
    );
    assert!(
        enqueue(
            &tx,
            day(),
            VERSION,
            Surface::Gui,
            &counter(),
            Some(&user(0))
        )
        .unwrap()
    );
    let batch = frozen(&tx, day(), Uuid::new_v4());
    let groups = days(&batch);
    assert_eq!(counts(&groups), 2);
    assert_eq!(groups[0]["users"].as_array().unwrap().len(), 1);
    assert!(groups[0]["users"][0]["key"].as_str() == Some(user(0).key()));
}

#[test]
fn app_service_clearing_unconfirmed_batch_preserves_daily_quota_but_allows_fresh_registration() {
    let mut db = database();
    let tx = transaction(&mut db);
    let install = Uuid::new_v4();
    for index in 0..3 {
        assert!(
            enqueue(
                &tx,
                day(),
                VERSION,
                Surface::Gui,
                &counter(),
                Some(&user(index))
            )
            .unwrap()
        );
    }
    let first = frozen(&tx, day(), install);
    clear(&tx).unwrap();
    assert!(!finish(&tx, first.id(), BatchDisposition::Accepted).unwrap());
    assert!(!finish(&tx, first.id(), BatchDisposition::Retry).unwrap());
    assert!(
        enqueue(
            &tx,
            day(),
            VERSION,
            Surface::Gui,
            &counter(),
            Some(&user(3))
        )
        .unwrap()
    );
    assert!(
        enqueue(
            &tx,
            day(),
            VERSION,
            Surface::Gui,
            &counter(),
            Some(&user(0))
        )
        .unwrap()
    );
    let fresh = frozen(&tx, day(), install);
    let groups = days(&fresh);
    assert_eq!(counts(&groups), 2);
    assert_eq!(groups[0]["users"].as_array().unwrap().len(), 1);
    assert!(groups[0]["users"][0]["key"].as_str() == Some(user(0).key()));

    reset(&tx).unwrap();
    assert!(
        enqueue(
            &tx,
            day(),
            VERSION,
            Surface::Gui,
            &counter(),
            Some(&user(3))
        )
        .unwrap()
    );
    let after_erase = frozen(&tx, day(), Uuid::new_v4());
    assert!(days(&after_erase)[0]["users"][0]["key"].as_str() == Some(user(3).key()));
}

#[test]
fn app_service_pending_expiry_does_not_change_partially_expired_frozen_body() {
    let mut db = database();
    let tx = transaction(&mut db);
    let old = day() - Days::new(7);
    for date in [old - Days::new(1), old, day()] {
        assert!(enqueue(&tx, date, VERSION, Surface::Gui, &counter(), None).unwrap());
    }
    let install = Uuid::new_v4();
    let first = frozen(&tx, day(), install);
    let groups = days(&first);
    assert_eq!(groups.len(), 2);
    assert_eq!(groups[0]["day"], old.to_string());
    assert_eq!(groups[0]["minutes"][0]["count"], 1);
    assert_eq!(groups[1]["minutes"][0]["count"], 1);

    let next_day = day() + Days::new(1);
    let retry = frozen(&tx, next_day, install);
    assert_eq!(first.id(), retry.id());
    assert!(first.body() == retry.body());
    assert!(
        batch_for_send(&tx, next_day, install, first.id())
            .unwrap()
            .is_some()
    );

    let after_window = day() + Days::new(8);
    assert!(
        batch_for_send(&tx, after_window, install, first.id())
            .unwrap()
            .is_none()
    );
    assert!(
        freeze(
            &tx,
            after_window,
            install,
            Platform::Android,
            Channel::Github
        )
        .unwrap()
        .is_none()
    );
    assert!(!finish(&tx, first.id(), BatchDisposition::Retry).unwrap());
    assert_eq!(
        tx.query_row("SELECT count(*) FROM app_service_minutes", [], |row| row
            .get::<_, i64>(0))
            .unwrap(),
        0
    );
}
