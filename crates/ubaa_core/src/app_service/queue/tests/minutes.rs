use super::*;
use crate::app_service::{AppService, AppServiceConfig};
use chrono::{DateTime, TimeDelta, Utc};
use serde_json::{Value, json};
use std::{
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
};

struct CampusClock {
    root: PathBuf,
    now: Arc<Mutex<DateTime<Utc>>>,
}

impl CampusClock {
    fn new() -> Self {
        Self {
            root: Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("../../.ubaa_local/minute_telemetry/core")
                .join(Uuid::new_v4().to_string()),
            now: Arc::new(Mutex::new("2026-11-10T16:00:00Z".parse().unwrap())),
        }
    }

    fn advance(&self, delta: TimeDelta) {
        *self.now.lock().unwrap() += delta;
    }

    fn open(&self, version: &str) -> AppService {
        let config = AppServiceConfig::from_build(
            Some("http://127.0.0.1:8787"),
            Some("github"),
            Some(version),
            Platform::Android,
            false,
        );
        let now = Arc::clone(&self.now);
        AppService::open(&self.root, config, Surface::Gui, 3)
            .unwrap()
            .with_runtime(move || *now.lock().unwrap(), false)
    }
}

impl Drop for CampusClock {
    fn drop(&mut self) {
        std::fs::remove_dir_all(&self.root).unwrap();
    }
}

fn track(service: &AppService, event: &TelemetryEvent) {
    assert!(service.enqueue(event, None).unwrap());
}

fn minute_items(group: &Value) -> &[Value] {
    group["minutes"].as_array().expect("应包含分钟计数")
}

#[test]
fn app_service_minutes_同分钟累加并在校园午夜从零起算() {
    let clock = CampusClock::new();
    clock.advance(TimeDelta::hours(24) - TimeDelta::seconds(2));
    let service = clock.open(VERSION);
    let auth = |event| {
        TelemetryEvent::Counter(CounterDimensions {
            event,
            feature: Feature::App,
            route: Route::Direct,
            result: CounterResult::Empty,
        })
    };
    let failed = TelemetryEvent::Error(ErrorDimensions {
        event: ErrorEvent::AuthFailed,
        feature: Feature::Auth,
        route: Route::Webvpn,
        error_code: "invalid_credentials".to_owned(),
        error_kind: ErrorKind::Authentication,
        retryable: false,
        source: None,
    });
    let loaded = |route| {
        TelemetryEvent::Counter(CounterDimensions {
            event: CounterEvent::FeatureLoaded,
            feature: Feature::Schedule,
            route,
            result: CounterResult::Empty,
        })
    };
    for route in [Route::Direct, Route::Webvpn] {
        track(&service, &auth(CounterEvent::AuthStarted));
        track(&service, &auth(CounterEvent::AuthSucceeded));
        track(&service, &failed);
        track(&service, &loaded(route));
        clock.advance(TimeDelta::seconds(1));
    }
    track(&service, &loaded(Route::Direct));

    let batch = service.freeze_next().unwrap().unwrap();
    let groups = days(&batch);
    assert_eq!(groups[0]["day"], "2026-11-11");
    assert_eq!(groups[1]["day"], "2026-11-12");
    assert_eq!(counts(&groups), 9);
    assert_eq!(
        minute_items(&groups[0]),
        json!([
            {"minute":1439,"event":"auth_started","feature":"auth","result":"success","count":2},
            {"minute":1439,"event":"auth_succeeded","feature":"auth","result":"success","count":2},
            {"minute":1439,"event":"auth_failed","feature":"auth","result":"failure","count":2},
            {"minute":1439,"event":"feature_loaded","feature":"schedule","result":"empty","count":2}
        ])
        .as_array()
        .unwrap()
    );
    assert_eq!(
        minute_items(&groups[1]),
        &[
            json!({"minute":0,"event":"feature_loaded","feature":"schedule","result":"empty","count":1})
        ]
    );
    let body = std::str::from_utf8(batch.body()).unwrap();
    assert!(body.contains(concat!(
        "\"timings\":[],\"minutes\":[{\"minute\":1439,\"event\":\"auth_started\",",
        "\"feature\":\"auth\",\"result\":\"success\",\"count\":2}"
    )));
}

