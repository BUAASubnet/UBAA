use super::*;
use ubaa_core::facade::{CacheKey, CacheLimits, CachePayload, CachePublication, OfflineCache};
#[derive(Clone)]
struct CacheTransport {
    mode: Arc<AtomicUsize>,
    calls: Arc<AtomicUsize>,
    cache_root: Arc<std::path::PathBuf>,
}
#[async_trait]
impl HttpTransport for CacheTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        let url = url::Url::parse(&request.url).unwrap();
        let path = url.path();
        let mode = self.mode.load(Ordering::SeqCst);
        let classify = if mode == 3 { 2 } else { 1 };
        if path == "/uc/api/oauth/index" {
            return Ok(HttpResponse::new(
                200,
                "https://ygdk.buaa.edu.cn/#/home?code=synthetic",
                Vec::new(),
            ));
        }
        let body = match path {
            "/api/uc/status" => include_str!("../../../../fixtures/auth/userinfo-success.json").to_owned(),
            "/api/Front/Clockin/User/campusAppLogin" => r#"{"code":1,"result":{"uid":1,"token":"synthetic"}}"#.into(),
            "/api/Front/Clockin/Classify/getList" => serde_json::json!({"code":1,"result":{"list":[{"classify_id":classify,"name":"合成体育"}]}}).to_string(),
            "/api/Front/Clockin/Item/getList" => r#"{"code":1,"result":{"list":[{"item_id":2,"name":"合成跑步"}]}}"#.into(),
            "/api/Front/Clockin/Clockin/getCount" => r#"{"code":1,"result":{"term_count":3}}"#.into(),
            "/api/Front/Clockin/Term/get" => r#"{"code":1,"result":{"term_id":7,"name":"合成学期"}}"#.into(),
            "/api/Front/Clockin/Clockin/getList" => {
                if mode == 6 || mode == 7 {
                    let mut repo = ubaa_core::facade::OfflineRepository::open(&self.cache_root,
                        "0123456789abcdef0123456789abcdef", CacheKey::new([4; 32]), CacheLimits::default()).unwrap();
                    repo.begin_read(ubaa_core::facade::CacheScope { route: ConnectionMode::Direct,
                        query: ubaa_core::facade::CacheQuery::YgdkRecordsSelection }).unwrap();
                }

                let query: std::collections::HashMap<_, _> = url.query_pairs().collect();
                let form: std::collections::HashMap<_, _> = url::form_urlencoded::parse(&request.body).collect();
                for key in ["page", "limit", "classify_id", "user_id"] { assert_eq!(query.get(key), form.get(key)); }
                assert_eq!(query.get("classify_id").unwrap(), &classify.to_string());
                assert!(!query.contains_key("token"));
                if mode == 1 || mode == 7 { return Ok(HttpResponse::new(503, request.url, Vec::new())); }
                if mode == 2 { r#"{"code":1,"result":{}}"#.into() }
                else if mode == 4 { r#"{"code":1,"result":{"list":[],"total":0}}"#.into() }
                else { r#"{"code":1,"result":{"list":[{"record_id":11,"item_id":2,"place":"合成操场","images":["https://synthetic.invalid/photo"]}],"total":30}}"#.into() }
            }
            _ => panic!("出现非只读合成请求"),
        };
        Ok(HttpResponse::new(200, request.url, body.into_bytes()))
    }
}
fn setup(root: &std::path::Path) -> (UbaaClient, OfflineCache, CacheTransport) {
    let store = FileSessionStore::new(root).unwrap();
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: Vec::new(),
            authenticated_at: 1000,
            last_activity: 1001,
        })
        .unwrap();
    let transport = CacheTransport {
        mode: Arc::new(AtomicUsize::new(0)),
        calls: Arc::new(AtomicUsize::new(0)),
        cache_root: Arc::new(root.to_owned()),
    };
    let client = UbaaClient::with_routing(
        transport.clone(),
        CountingTransport(Arc::new(AtomicUsize::new(0))),
        store,
        RouteConfig::parse("[route]\ndefault = \"direct\"\n").unwrap(),
        NeverProbe,
    )
    .unwrap();
    let cache = OfflineCache::open(
        root,
        "0123456789abcdef0123456789abcdef",
        "fixture-user",
        CacheKey::new([4; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    (client, cache, transport)
}

#[test]
fn 阳光记录按分类页码隔离且失败不抹旧记录或保存照片地址() {
    let root = test_root("ygdk-record-cache");
    let (mut client, cache, transport) = setup(&root);
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let fresh = runtime
        .block_on(client.refresh_cached_ygdk_records(&cache, 2, 5))
        .unwrap();
    assert!(fresh.complete);
    let old = cache
        .read_ygdk_records(ConnectionMode::Direct, 1, 2, 5)
        .unwrap()
        .unwrap();
    let CachePayload::YgdkRecords(saved) = &old.payload else {
        panic!("必须为阳光记录")
    };
    assert_eq!(saved.content[0].image_count, 1);
    assert!(!serde_json::to_string(saved).unwrap().contains("https://"));
    assert!(
        cache
            .read_ygdk_records(ConnectionMode::Direct, 2, 2, 5)
            .unwrap()
            .is_none()
    );
    assert!(
        cache
            .read_ygdk_records(ConnectionMode::Direct, 1, 1, 5)
            .unwrap()
            .is_none()
    );
    assert!(
        cache
            .read_ygdk_records(ConnectionMode::WebVpn, 1, 2, 5)
            .unwrap()
            .is_none()
    );
    transport.mode.store(1, Ordering::SeqCst);
    assert!(
        runtime
            .block_on(client.refresh_cached_ygdk_records(&cache, 2, 5))
            .is_err()
    );
    transport.mode.store(2, Ordering::SeqCst);
    let partial = runtime
        .block_on(client.refresh_cached_ygdk_records(&cache, 2, 5))
        .unwrap();
    assert!(!partial.complete);
    assert_eq!(partial.publication, Some(CachePublication::Preserved));
    assert_eq!(
        cache
            .read_ygdk_records(ConnectionMode::Direct, 1, 2, 5)
            .unwrap()
            .unwrap()
            .payload,
        old.payload
    );
    transport.mode.store(3, Ordering::SeqCst);
    runtime
        .block_on(client.refresh_cached_ygdk_records(&cache, 2, 5))
        .unwrap();
    let CachePayload::YgdkRecordsSelection(selected) = cache
        .read_ygdk_records_selection(ConnectionMode::Direct)
        .unwrap()
        .unwrap()
        .payload
    else {
        panic!("必须为分类索引")
    };
    assert_eq!(selected.classify_id, 2);
    assert!(
        cache
            .read_ygdk_records(ConnectionMode::Direct, 1, 2, 5)
            .unwrap()
            .is_some()
    );
    transport.mode.store(4, Ordering::SeqCst);
    runtime
        .block_on(client.refresh_cached_ygdk_records(&cache, 2, 5))
        .unwrap();
    let CachePayload::YgdkRecords(empty) = cache
        .read_ygdk_records(ConnectionMode::Direct, 1, 2, 5)
        .unwrap()
        .unwrap()
        .payload
    else {
        panic!("必须为记录")
    };
    assert!(empty.content.is_empty());
    let before = transport.calls.load(Ordering::SeqCst);
    assert!(
        runtime
            .block_on(client.refresh_cached_ygdk_records(&cache, 0, 5))
            .is_err()
    );
    assert_eq!(transport.calls.load(Ordering::SeqCst), before);
    drop(cache);
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 阳光分类索引被替代后旧请求不能发布数据页() {
    let root = test_root("ygdk-record-parent-fence");
    let (mut client, cache, transport) = setup(&root);
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    runtime
        .block_on(client.refresh_cached_ygdk_records(&cache, 2, 5))
        .unwrap();
    let old = cache
        .read_ygdk_records(ConnectionMode::Direct, 1, 2, 5)
        .unwrap()
        .unwrap();
    for mode in [6, 7] {
        transport.mode.store(mode, Ordering::SeqCst);
        let error = runtime
            .block_on(client.refresh_cached_ygdk_records(&cache, 2, 5))
            .unwrap_err();
        if mode == 6 {
            assert!(matches!(
                error,
                ubaa_core::facade::OfflineReadError::Cache(
                    ubaa_core::facade::CacheError::Superseded
                )
            ));
        }
        let current = cache
            .read_ygdk_records(ConnectionMode::Direct, 1, 2, 5)
            .unwrap()
            .unwrap();
        assert_eq!(current.revision, old.revision);
        assert_eq!(current.last_attempt_succeeded, old.last_attempt_succeeded);
    }
    drop(cache);
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}
