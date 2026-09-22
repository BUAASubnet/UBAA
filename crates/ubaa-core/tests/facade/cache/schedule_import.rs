use super::*;
use std::sync::Mutex;
use ubaa_core::facade::{
    CacheError, CacheKey, CacheLimits, CachePayload, CacheQuery, CacheScope, OfflineCache,
    OfflineReadError,
};

#[derive(Clone, Default)]
struct ImportTransport {
    requests: Arc<Mutex<Vec<HttpRequest>>>,
    fail_second: Arc<std::sync::atomic::AtomicBool>,
    two_terms: Arc<std::sync::atomic::AtomicBool>,
    weeks_today: Arc<std::sync::atomic::AtomicBool>,
    unknown_weeks: Arc<std::sync::atomic::AtomicBool>,
    unknown_week: Arc<std::sync::atomic::AtomicBool>,
    cancel_on_week: Arc<Mutex<Option<ubaa_core::facade::ScheduleImportCancellation>>>,
}
#[async_trait]
impl HttpTransport for ImportTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.requests.lock().unwrap().push(request.clone());
        let mut body = if request.url.ends_with("/api/uc/status") {
            include_bytes!("../../../../../fixtures/auth/userinfo-success.json").to_vec()
        } else if request.url.contains("currentUser.do") {
            b"{}".to_vec()
        } else if request.url.contains("schoolCalendars.do") {
            include_bytes!("../../../../../fixtures/readonly/schedule-terms.json").to_vec()
        } else if request.url.contains("getTermWeeks.do") {
            br#"{"code":"0","datas":[{"startDate":"2026-02-23","endDate":"2026-03-01","term":"2025-2026-1","curWeek":true,"serialNumber":1,"name":"Week 1"},{"startDate":"2026-03-02","endDate":"2026-03-08","term":"2025-2026-1","curWeek":false,"serialNumber":2,"name":"Week 2"}]}"#.to_vec()
        } else if request.url.contains("getMyScheduleDetail.do") {
            let body = String::from_utf8_lossy(&request.body);
            if body.contains("week=2") && self.fail_second.load(Ordering::SeqCst) {
                return Err(ubaa_core::facade::UbaaError::new(
                    ErrorCode::NetworkError,
                    ubaa_core::facade::ErrorKind::Network,
                    true,
                    "合成第二周失败",
                ));
            }
            include_bytes!("../../../../../fixtures/readonly/schedule-week.json").to_vec()
        } else {
            panic!("未预期的合成只读请求");
        };
        if request.url.contains("getTermWeeks.do") && self.weeks_today.load(Ordering::SeqCst) {
            let today = chrono::Utc::now()
                .with_timezone(&chrono::FixedOffset::east_opt(8 * 3600).unwrap())
                .date_naive();
            let mut value: serde_json::Value = serde_json::from_slice(&body).unwrap();
            for (index, week) in value["datas"]
                .as_array_mut()
                .unwrap()
                .iter_mut()
                .enumerate()
            {
                let start = today + chrono::Days::new(u64::try_from(index).unwrap() * 7);
                week["startDate"] = serde_json::json!(start.to_string());
                week["endDate"] = serde_json::json!((start + chrono::Days::new(6)).to_string());
            }
            body = serde_json::to_vec(&value).unwrap();
        }
        if self.two_terms.load(Ordering::SeqCst) {
            if request.url.contains("schoolCalendars.do") {
                let mut value: serde_json::Value = serde_json::from_slice(&body).unwrap();
                value["datas"].as_array_mut().unwrap().push(serde_json::json!({"itemCode":"2025-2026-2","itemName":"Other fixture term","selected":false,"itemIndex":2}));
                body = serde_json::to_vec(&value).unwrap();
            } else if request.url.contains("getTermWeeks.do") {
                let url = url::Url::parse(&request.url).unwrap();
                let term = url
                    .query_pairs()
                    .find(|(key, _)| key == "termCode")
                    .unwrap()
                    .1
                    .to_string();
                let mut value: serde_json::Value = serde_json::from_slice(&body).unwrap();
                for week in value["datas"].as_array_mut().unwrap() {
                    week["term"] = serde_json::json!(term);
                }
                body = serde_json::to_vec(&value).unwrap();
            }
        }
        let weekly = request.url.contains("getMyScheduleDetail.do");
        if weekly && let Some(cancel) = self.cancel_on_week.lock().unwrap().take() {
            cancel.cancel();
        }
        if (weekly && self.unknown_week.load(Ordering::SeqCst))
            || (request.url.contains("getTermWeeks.do")
                && self.unknown_weeks.load(Ordering::SeqCst))
        {
            let mut value: serde_json::Value = serde_json::from_slice(&body).unwrap();
            value["code"] = serde_json::json!("unconfirmed");
            body = serde_json::to_vec(&value).unwrap();
        }
        Ok(HttpResponse::new(200, request.url, body))
    }
}
fn setup(
    root: &std::path::Path,
    mode: ConnectionMode,
    transport: ImportTransport,
) -> (UbaaClient, OfflineCache) {
    let store = FileSessionStore::new(root).unwrap();
    store
        .save(&SessionSnapshot {
            mode,
            cookies: Vec::new(),
            authenticated_at: 1000,
            last_activity: 1001,
        })
        .unwrap();
    let mode = if mode == ConnectionMode::Direct {
        "direct"
    } else {
        "webvpn"
    };
    let client = UbaaClient::with_routing(
        transport.clone(),
        transport,
        store,
        RouteConfig::parse(&format!("[route]\ndefault=\"{mode}\"\n")).unwrap(),
        NeverProbe,
    )
    .unwrap();
    let cache = OfflineCache::open(
        root,
        "0123456789abcdef0123456789abcdef",
        "fixture-user",
        CacheKey::new([9; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    (client, cache)
}
fn imported(mode: ConnectionMode) -> CacheScope {
    CacheScope {
        route: mode,
        query: CacheQuery::ImportedSchedules,
    }
}
#[test]
fn 两路线逐元数据和单周返回_全部完成后才发布() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        let root = test_root("schedule-import");
        let transport = ImportTransport::default();
        let (mut client, cache) = setup(&root, mode, transport.clone());
        runtime.block_on(async {
            let mut plan = client
                .begin_schedule_import(&cache, "2025-2026-1")
                .await
                .unwrap();
            for expected in [0, 0, 1, 2] {
                let batch = client.next_schedule_import(&mut plan).await.unwrap();
                assert_eq!(batch.resolution.mode, mode);
                assert_eq!(batch.data.completed_weeks, expected);
                let saved = cache.read(&imported(mode), 1).unwrap();
                assert_eq!(saved.is_some(), expected == 2);
                if expected == 2 {
                    assert!(batch.data.finished);
                    assert!(batch.data.save_error.is_none());
                }
            }
            assert!(matches!(
                client.next_schedule_import(&mut plan).await,
                Err(OfflineReadError::Cache(CacheError::Superseded))
            ));
        });
        let requests = transport.requests.lock().unwrap();
        let weeks: Vec<_> = requests
            .iter()
            .filter(|request| request.url.contains("getMyScheduleDetail.do"))
            .collect();
        assert_eq!(weeks.len(), 2);
        for request in weeks {
            assert_eq!(request.method, ubaa_core::facade::testing::HttpMethod::Post);
            let fields: std::collections::HashMap<_, _> =
                url::form_urlencoded::parse(&request.body).collect();
            assert_eq!(fields.len(), 3);
            assert_eq!(fields["type"], "week");
            assert_eq!(fields["termCode"], "2025-2026-1");
        }
        drop(requests);
        drop((client, cache));
        let _ = std::fs::remove_dir_all(root);
    }
}
#[test]
fn 取消清理和较新导入不允许旧计划再发下一周() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    for action in [0, 1, 2] {
        let root = test_root("schedule-import-cancel");
        let transport = ImportTransport::default();
        let (mut client, cache) = setup(&root, ConnectionMode::Direct, transport.clone());
        runtime.block_on(async {
            let mut plan = client
                .begin_schedule_import(&cache, "2025-2026-1")
                .await
                .unwrap();
            client.next_schedule_import(&mut plan).await.unwrap();
            match action {
                0 => plan.cancellation().cancel(),
                1 => {
                    cache.clear().unwrap();
                }
                _ => {
                    client
                        .begin_schedule_import(&cache, "2025-2026-1")
                        .await
                        .unwrap();
                }
            }
            let before = transport.requests.lock().unwrap().len();
            assert!(client.next_schedule_import(&mut plan).await.is_err());
            assert_eq!(transport.requests.lock().unwrap().len(), before);
            assert!(
                cache
                    .read(&imported(ConnectionMode::Direct), 1)
                    .unwrap()
                    .is_none()
            );
        });
        drop((client, cache));
        let _ = std::fs::remove_dir_all(root);
    }
}
#[test]
fn 部分周失败保留此前完整导入且不自动重发() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let root = test_root("schedule-import-partial");
    let transport = ImportTransport::default();
    let (mut client, cache) = setup(&root, ConnectionMode::Direct, transport.clone());
    runtime.block_on(async {
        let mut first=client.begin_schedule_import(&cache,"2025-2026-1").await.unwrap();
        for _ in 0..4 {client.next_schedule_import(&mut first).await.unwrap();}
        let before=cache.read(&imported(ConnectionMode::Direct),1).unwrap().unwrap();
        assert!(matches!(&before.payload,CachePayload::ImportedSchedules(values) if values[0].schedules.len()==2));
        transport.fail_second.store(true,Ordering::SeqCst);
        let mut retry=client.begin_schedule_import(&cache,"2025-2026-1").await.unwrap();
        for _ in 0..3 {client.next_schedule_import(&mut retry).await.unwrap();}
        assert!(client.next_schedule_import(&mut retry).await.is_err());
        let calls=transport.requests.lock().unwrap().len();
        assert!(client.next_schedule_import(&mut retry).await.is_err());
        assert_eq!(transport.requests.lock().unwrap().len(),calls);
        let after=cache.read(&imported(ConnectionMode::Direct),1).unwrap().unwrap();
        assert_eq!(before.payload,after.payload);assert_eq!(before.fetched_at,after.fetched_at);
    });
    drop((client, cache));
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 未获证实的包装码不进入完整导入_普通接口容错保持() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    for weeks in [false, true] {
        let root = test_root("schedule-import-unknown");
        let transport = ImportTransport::default();
        let (mut client, cache) = setup(&root, ConnectionMode::Direct, transport.clone());
        runtime.block_on(async {
            let mut plan = client
                .begin_schedule_import(&cache, "2025-2026-1")
                .await
                .unwrap();
            client.next_schedule_import(&mut plan).await.unwrap();
            if weeks {
                transport.unknown_weeks.store(true, Ordering::SeqCst);
                assert!(client.schedule_weeks("2025-2026-1").await.is_ok());
            } else {
                client.next_schedule_import(&mut plan).await.unwrap();
                transport.unknown_week.store(true, Ordering::SeqCst);
                assert!(client.schedule_week("2025-2026-1", 1).await.is_ok());
            }
            assert!(client.next_schedule_import(&mut plan).await.is_err());
            assert!(
                cache
                    .read(&imported(ConnectionMode::Direct), 1)
                    .unwrap()
                    .is_none()
            );
        });
        drop((client, cache));
        let _ = std::fs::remove_dir_all(root);
    }
}
#[test]
fn 请求返回时已取消不发布迟到周或继续下周() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let root = test_root("schedule-import-late");
    let transport = ImportTransport::default();
    let (mut client, cache) = setup(&root, ConnectionMode::Direct, transport.clone());
    runtime.block_on(async {
        let mut plan = client
            .begin_schedule_import(&cache, "2025-2026-1")
            .await
            .unwrap();
        client.next_schedule_import(&mut plan).await.unwrap();
        client.next_schedule_import(&mut plan).await.unwrap();
        *transport.cancel_on_week.lock().unwrap() = Some(plan.cancellation());
        assert!(matches!(
            client.next_schedule_import(&mut plan).await,
            Err(OfflineReadError::Cache(CacheError::Superseded))
        ));
        assert!(
            cache
                .read(&imported(ConnectionMode::Direct), 1)
                .unwrap()
                .is_none()
        );
        let count = transport.requests.lock().unwrap().len();
        assert!(client.next_schedule_import(&mut plan).await.is_err());
        assert_eq!(transport.requests.lock().unwrap().len(), count);
    });
    drop((client, cache));
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn facade精确读取已导入的周次与日期_不发送网络() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let root = test_root("schedule-import-local");
    let transport = ImportTransport::default();
    let (mut client, cache) = setup(&root, ConnectionMode::Direct, transport.clone());
    runtime.block_on(async {
        let mut plan = client
            .begin_schedule_import(&cache, "2025-2026-1")
            .await
            .unwrap();
        for _ in 0..4 {
            client.next_schedule_import(&mut plan).await.unwrap();
        }
    });
    let before = transport.requests.lock().unwrap().len();
    let query = CacheQuery::ScheduleToday {
        date: "2026-02-23".into(),
    };
    let value = cache
        .read_imported_schedule(ConnectionMode::Direct, query)
        .unwrap()
        .unwrap();
    assert!(matches!(value.payload,CachePayload::Today(items) if items.len()==1));
    assert!(
        cache
            .read_imported_schedule(
                ConnectionMode::WebVpn,
                CacheQuery::ScheduleWeek {
                    term: "2025-2026-1".into(),
                    week: 1
                }
            )
            .unwrap()
            .is_none()
    );
    let value = cache
        .read_academic(
            ConnectionMode::Direct,
            &ubaa_core::facade::AcademicQuery::Week {
                term: "2025-2026-1".into(),
                week: 2,
            },
        )
        .unwrap()
        .unwrap();
    assert!(matches!(value.payload, CachePayload::Week(_)));
    assert_eq!(transport.requests.lock().unwrap().len(), before);
    drop((client, cache));
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 不同学期导入互不替代_交错完成后均保留() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let root = test_root("schedule-import-terms");
    let transport = ImportTransport::default();
    transport.two_terms.store(true, Ordering::SeqCst);
    let (mut client, cache) = setup(&root, ConnectionMode::Direct, transport.clone());
    runtime.block_on(async {
        let mut first = client
            .begin_schedule_import(&cache, "2025-2026-1")
            .await
            .unwrap();
        let mut second = client
            .begin_schedule_import(&cache, "2025-2026-2")
            .await
            .unwrap();
        for _ in 0..4 {
            client.next_schedule_import(&mut first).await.unwrap();
            client.next_schedule_import(&mut second).await.unwrap();
        }
        let value = cache
            .read(&imported(ConnectionMode::Direct), 1)
            .unwrap()
            .unwrap();
        assert!(matches!(value.payload,CachePayload::ImportedSchedules(values) if values.len()==2));
    });
    drop((client, cache));
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 完整导入收尾不遮蔽后来完成的精确周查询_时钟回退也保留() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let root = test_root("schedule-import-later-week");
    let transport = ImportTransport::default();
    let (mut client, cache) = setup(&root, ConnectionMode::Direct, transport);
    runtime.block_on(async {
        let mut plan = client
            .begin_schedule_import(&cache, "2025-2026-1")
            .await
            .unwrap();
        for _ in 0..3 {
            client.next_schedule_import(&mut plan).await.unwrap();
        }
        // 同一精确周范围的较新成功观察，取得时系统时钟发生回退。
        let mut repo = ubaa_core::facade::OfflineRepository::open(
            &root,
            "0123456789abcdef0123456789abcdef",
            CacheKey::new([9; 32]),
            CacheLimits::default(),
        )
        .unwrap();
        let query = CacheQuery::ScheduleWeek {
            term: "2025-2026-1".into(),
            week: 1,
        };
        let ticket = repo
            .begin_read(CacheScope {
                route: ConnectionMode::Direct,
                query,
            })
            .unwrap();
        repo.publish(
            &ticket,
            CachePayload::Week(ubaa_core::facade::WeeklySchedule {
                name: "后来单周结果".into(),
                ..Default::default()
            }),
            100,
            ubaa_core::facade::CacheCompleteness::Complete,
        )
        .unwrap();
        client.next_schedule_import(&mut plan).await.unwrap();
        let read = cache
            .read_academic(
                ConnectionMode::Direct,
                &ubaa_core::facade::AcademicQuery::Week {
                    term: "2025-2026-1".into(),
                    week: 1,
                },
            )
            .unwrap()
            .unwrap();
        assert!(matches!(read.payload,CachePayload::Week(week) if week.name=="后来单周结果"));
    });
    drop((client, cache));
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 今日精确快照缺失时仅从已覆盖的完整导入恢复() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let root = test_root("schedule-import-today");
    let transport = ImportTransport::default();
    transport.weeks_today.store(true, Ordering::SeqCst);
    let (mut client, cache) = setup(&root, ConnectionMode::Direct, transport.clone());
    runtime.block_on(async {
        let mut plan = client
            .begin_schedule_import(&cache, "2025-2026-1")
            .await
            .unwrap();
        for _ in 0..4 {
            client.next_schedule_import(&mut plan).await.unwrap();
        }
    });
    let before = transport.requests.lock().unwrap().len();
    assert!(cache.read_today(ConnectionMode::Direct).unwrap().is_some());
    assert!(cache.read_today(ConnectionMode::WebVpn).unwrap().is_none());
    assert_eq!(transport.requests.lock().unwrap().len(), before);
    drop((client, cache));
    let _ = std::fs::remove_dir_all(root);
}