#[test]
fn app_service_minutes_跨版本六百键并按五百一十二项拆批() {
    let clock = CampusClock::new();
    let old = clock.open(VERSION);
    let new = clock.open("2.1.0+16");
    let event = counter();
    for _ in 0..520 {
        track(&old, &event);
        clock.advance(TimeDelta::minutes(1));
    }
    for _ in 0..80 {
        track(&new, &event);
        clock.advance(TimeDelta::minutes(1));
    }
    track(&new, &event);
    clock.advance(TimeDelta::minutes(-1));
    track(&new, &event);

    let first = old.freeze_next().unwrap().unwrap();
    let groups = days(&first);
    assert_eq!(groups.len(), 2);
    assert_eq!(groups[0]["app_version"], "2.1.0+16");
    assert_eq!(groups[0]["counters"][0]["count"], 82);
    assert_eq!(minute_items(&groups[0]).len(), 80);
    assert_eq!(minute_items(&groups[0])[79]["minute"], 599);
    assert_eq!(minute_items(&groups[0])[79]["count"], 2);
    assert_eq!(groups[1]["app_version"], VERSION);
    assert_eq!(groups[1]["counters"][0]["count"], 520);
    assert_eq!(minute_items(&groups[1]).len(), 512);
    assert_eq!(minute_items(&groups[1])[511]["minute"], 511);

    assert!(
        old.finish_batch(first.id(), BatchDisposition::Retry)
            .unwrap()
    );
    let retry = new.freeze_next().unwrap().unwrap();
    assert_eq!(retry.id(), first.id());
    assert!(retry.body() == first.body());
    assert!(
        new.finish_batch(first.id(), BatchDisposition::Accepted)
            .unwrap()
    );

    let second = new.freeze_next().unwrap().unwrap();
    let groups = days(&second);
    assert_eq!(groups.len(), 1);
    assert_eq!(groups[0]["app_version"], VERSION);
    assert_eq!(counts(&groups), 0);
    assert_eq!(minute_items(&groups[0]).len(), 8);
    assert_eq!(minute_items(&groups[0])[0]["minute"], 512);
    assert_eq!(minute_items(&groups[0])[7]["minute"], 519);

    // 冻结和确认都不释放当日配额，已发送的键仍可在新批次里继续累加。
    clock.advance(TimeDelta::minutes(2));
    track(&new, &event);
    clock.advance(TimeDelta::minutes(-601));
    track(&old, &event);
    assert!(
        new.finish_batch(second.id(), BatchDisposition::Accepted)
            .unwrap()
    );

    let third = new.freeze_next().unwrap().unwrap();
    let groups = days(&third);
    assert_eq!(counts(&groups), 2);
    assert!(groups[0].get("minutes").is_none());
    assert_eq!(minute_items(&groups[1]).len(), 1);
    assert_eq!(minute_items(&groups[1])[0]["minute"], 0);
    assert_eq!(minute_items(&groups[1])[0]["count"], 1);
    assert!(
        new.finish_batch(third.id(), BatchDisposition::Accepted)
            .unwrap()
    );
    assert!(new.freeze_next().unwrap().is_none());
}

#[test]
fn app_service_minutes_容量不足只丢弃新增分钟键() {
    let clock = CampusClock::new();
    let service = clock.open(VERSION);
    track(&service, &counter());
    let other = CounterDimensions {
        event: CounterEvent::FeatureLoaded,
        feature: Feature::Grades,
        route: Route::None,
        result: CounterResult::Empty,
    };
    let id = Uuid::new_v4();
    let install = service.snapshot().unwrap().install_id.unwrap();
    service
        .store
        .write(|tx| {
            // 模拟等待重试的正文和已排队的计数占用，只留下新按天计数所需空间。
            let daily_size =
                serde_json::to_vec(&other)?.len() + usize::from(COUNT_AND_SEPARATOR_BYTES);
            let reserved = CAPACITY_BYTES - FRAME_RESERVE - daily_size - queued_bytes(tx)?;
            tx.execute(
                "INSERT INTO app_service_batches(id,install_id,last_day,body)
             VALUES(?1,?2,?3,zeroblob(?4))",
                params![
                    id.to_string(),
                    install.to_string(),
                    day().to_string(),
                    u32::try_from(reserved).unwrap()
                ],
            )?;
            Ok(())
        })
        .unwrap();

    track(&service, &counter());
    clock.advance(TimeDelta::minutes(1));
    track(&service, &TelemetryEvent::Counter(other));
    assert!(
        service
            .finish_batch(id, BatchDisposition::Accepted)
            .unwrap()
    );
    let batch = service.freeze_next().unwrap().unwrap();
    let groups = days(&batch);
    assert_eq!(counts(&groups), 3);
    assert_eq!(groups[0]["counters"][1]["feature"], "grades");
    assert_eq!(minute_items(&groups[0]).len(), 1);
    assert_eq!(minute_items(&groups[0])[0]["minute"], 0);
    assert_eq!(minute_items(&groups[0])[0]["count"], 2);
}

#[test]
fn app_service_minutes_关闭和删除清空分钟计数() {
    let clock = CampusClock::new();
    let service = clock.open(VERSION);
    for erase in [false, true] {
        track(&service, &counter());
        let first = service.freeze_next().unwrap().unwrap();
        assert_eq!(minute_items(&days(&first)[0])[0]["count"], 1);
        track(&service, &counter());
        if erase {
            let id = service.begin_erase().unwrap().unwrap();
            assert!(!service.enqueue(&counter(), None).unwrap());
            assert!(service.freeze_next().unwrap().is_none());
            assert!(service.finish_erase(id).unwrap());
        } else {
            assert!(service.set_telemetry(false).unwrap());
            assert!(service.set_telemetry(true).unwrap());
        }
        assert!(
            !service
                .finish_batch(first.id(), BatchDisposition::Retry)
                .unwrap()
        );
        assert!(service.freeze_next().unwrap().is_none());
    }
}

#[test]
fn app_service_minutes_单键计数跨批拆分而不在同批重复() {
    let clock = CampusClock::new();
    let service = clock.open(VERSION);
    track(&service, &counter());
    service
        .store
        .write(|tx| {
            tx.execute("UPDATE app_service_pending SET count=?1", [COUNT_LIMIT])?;
            tx.execute("UPDATE app_service_minutes SET count=?1", [COUNT_LIMIT])?;
            Ok(())
        })
        .unwrap();
    track(&service, &counter());

    for expected in [COUNT_LIMIT, 1] {
        let batch = service.freeze_next().unwrap().unwrap();
        let groups = days(&batch);
        assert_eq!(minute_items(&groups[0]).len(), 1);
        assert_eq!(minute_items(&groups[0])[0]["count"], expected);
        assert_eq!(groups[0]["counters"][0]["count"], expected);
        assert!(
            service
                .finish_batch(batch.id(), BatchDisposition::Accepted)
                .unwrap()
        );
    }
    assert!(service.freeze_next().unwrap().is_none());
}
