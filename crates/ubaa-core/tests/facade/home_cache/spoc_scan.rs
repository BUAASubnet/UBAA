use super::*;
use ubaa_core::facade::{
    CacheError, CachePublication, CacheScope, OfflineReadError, SpocScanCancellation,
};
#[derive(Clone)]
struct Pages {
    base: HomeTransport,
    flags: Arc<AtomicUsize>,
    page: Arc<AtomicUsize>,
    cancel: Arc<std::sync::Mutex<Option<SpocScanCancellation>>>,
}
impl Default for Pages {
    fn default() -> Self {
        Self {
            base: HomeTransport {
                mode: Arc::new(AtomicUsize::new(0)),
                requests: Arc::new(std::sync::Mutex::new(Vec::new())),
            },
            flags: Arc::new(AtomicUsize::new(0)),
            page: Arc::new(AtomicUsize::new(0)),
            cancel: Arc::new(std::sync::Mutex::new(None)),
        }
    }
}
#[async_trait]
impl HttpTransport for Pages {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let flags = self.flags.load(Ordering::SeqCst);
        let term = if flags & 8 != 0 {
            "synthetic-new-term"
        } else {
            "2025-20262"
        };
        let body = if request.url.ends_with("/queryOne") {
            self.page.store(0, Ordering::SeqCst);
            serde_json::json!({"code":200,"content":{"mrxq":term,"dqxq":"合成学期"}})
        } else if request.url.ends_with("/queryListByPage") {
            let page = self.page.fetch_add(1, Ordering::SeqCst) + 1;
            if let Some(cancel) = self.cancel.lock().unwrap().take() {
                cancel.cancel();
            }
            if flags & 1 != 0 && page == 2 {
                return Ok(HttpResponse::new(503, request.url, Vec::new()));
            }
            serde_json::json!({"code":200,"content":{
                "pageNum":page,"pageSize":if flags & 32 != 0 { 30 } else { 15 },"pages":2,"hasNextPage":page == 1 && flags & 64 == 0,
                "list":[{"zyid": if flags & 16 != 0 { "a1".to_string() } else { format!("a{page}") }, "zymc":"合成作业","sskcid":"course-1", "xnxq":if flags & 4 != 0 { "wrong-term" } else {term}}]
            }})
        } else {
            return self.base.execute(request).await;
        };
        self.base.requests.lock().unwrap().push(request.clone());
        Ok(HttpResponse::new(
            200,
            request.url,
            serde_json::to_vec(&body).unwrap(),
        ))
    }
}
fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}
fn scope(term: &str, page: u32) -> CacheScope {
    CacheScope {
        route: ConnectionMode::Direct,
        query: CacheQuery::SpocPage {
            term: term.into(),
            page,
            size: 15,
        },
    }
}

