use super::*;
use ubaa_core::facade::{CacheKey, CacheLimits, CachePayload, OfflineCache, OfflineReadError};

fn cached_client(
    root: &std::path::Path,
    requests: Arc<std::sync::Mutex<Vec<HttpRequest>>>,
) -> UbaaClient {
    cached_client_transport(root, OfflineTransport(requests))
}

fn cached_client_transport(
    root: &std::path::Path,
    transport: impl HttpTransport + 'static,
) -> UbaaClient {
    let store = FileSessionStore::new(root).unwrap();
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: Vec::new(),
            authenticated_at: 1_000,
            last_activity: 1_001,
        })
        .unwrap();
    UbaaClient::with_routing(
        transport,
        CountingTransport(Arc::new(AtomicUsize::new(0))),
        store,
        RouteConfig::parse("[route]\ndefault = \"direct\"\n").unwrap(),
        NeverProbe,
    )
    .unwrap()
}

#[test]
fn 学业缓存按精确参数保存完整结果且磁盘重开不发送网络() {
    use ubaa_core::facade::AcademicQuery;
    let root = test_root("offline-academic");
    let requests = Arc::new(std::sync::Mutex::new(Vec::new()));
    let mut client = cached_client(&root, requests.clone());
    let cache = OfflineCache::open(
        &root,
        "0123456789abcdef0123456789abcdef",
        "fixture-user",
        CacheKey::new([9; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let queries = [
        AcademicQuery::Terms,
        AcademicQuery::Weeks {
            term: "2025-2026-1".into(),
        },
        AcademicQuery::Week {
            term: "2025-2026-1".into(),
            week: 3,
        },
        AcademicQuery::Exams {
            term: "2025-2026-1".into(),
        },
        AcademicQuery::Grades {
            term: "2025-2026-1".into(),
        },
        AcademicQuery::Classrooms {
            campus: 1,
            date: "2026-09-22".into(),
        },
    ];
    let mut results = Vec::new();
    for query in queries {
        let result = runtime
            .block_on(client.refresh_cached_academic(&cache, query))
            .unwrap();
        assert!(result.save_error.is_none());
        results.push(result);
    }
    assert_academic_parameters(&requests.lock().unwrap());
    drop(cache);
    let before = requests.lock().unwrap().len();
    let reopened = OfflineCache::open(
        &root,
        "0123456789abcdef0123456789abcdef",
        "fixture-user",
        CacheKey::new([9; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    for result in results {
        let record = reopened
            .read(&result.scope, result.fetched_at)
            .unwrap()
            .unwrap();
        assert_eq!(record.payload, result.data);
        let mut other = result.scope.clone();
        other.route = ConnectionMode::WebVpn;
        assert!(reopened.read(&other, result.fetched_at).unwrap().is_none());
    }
    assert_eq!(before, requests.lock().unwrap().len());
    drop(reopened);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn online_today_is_saved_under_the_exact_sent_campus_date_and_reads_without_http() {
    let root = test_root("offline-today");
    let requests = Arc::new(std::sync::Mutex::new(Vec::new()));
    let mut client = cached_client(&root, requests.clone());
    let cache = OfflineCache::open(
        &root,
        "0123456789abcdef0123456789abcdef",
        "fixture-user",
        CacheKey::new([9; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let result = runtime
        .block_on(client.refresh_cached_today(&cache))
        .unwrap();
    assert!(result.save_error.is_none());
    assert_eq!(result.data.len(), 1);
    let before = requests.lock().unwrap().len();
    let cached = cache
        .read(&result.scope, result.fetched_at)
        .unwrap()
        .unwrap();
    assert_eq!(cached.payload, CachePayload::Today(result.data));
    assert_eq!(requests.lock().unwrap().len(), before);
    let request_date = requests
        .lock()
        .unwrap()
        .iter()
        .find(|r| r.url.contains("teachingSchedule/detail.do"))
        .unwrap()
        .url
        .clone();
    let url = url::Url::parse(&request_date).unwrap();
    if let ubaa_core::facade::CacheQuery::ScheduleToday { date } = &result.scope.query {
        assert_eq!(
            url.query_pairs().find(|(key, _)| key == "rq").unwrap().1,
            date.as_str()
        );
    } else {
        panic!("必须为今日范围");
    }
    drop(cache);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn mismatched_account_never_reads_or_caches_school_business_data() {
    let root = test_root("offline-identity");
    let requests = Arc::new(std::sync::Mutex::new(Vec::new()));
    let mut client = cached_client(&root, requests.clone());
    let cache = OfflineCache::open(
        &root,
        "0123456789abcdef0123456789abcdef",
        "another-fixture",
        CacheKey::new([9; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    assert!(matches!(
        runtime.block_on(client.refresh_cached_today(&cache)),
        Err(OfflineReadError::IdentityMismatch { .. })
    ));
    assert!(
        requests
            .lock()
            .unwrap()
            .iter()
            .all(|r| r.url.ends_with("/api/uc/status"))
    );
    drop(cache);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn judge_summary_cache_keeps_expired_scope_and_persists_across_reopen() {
    let root = test_root("offline-judge");
    let requests = Arc::new(std::sync::Mutex::new(Vec::new()));
    let mut client = cached_client(&root, requests.clone());
    let cache = OfflineCache::open(
        &root,
        "0123456789abcdef0123456789abcdef",
        "fixture-user",
        CacheKey::new([9; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let result = runtime
        .block_on(client.refresh_cached_judge(&cache, true))
        .unwrap();
    assert_eq!(result.data.len(), 1);
    assert!(result.save_error.is_none());
    assert_eq!(
        result.scope.query,
        ubaa_core::facade::CacheQuery::JudgeSummaries {
            include_expired: true
        }
    );
    drop(cache);
    let cache = OfflineCache::open(
        &root,
        "0123456789abcdef0123456789abcdef",
        "fixture-user",
        CacheKey::new([9; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    assert_eq!(
        cache
            .read(&result.scope, result.fetched_at)
            .unwrap()
            .unwrap()
            .payload,
        CachePayload::JudgeSummaries(result.data)
    );
    let other_scope = ubaa_core::facade::CacheScope {
        route: ConnectionMode::Direct,
        query: ubaa_core::facade::CacheQuery::JudgeSummaries {
            include_expired: false,
        },
    };
    assert!(
        cache
            .read(&other_scope, result.fetched_at)
            .unwrap()
            .is_none()
    );
    drop(cache);
    let _ = std::fs::remove_dir_all(root);
}

#[derive(Clone)]
struct OfflineTransport(Arc<std::sync::Mutex<Vec<HttpRequest>>>);
#[async_trait]
impl HttpTransport for OfflineTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.0.lock().unwrap().push(request.clone());
        if request.url.starts_with("https://sso.buaa.edu.cn/login?") {
            let mut response = HttpResponse::new(302, request.url, Vec::new());
            response
                .headers
                .insert("Location".into(), vec!["https://judge.buaa.edu.cn/".into()]);
            return Ok(response);
        }
        if request.url.contains("/gsapp/sys/wdkbapp/") {
            return Ok(HttpResponse::new(503, request.url, Vec::new()));
        }
        let body = if request.url.ends_with("/api/uc/status") {
            include_bytes!("../../../../fixtures/auth/userinfo-success.json").to_vec()
        } else if request.url.contains("currentUser.do") {
            b"{}".to_vec()
        } else if request.url.contains("schoolCalendars.do") {
            include_bytes!("../../../../fixtures/readonly/schedule-terms.json").to_vec()
        } else if request.url.contains("getTermWeeks.do") {
            include_bytes!("../../../../fixtures/readonly/schedule-weeks.json").to_vec()
        } else if request.url.contains("getMyScheduleDetail.do") {
            include_bytes!("../../../../fixtures/readonly/schedule-week.json").to_vec()
        } else if request.url.contains("exams.do") {
            include_bytes!("../../../../fixtures/readonly/exam.json").to_vec()
        } else if request.url.contains("buaascore/wap/default/index") {
            if request.method == ubaa_core::facade::testing::HttpMethod::Post {
                include_bytes!("../../../../fixtures/readonly/grades.json").to_vec()
            } else {
                include_bytes!("../../../../fixtures/readonly/grades-page.html").to_vec()
            }
        } else if request.url.contains("buaafreeclass/wap/default/search1") {
            include_bytes!("../../../../fixtures/readonly/classroom.json").to_vec()
        } else if request.url.contains("teachingSchedule/detail.do") {
            include_bytes!("../../../../fixtures/readonly/schedule-today.json").to_vec()
        } else if request.url.starts_with("https://sso.buaa.edu.cn/login?")
            || request.url == "https://judge.buaa.edu.cn/"
        {
            b"<html><body>ready</body></html>".to_vec()
        } else if request.url.contains("courselist.jsp?courseID=0") {
            br"<a href='courselist.jsp?courseID=12'>Fixture Course</a>".to_vec()
        } else if request.url.contains("courselist.jsp?courseID=12") {
            b"<html>selected</html>".to_vec()
        } else if request.url.ends_with("assignment/index.jsp") {
            include_bytes!("../../../../fixtures/readonly/judge-assignments.html").to_vec()
        } else if request.url.contains("assignment/index.jsp?assignID=101") {
            include_bytes!("../../../../fixtures/readonly/judge-detail.html").to_vec()
        } else {
            panic!("未预期的合成请求");
        };
        Ok(HttpResponse::new(200, request.url, body))
    }
}

#[derive(Clone)]
struct ControlledAcademicTransport {
    inner: OfflineTransport,
    mode: Arc<AtomicUsize>,
    cache: OfflineCache,
}
#[async_trait]
impl HttpTransport for ControlledAcademicTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        if request.url.contains("getMyScheduleDetail.do") {
            match self.mode.load(Ordering::SeqCst) {
                1 => return Ok(HttpResponse::new(503, request.url, b"synthetic".to_vec())),
                2 => self.cache.deactivate().unwrap(),
                3 => return Ok(HttpResponse::new(200, request.url, br#"{"code":"0","datas":{"arrangedList":[],"code":"response-code","name":"synthetic"}}"#.to_vec())),
                _ => {}
            }
        }
        self.inner.execute(request).await
    }
}

#[test]
fn 学业失败保留原完整内容且完整空周才可替换() {
    use ubaa_core::facade::{AcademicQuery, CacheError};
    let root = test_root("offline-academic-failure");
    std::fs::create_dir_all(&root).unwrap();
    let cache = OfflineCache::open(
        &root,
        "0123456789abcdef0123456789abcdef",
        "fixture-user",
        CacheKey::new([9; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    let mode = Arc::new(AtomicUsize::new(0));
    let mut client = cached_client_transport(
        &root,
        ControlledAcademicTransport {
            inner: OfflineTransport(Arc::new(std::sync::Mutex::new(Vec::new()))),
            mode: mode.clone(),
            cache: cache.clone(),
        },
    );
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let query = AcademicQuery::Week {
        term: "2025-2026-1".into(),
        week: 3,
    };
    let first = runtime
        .block_on(client.refresh_cached_academic(&cache, query.clone()))
        .unwrap();
    mode.store(1, Ordering::SeqCst);
    assert!(matches!(
        runtime.block_on(client.refresh_cached_academic(&cache, query.clone())),
        Err(OfflineReadError::Read(_))
    ));
    let previous = cache.read(&first.scope, first.fetched_at).unwrap().unwrap();
    assert_eq!(previous.payload, first.data);
    assert_eq!(previous.fetched_at, first.fetched_at);
    assert!(!previous.last_attempt_succeeded);
    mode.store(3, Ordering::SeqCst);
    let empty = runtime
        .block_on(client.refresh_cached_academic(&cache, query.clone()))
        .unwrap();
    let CachePayload::Week(value) = &empty.data else {
        panic!("必须是周课表");
    };
    assert!(value.arranged_list.is_empty());
    assert_eq!(value.code, "response-code");
    assert_eq!(
        cache
            .read(&empty.scope, empty.fetched_at)
            .unwrap()
            .unwrap()
            .payload,
        empty.data
    );
    mode.store(2, Ordering::SeqCst);
    assert!(matches!(
        runtime.block_on(client.refresh_cached_academic(&cache, query)),
        Err(OfflineReadError::Cache(CacheError::Inactive))
    ));
    drop(cache);
    drop(client);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 学业非法范围在认证前拒绝且错账号不读取业务() {
    use ubaa_core::facade::{AcademicQuery, CacheError};
    let root = test_root("offline-academic-guards");
    let requests = Arc::new(std::sync::Mutex::new(Vec::new()));
    let mut client = cached_client(&root, requests.clone());
    let cache = OfflineCache::open(
        &root,
        "0123456789abcdef0123456789abcdef",
        "other-user",
        CacheKey::new([9; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    for query in [
        AcademicQuery::Week {
            term: "2025-2026-1".into(),
            week: 0,
        },
        AcademicQuery::Grades {
            term: "20261".into(),
        },
        AcademicQuery::Classrooms {
            campus: 1,
            date: "2026-02-30".into(),
        },
    ] {
        assert!(matches!(
            runtime.block_on(client.refresh_cached_academic(&cache, query)),
            Err(OfflineReadError::Cache(CacheError::InvalidInput))
        ));
    }
    assert!(requests.lock().unwrap().is_empty());
    assert!(matches!(
        runtime.block_on(client.refresh_cached_academic(&cache, AcademicQuery::Terms)),
        Err(OfflineReadError::IdentityMismatch { .. })
    ));
    assert!(
        requests
            .lock()
            .unwrap()
            .iter()
            .all(|request| request.url.ends_with("/api/uc/status"))
    );
    drop(cache);
    drop(client);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 学业缓存容量不足仍返回在线内容但不能宣称已保存() {
    use ubaa_core::facade::{AcademicQuery, CacheError};
    let root = test_root("offline-academic-capacity");
    let mut client = cached_client(&root, Arc::new(std::sync::Mutex::new(Vec::new())));
    let cache = OfflineCache::open(
        &root,
        "0123456789abcdef0123456789abcdef",
        "fixture-user",
        CacheKey::new([9; 32]),
        CacheLimits {
            soft_bytes: 128,
            hard_bytes: 128,
        },
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let result = runtime
        .block_on(client.refresh_cached_academic(&cache, AcademicQuery::Terms))
        .unwrap();
    assert_eq!(result.save_error, Some(CacheError::Capacity));
    let CachePayload::Terms(terms) = result.data else {
        panic!("必须为学期列表");
    };
    assert!(!terms.is_empty());
    assert!(
        cache
            .read(&result.scope, result.fetched_at)
            .unwrap()
            .is_none()
    );
    drop(cache);
    drop(client);
    let _ = std::fs::remove_dir_all(root);
}

fn assert_academic_parameters(sent: &[HttpRequest]) {
    let week = sent
        .iter()
        .find(|request| request.url.contains("getMyScheduleDetail.do"))
        .unwrap();
    let form: std::collections::BTreeMap<_, _> = url::form_urlencoded::parse(&week.body)
        .into_owned()
        .collect();
    assert_eq!(
        form,
        [
            ("termCode".into(), "2025-2026-1".into()),
            ("type".into(), "week".into()),
            ("week".into(), "3".into())
        ]
        .into()
    );
    let grade = sent
        .iter()
        .find(|request| request.url.contains("buaascore") && !request.body.is_empty())
        .unwrap();
    let form: std::collections::BTreeMap<_, _> = url::form_urlencoded::parse(&grade.body)
        .into_owned()
        .collect();
    assert_eq!(
        form,
        [
            ("xq".into(), "1".into()),
            ("year".into(), "2025-2026".into())
        ]
        .into()
    );
    let room = sent
        .iter()
        .find(|request| request.url.contains("buaafreeclass"))
        .unwrap();
    let url = url::Url::parse(&room.url).unwrap();
    let params: std::collections::BTreeMap<_, _> = url.query_pairs().into_owned().collect();
    assert_eq!(
        params,
        [
            ("xqid".into(), "1".into()),
            ("floorid".into(), String::new()),
            ("date".into(), "2026-09-22".into())
        ]
        .into()
    );
}
