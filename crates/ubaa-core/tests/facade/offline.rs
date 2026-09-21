use super::*;
use ubaa_core::facade::{CacheKey, CacheLimits, CachePayload, OfflineCache, OfflineReadError};

fn cached_client(
    root: &std::path::Path,
    requests: Arc<std::sync::Mutex<Vec<HttpRequest>>>,
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
        OfflineTransport(requests),
        CountingTransport(Arc::new(AtomicUsize::new(0))),
        store,
        RouteConfig::parse("[route]\ndefault = \"direct\"\n").unwrap(),
        NeverProbe,
    )
    .unwrap()
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

#[derive(Clone)]
struct OfflineTransport(Arc<std::sync::Mutex<Vec<HttpRequest>>>);
#[async_trait]
impl HttpTransport for OfflineTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.0.lock().unwrap().push(request.clone());
        let body = if request.url.ends_with("/api/uc/status") {
            include_bytes!("../../../../fixtures/auth/userinfo-success.json").to_vec()
        } else if request.url.contains("currentUser.do") {
            b"{}".to_vec()
        } else if request.url.contains("teachingSchedule/detail.do") {
            include_bytes!("../../../../fixtures/readonly/schedule-today.json").to_vec()
        } else {
            panic!("未预期的合成请求");
        };
        Ok(HttpResponse::new(200, request.url, body))
    }
}