#[test]
fn spoc_逐页读取之间可读取签到_精确页和学期持久化_部分新学期保留旧选择() {
    let root = test_root("spoc-page-interleave");
    let transport = Pages::default();
    let (mut client, cache) = setup(&root, transport.clone());
    rt().block_on(async {
        let mut plan = client
            .begin_spoc_scan(Some(&cache), Some("fixture-user"))
            .await
            .unwrap();
        assert_eq!(transport.page.load(Ordering::SeqCst), 0);
        assert_eq!(
            client
                .next_spoc_scan(&mut plan)
                .await
                .unwrap()
                .completed_pages,
            0
        );
        assert_eq!(
            client
                .next_spoc_scan(&mut plan)
                .await
                .unwrap()
                .completed_pages,
            0
        );
        let first = client.next_spoc_scan(&mut plan).await.unwrap();
        assert_eq!(first.data.assignments.len(), 1);
        assert!(!first.finished);
        assert!(!first.complete);
        assert!(
            cache
                .read_home(ConnectionMode::Direct, &HomeQuery::SpocAssignments)
                .unwrap()
                .is_none()
        );
        let page = cache
            .read(&scope("2025-20262", 1), first.fetched_at)
            .unwrap()
            .unwrap();
        assert_eq!(page.completeness, CacheCompleteness::Complete);
        client.signin_today().await.unwrap();
        assert_eq!(transport.page.load(Ordering::SeqCst), 1);
        let last = client.next_spoc_scan(&mut plan).await.unwrap();
        assert!(last.finished && last.complete);
        assert_eq!(last.data.assignments.len(), 2);
        assert_eq!(last.publication, Some(CachePublication::Stored));
        assert_eq!(last.fetched_at, first.fetched_at);
        let old = cache
            .read_home(ConnectionMode::Direct, &HomeQuery::SpocAssignments)
            .unwrap()
            .unwrap();
        assert_eq!(
            old.scope.query,
            CacheQuery::SpocTerm {
                term: "2025-20262".into()
            }
        );
        transport.flags.store(8 | 16, Ordering::SeqCst);
        let partial = client
            .refresh_cached_home(&cache, HomeQuery::SpocAssignments)
            .await
            .unwrap();
        assert!(!partial.complete);
        assert_eq!(
            cache
                .read_home(ConnectionMode::Direct, &HomeQuery::SpocAssignments)
                .unwrap()
                .unwrap()
                .payload,
            old.payload
        );
        transport.flags.store(8, Ordering::SeqCst);
        let new = client
            .refresh_cached_home(&cache, HomeQuery::SpocAssignments)
            .await
            .unwrap();
        assert!(new.complete);
        assert_ne!(new.result.scope, old.scope);
        assert!(
            cache
                .read(&old.scope, new.result.fetched_at)
                .unwrap()
                .is_some()
        );
        assert!(
            cache
                .read(&scope("synthetic-new-term", 2), new.result.fetched_at)
                .unwrap()
                .is_some()
        );
        assert!(
            cache
                .read_home(ConnectionMode::WebVpn, &HomeQuery::SpocAssignments)
                .unwrap()
                .is_none()
        );
    });
    drop(cache);
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn spoc_中途网络失败不清空_错学期错页大小拒绝_矛盾页尾只算部分() {
    let root = test_root("spoc-page-failures");
    let transport = Pages::default();
    let (mut client, cache) = setup(&root, transport.clone());
    rt().block_on(async {
        client
            .refresh_cached_home(&cache, HomeQuery::SpocAssignments)
            .await
            .unwrap();
        let old = cache
            .read_home(ConnectionMode::Direct, &HomeQuery::SpocAssignments)
            .unwrap()
            .unwrap();
        for flags in [1, 4, 32] {
            transport.flags.store(flags, Ordering::SeqCst);
            assert!(
                client
                    .refresh_cached_home(&cache, HomeQuery::SpocAssignments)
                    .await
                    .is_err()
            );
            let saved = cache
                .read_home(ConnectionMode::Direct, &HomeQuery::SpocAssignments)
                .unwrap()
                .unwrap();
            assert_eq!(saved.payload, old.payload);
            assert_eq!(saved.fetched_at, old.fetched_at);
        }
        transport.flags.store(64, Ordering::SeqCst);
        let partial = client
            .refresh_cached_home(&cache, HomeQuery::SpocAssignments)
            .await
            .unwrap();
        assert!(!partial.complete, "总页数为2而第一页宣告结束不能宣称完整");
    });
    drop(cache);
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn spoc_新请求取消退出清理和客户端替换拒绝旧计划且不发新页() {
    for reason in 0..5 {
        let root = test_root(&format!("spoc-stale-{reason}"));
        let transport = Pages::default();
        let (mut client, cache) = setup(&root, transport.clone());
        rt().block_on(async {
            let mut plan = client.begin_spoc_scan(Some(&cache), None).await.unwrap();
            client.next_spoc_scan(&mut plan).await.unwrap();
            client.next_spoc_scan(&mut plan).await.unwrap();
            match reason {
                0 => {
                    let _newer = client.begin_spoc_scan(Some(&cache), None).await.unwrap();
                }
                1 => plan.cancellation().cancel(),
                2 => cache.clear().unwrap(),
                3 => cache.deactivate().unwrap(),
                _ => {
                    client = setup(&root.join("replacement"), transport.clone()).0;
                }
            }
            assert!(client.next_spoc_scan(&mut plan).await.is_err());
            assert_eq!(transport.page.load(Ordering::SeqCst), 0);
        });
        drop(cache);
        drop(client);
        std::fs::remove_dir_all(root).unwrap();
    }
}
#[test]
fn spoc_请求期间取消拒绝回写_无缓存仍核对身份并按页返回() {
    let root = test_root("spoc-online-cancel");
    let transport = Pages::default();
    let (mut client, cache) = setup(&root, transport.clone());
    rt().block_on(async {
        assert!(matches!(
            client.begin_spoc_scan(None, Some("different-user")).await,
            Err(OfflineReadError::IdentityMismatch { .. })
        ));
        assert_eq!(transport.page.load(Ordering::SeqCst), 0);
        let mut plan = client.begin_spoc_scan(Some(&cache), None).await.unwrap();
        client.next_spoc_scan(&mut plan).await.unwrap();
        client.next_spoc_scan(&mut plan).await.unwrap();
        *transport.cancel.lock().unwrap() = Some(plan.cancellation());
        assert!(matches!(
            client.next_spoc_scan(&mut plan).await,
            Err(OfflineReadError::Cache(CacheError::Superseded))
        ));
        assert!(
            cache
                .read(&scope("2025-20262", 1), chrono::Utc::now().timestamp())
                .unwrap()
                .is_none()
        );
        let mut online = client
            .begin_spoc_scan(None, Some("fixture-user"))
            .await
            .unwrap();
        loop {
            let batch = client.next_spoc_scan(&mut online).await.unwrap();
            assert!(batch.publication.is_none());
            if batch.finished {
                assert!(batch.complete);
                assert_eq!(batch.data.assignments.len(), 2);
                break;
            }
        }
        assert!(
            cache
                .read_home(ConnectionMode::Direct, &HomeQuery::SpocAssignments)
                .unwrap()
                .is_none()
        );
    });
    drop(cache);
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}
