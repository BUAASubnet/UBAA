use super::*;
use std::sync::{Mutex, atomic::AtomicBool};
use ubaa_core::facade::{CacheError, CacheKey, CacheLimits, OfflineCache, OfflineReadError};
#[derive(Clone)]
struct Transport {
    old: OfflineCache,
    next: Arc<Mutex<Option<OfflineCache>>>,
    reset: Arc<AtomicBool>,
    calls: Arc<AtomicUsize>,
}
#[async_trait]
impl HttpTransport for Transport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        let url = url::Url::parse(&request.url).unwrap();
        assert!(matches!(url.path(), "/api/uc/status" | "/api/uc/userinfo"));
        if self.reset.swap(false, Ordering::SeqCst) {
            assert_eq!(url.path(), "/api/uc/status");
            let (next, report) = self.old.clear_and_reopen().unwrap();
            assert_eq!(report.usage.unwrap().entry_count, 0);
            *self.next.lock().unwrap() = Some(next);
        }
        Ok(HttpResponse::new(
            200,
            request.url,
            include_bytes!("../../../../../fixtures/auth/userinfo-success.json").to_vec(),
        ))
    }
}
fn setup(root: &std::path::Path) -> (UbaaClient, OfflineCache, Transport) {
    let store = FileSessionStore::new(root).unwrap();
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: vec![],
            authenticated_at: 1000,
            last_activity: 1001,
        })
        .unwrap();
    let cache = OfflineCache::open(
        root,
        "0123456789abcdef0123456789abcdef",
        "fixture-user",
        CacheKey::new([9; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    let transport = Transport {
        old: cache.clone(),
        next: Arc::default(),
        reset: Arc::new(AtomicBool::new(false)),
        calls: Arc::new(AtomicUsize::new(0)),
    };
    let client = UbaaClient::with_routing(
        transport.clone(),
        CountingTransport(Arc::new(AtomicUsize::new(0))),
        store,
        RouteConfig::parse("[route]\ndefault = \"direct\"\n").unwrap(),
        NeverProbe,
    )
    .unwrap();
    (client, cache, transport)
}
#[test]
fn 清理返回新句柄而旧克隆及独立连接不能再读取或取票() {
    let root = test_root("cache-management");
    let (mut client, cache, transport) = setup(&root);
    let other = OfflineCache::open(
        &root,
        "0123456789abcdef0123456789abcdef",
        "fixture-user",
        CacheKey::new([9; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    let copied = cache.clone();
    let (next, report) = cache.clear_and_reopen().unwrap();
    assert!(report.compacted);
    for old in [&cache, &copied, &other] {
        assert_eq!(old.usage(), Err(CacheError::Superseded));
        assert_eq!(old.activate(), Err(CacheError::Superseded));
    }
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    runtime.block_on(async {
        assert!(matches!(
            client.refresh_cached_profile(&copied).await,
            Err(OfflineReadError::Cache(CacheError::Superseded))
        ));
        assert!(matches!(
            client.begin_judge_scan(&copied, false, None).await,
            Err(OfflineReadError::Cache(CacheError::Superseded))
        ));
        assert_eq!(transport.calls.load(Ordering::SeqCst), 0);
        client.refresh_cached_profile(&next).await.unwrap();
        assert_eq!(next.usage().unwrap().entry_count, 1);
    });
    let _ = std::fs::remove_dir_all(root);
}
#[test]
fn 清理发生在认证返回前也不能让旧读取链取得新票据() {
    let root = test_root("cache-management-auth");
    let (mut client, cache, transport) = setup(&root);
    transport.reset.store(true, Ordering::SeqCst);
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    runtime.block_on(async {
        assert!(matches!(
            client.refresh_cached_profile(&cache).await,
            Err(OfflineReadError::Cache(CacheError::Superseded))
        ));
        assert_eq!(transport.calls.load(Ordering::SeqCst), 1);
        let next = transport.next.lock().unwrap().take().unwrap();
        assert_eq!(next.usage().unwrap().entry_count, 0);
        client.refresh_cached_profile(&next).await.unwrap();
        assert_eq!(next.usage().unwrap().entry_count, 1);
    });
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 本地控制记录损坏不阻断原在线读取且不保存新内容() {
    let root = test_root("cache-management-corrupt");
    let (mut client, cache, transport) = setup(&root);
    let db = rusqlite::Connection::open(
        root.join("business-cache/0123456789abcdef0123456789abcdef.sqlite"),
    )
    .unwrap();
    db.execute("UPDATE control SET body=?1", [vec![0_u8; 32]])
        .unwrap();
    drop(db);
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let result = runtime
        .block_on(client.refresh_cached_profile(&cache))
        .unwrap();
    assert_eq!(result.save_error, Some(CacheError::Corrupt));
    assert_eq!(result.data.username.as_deref(), Some("fixture-user"));
    assert_eq!(transport.calls.load(Ordering::SeqCst), 2);
    assert_eq!(cache.usage(), Err(CacheError::Corrupt));
    let _ = std::fs::remove_dir_all(root);
}
