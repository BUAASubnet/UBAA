use super::*;
use ubaa_core::facade::{
    CacheCompleteness, CacheError, CacheKey, CacheLimits, CachePayload, CachePublication,
    CgyyCacheQuery, CgyyReadData, OfflineCache,
};
#[derive(Clone)]
struct CacheTransport {
    mode: Arc<AtomicUsize>,
    calls: Arc<AtomicUsize>,
}
#[async_trait]
impl HttpTransport for CacheTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        let path = url::Url::parse(&request.url).unwrap().path().to_owned();
        if path == "/api/uc/status" {
            return Ok(HttpResponse::new(
                200,
                request.url,
                include_bytes!("../../../../fixtures/auth/userinfo-success.json").to_vec(),
            ));
        }
        if path.ends_with("/sso/manageLogin") {
            let mut response = HttpResponse::new(200, request.url, Vec::new());
            response.headers.insert(
                "Set-Cookie".into(),
                vec!["sso_buaa_zhjs_token=synthetic; Path=/".into()],
            );
            return Ok(response);
        }
        if path.ends_with("/api/login") {
            return Ok(HttpResponse::new(
                200,
                request.url,
                br#"{"code":200,"data":{"token":{"access_token":"synthetic"}}}"#.to_vec(),
            ));
        }
        let mode = self.mode.load(Ordering::SeqCst);
        let body = match path.as_str() {
            "/venue-zhjs-server/api/front/website/venues" => {
                include_str!("../../../../fixtures/readonly/cgyy-sites.json")
            }
            "/venue-zhjs-server/api/codes" => {
                r#"{"code":200,"data":[{"key":3,"name":"合成用途类"}]}"#
            }
            "/venue-zhjs-server/api/reservation/day/info" => {
                include_str!("../../../../fixtures/readonly/cgyy-day.json")
            }
            "/venue-zhjs-server/api/orders/mine" => {
                if mode == 5 {
                    r#"{"code":200,"data":{"content":[],"number":9,"size":20}}"#
                } else if mode == 6 {
                    r#"{"code":200,"data":{"number":0,"size":20}}"#
                } else if mode == 3 {
                    r#"{"code":200,"data":null}"#
                } else {
                    include_str!("../../../../fixtures/readonly/cgyy-orders.json")
                }
            }
            "/venue-zhjs-server/api/orders/9" => {
                if mode == 4 {
                    r#"{"code":200,"data":null}"#
                } else {
                    r#"{"code":200,"data":{"id":9,"theme":"合成主题","orderStatus":1}}"#
                }
            }
            _ => panic!("出现未授权的合成请求"),
        };
        if mode == 2 || (mode == 1 && path.ends_with("/api/codes")) {
            return Ok(HttpResponse::new(503, request.url, b"synthetic".to_vec()));
        }
        Ok(HttpResponse::new(
            200,
            request.url,
            body.as_bytes().to_vec(),
        ))
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
fn 研讨室五范围持久化且错日期与失败不覆盖() {
    let root = test_root("cgyy-cache");
    let (mut client, cache, transport) = setup(&root);
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    for query in [
        CgyyCacheQuery::Sites,
        CgyyCacheQuery::Purposes,
        CgyyCacheQuery::Day {
            site_id: 4,
            date: "2026-03-29".into(),
        },
        CgyyCacheQuery::Orders { page: 0, size: 20 },
        CgyyCacheQuery::Detail { order_id: 9 },
    ] {
        let online = runtime
            .block_on(client.refresh_cached_cgyy(&cache, query.clone()))
            .unwrap();
        assert!(online.complete);
        assert_eq!(online.publication, Some(CachePublication::Stored));
        assert!(online.result.save_error.is_none());
        let old = cache
            .read_cgyy(ConnectionMode::Direct, &query)
            .unwrap()
            .unwrap();
        assert!(
            cache
                .read_cgyy(ConnectionMode::WebVpn, &query)
                .unwrap()
                .is_none()
        );
        if query != CgyyCacheQuery::Purposes {
            transport.mode.store(2, Ordering::SeqCst);
            assert!(
                runtime
                    .block_on(client.refresh_cached_cgyy(&cache, query.clone()))
                    .is_err()
            );
            assert_eq!(
                cache
                    .read_cgyy(ConnectionMode::Direct, &query)
                    .unwrap()
                    .unwrap()
                    .payload,
                old.payload
            );
            transport.mode.store(0, Ordering::SeqCst);
        }
    }
    check_replacement(&mut client, &cache, &runtime, &transport);
    let before = transport.calls.load(Ordering::SeqCst);
    assert!(
        runtime
            .block_on(
                client.refresh_cached_cgyy(&cache, CgyyCacheQuery::Orders { page: -1, size: 20 })
            )
            .is_err()
    );
    assert_eq!(transport.calls.load(Ordering::SeqCst), before);
    drop(cache);
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn 用途静态回退不替代动态完整记录且首次回退标部分() {
    let root = test_root("cgyy-cache-fallback");
    let (mut client, cache, transport) = setup(&root);
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    runtime
        .block_on(client.refresh_cached_cgyy(&cache, CgyyCacheQuery::Purposes))
        .unwrap();
    transport.mode.store(1, Ordering::SeqCst);
    let fallback = runtime
        .block_on(client.refresh_cached_cgyy(&cache, CgyyCacheQuery::Purposes))
        .unwrap();
    assert!(!fallback.complete);
    assert_eq!(fallback.publication, Some(CachePublication::Preserved));
    let CgyyReadData::Purposes(value) = fallback.result.data else {
        panic!("必须为用途")
    };
    assert_eq!(
        value.source,
        ubaa_core::facade::CgyyPurposeSource::StaticFallback
    );
    let record = cache
        .read_cgyy(ConnectionMode::Direct, &CgyyCacheQuery::Purposes)
        .unwrap()
        .unwrap();
    assert_eq!(record.completeness, CacheCompleteness::Complete);
    let CachePayload::CgyyPurposes(value) = record.payload else {
        panic!("必须为用途")
    };
    assert_eq!(value.items[0].name, "合成用途类");
    cache.clear().unwrap();
    let first = runtime
        .block_on(client.refresh_cached_cgyy(&cache, CgyyCacheQuery::Purposes))
        .unwrap();
    assert_eq!(first.publication, Some(CachePublication::Stored));
    assert_eq!(
        cache
            .read_cgyy(ConnectionMode::Direct, &CgyyCacheQuery::Purposes)
            .unwrap()
            .unwrap()
            .completeness,
        CacheCompleteness::Partial
    );
    drop(cache);
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}

fn check_replacement(
    client: &mut UbaaClient,
    cache: &OfflineCache,
    runtime: &tokio::runtime::Runtime,
    transport: &CacheTransport,
) {
    let wrong = CgyyCacheQuery::Day {
        site_id: 4,
        date: "2026-03-30".into(),
    };
    let result = runtime
        .block_on(client.refresh_cached_cgyy(cache, wrong.clone()))
        .unwrap();
    assert!(!result.complete);
    assert_eq!(result.result.save_error, Some(CacheError::InvalidInput));
    assert!(
        cache
            .read_cgyy(ConnectionMode::Direct, &wrong)
            .unwrap()
            .is_none()
    );
    assert!(
        cache
            .read_cgyy(
                ConnectionMode::Direct,
                &CgyyCacheQuery::Orders { page: 1, size: 20 }
            )
            .unwrap()
            .is_none()
    );
    transport.mode.store(3, Ordering::SeqCst);
    runtime
        .block_on(client.refresh_cached_cgyy(cache, CgyyCacheQuery::Orders { page: 0, size: 20 }))
        .unwrap();
    let CachePayload::CgyyOrders(empty) = cache
        .read_cgyy(
            ConnectionMode::Direct,
            &CgyyCacheQuery::Orders { page: 0, size: 20 },
        )
        .unwrap()
        .unwrap()
        .payload
    else {
        panic!("必须为订单")
    };
    assert!(empty.content.is_empty());
    transport.mode.store(4, Ordering::SeqCst);
    let empty_detail = runtime
        .block_on(client.refresh_cached_cgyy(cache, CgyyCacheQuery::Detail { order_id: 9 }))
        .unwrap();
    assert!(!empty_detail.complete);
    assert_eq!(
        empty_detail.result.save_error,
        Some(CacheError::InvalidInput)
    );
    let CachePayload::CgyyDetail(old) = cache
        .read_cgyy(
            ConnectionMode::Direct,
            &CgyyCacheQuery::Detail { order_id: 9 },
        )
        .unwrap()
        .unwrap()
        .payload
    else {
        panic!("必须为详情")
    };
    assert_eq!(old.id, 9);
}

#[test]
fn 订单缓存不接收错页和缺集合且非首页空页沿请求回退() {
    let root = test_root("cgyy-cache-page-scope");
    let (mut client, cache, transport) = setup(&root);
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let query = CgyyCacheQuery::Orders { page: 0, size: 20 };
    runtime
        .block_on(client.refresh_cached_cgyy(&cache, query.clone()))
        .unwrap();
    let old = cache
        .read_cgyy(ConnectionMode::Direct, &query)
        .unwrap()
        .unwrap();
    for mode in [5, 6] {
        transport.mode.store(mode, Ordering::SeqCst);
        let result = runtime
            .block_on(client.refresh_cached_cgyy(&cache, query.clone()))
            .unwrap();
        assert!(!result.complete);
        assert_eq!(
            cache
                .read_cgyy(ConnectionMode::Direct, &query)
                .unwrap()
                .unwrap()
                .payload,
            old.payload
        );
    }
    transport.mode.store(3, Ordering::SeqCst);
    let query = CgyyCacheQuery::Orders { page: 3, size: 10 };
    let result = runtime
        .block_on(client.refresh_cached_cgyy(&cache, query.clone()))
        .unwrap();
    assert!(result.complete);
    assert!(result.result.save_error.is_none());
    let CachePayload::CgyyOrders(page) = cache
        .read_cgyy(ConnectionMode::Direct, &query)
        .unwrap()
        .unwrap()
        .payload
    else {
        panic!("必须为订单页")
    };
    assert_eq!((page.number, page.size), (3, 10));
    assert!(page.content.is_empty());
    drop(cache);
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}
