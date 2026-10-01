use super::*;
use ubaa_core::facade::{
    CacheError, CacheKey, CacheLimits, CachePayload, LibBookCacheQuery, OfflineCache,
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
        if path == "/login" {
            let mut response = HttpResponse::new(302, request.url, Vec::new());
            response.headers.insert(
                "Location".into(),
                vec!["https://booking.lib.buaa.edu.cn/v4/login/cas?cas=synthetic".into()],
            );
            return Ok(response);
        }
        if path == "/v4/login/user" {
            return Ok(HttpResponse::new(
                200,
                request.url,
                br#"{"code":0,"data":{"member":{"token":"synthetic"}}}"#.to_vec(),
            ));
        }
        let mode = self.mode.load(Ordering::SeqCst);
        assert_eq!(
            request.headers.get("Authorization").map(String::as_str),
            Some("bearersynthetic")
        );
        let input: serde_json::Value = serde_json::from_slice(&request.body).unwrap();
        let body = match path.as_str() {
            _ if mode == 4 => r#"{"code":1,"data":{}}"#,
            "/v4/space/pcTopFor" => {
                assert_eq!(input["day"], "2026-09-22");
                r#"{"code":1,"data":{"list":[{"id":"p1","name":"合成楼馆"}]}}"#
            }
            "/v4/space/pick" => {
                assert_eq!(input["premisesIds"], "p1");
                assert_eq!(input["storeyIds"], serde_json::json!(["f1"]));
                r#"{"code":1,"data":{"area":[{"id":"a1","name":"合成分区"}]}}"#
            }
            "/v4/Space/map" if mode == 5 => {
                r#"{"code":1,"data":{"area":{"id":"a1"},"date":{"list":[{"day":"2026-10-02","times":[{"id":"m1","start":"08:00","end":"09:00"}]},{"day":"2026-10-03","times":[{"id":"m2","start":"14:00","end":"15:00"}]}]}}}"#
            }
            "/v4/Space/map" => r#"{"code":1,"data":{"area":{"id":"a1"},"date":{"list":[]}}}"#,
            "/v4/Space/seat" => {
                assert_eq!(input["id"], "a1");
                assert_eq!(input["start_time"], "08:00");
                assert_eq!(input["end_time"], "09:00");
                r#"{"code":1,"data":{"list":[{"id":"s1","status":"1","name":"合成座位"}]}}"#
            }
            "/v4/member/seat" => match mode {
                2 => r#"{"code":1,"data":{"data":[],"current_page":2,"per_page":20}}"#,
                3 => r#"{"code":1,"data":{"data":[],"current_page":1,"per_page":20}}"#,
                _ => {
                    r#"{"code":1,"data":{"data":[{"id":"b1","status":"1"}],"current_page":1,"per_page":20}}"#
                }
            },
            _ => panic!("出现未授权的合成请求"),
        };
        Ok(HttpResponse::new(
            if mode == 1 { 503 } else { 200 },
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
fn 图书馆五范围失败保留错页拒绝且合法空页替换() {
    let root = test_root("libbook-cache");
    let (mut client, cache, transport) = setup(&root);
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    for query in [
        LibBookCacheQuery::Libraries {
            day: "2026-09-22".into(),
        },
        LibBookCacheQuery::Areas {
            premises_id: "p1".into(),
            storey_id: Some("f1".into()),
            day: "2026-09-22".into(),
        },
        LibBookCacheQuery::AreaDetail {
            area_id: "a1".into(),
        },
        LibBookCacheQuery::Seats {
            area_id: "a1".into(),
            day: "2026-09-22".into(),
            start_time: "08:00".into(),
            end_time: "09:00".into(),
        },
        LibBookCacheQuery::Bookings { page: 1, limit: 20 },
    ] {
        let online = runtime
            .block_on(client.refresh_cached_libbook(&cache, query.clone()))
            .unwrap();
        assert!(online.complete);
        assert!(online.result.save_error.is_none());
        let old = cache
            .read_libbook(ConnectionMode::Direct, &query)
            .unwrap()
            .unwrap();
        assert!(
            cache
                .read_libbook(ConnectionMode::WebVpn, &query)
                .unwrap()
                .is_none()
        );
        transport.mode.store(1, Ordering::SeqCst);
        assert!(
            runtime
                .block_on(client.refresh_cached_libbook(&cache, query.clone()))
                .is_err()
        );
        assert_eq!(
            cache
                .read_libbook(ConnectionMode::Direct, &query)
                .unwrap()
                .unwrap()
                .payload,
            old.payload
        );
        transport.mode.store(4, Ordering::SeqCst);
        let partial = runtime
            .block_on(client.refresh_cached_libbook(&cache, query.clone()))
            .unwrap();
        assert!(!partial.complete);
        assert_eq!(
            cache
                .read_libbook(ConnectionMode::Direct, &query)
                .unwrap()
                .unwrap()
                .payload,
            old.payload
        );
        transport.mode.store(0, Ordering::SeqCst);
    }
    check_bookings(&mut client, &cache, &transport, &runtime);
    drop(cache);
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}

fn check_bookings(
    client: &mut UbaaClient,
    cache: &OfflineCache,
    transport: &CacheTransport,
    runtime: &tokio::runtime::Runtime,
) {
    let query = LibBookCacheQuery::Bookings { page: 1, limit: 20 };
    transport.mode.store(2, Ordering::SeqCst);
    let wrong = runtime
        .block_on(client.refresh_cached_libbook(cache, query.clone()))
        .unwrap();
    assert!(!wrong.complete);
    assert_eq!(wrong.result.save_error, Some(CacheError::InvalidInput));
    let CachePayload::LibBookBookings(saved) = cache
        .read_libbook(ConnectionMode::Direct, &query)
        .unwrap()
        .unwrap()
        .payload
    else {
        panic!("载荷类型错误")
    };
    assert_eq!(saved.bookings.len(), 1);
    transport.mode.store(3, Ordering::SeqCst);
    assert!(
        runtime
            .block_on(client.refresh_cached_libbook(cache, query.clone()))
            .unwrap()
            .complete
    );
    let CachePayload::LibBookBookings(saved) = cache
        .read_libbook(ConnectionMode::Direct, &query)
        .unwrap()
        .unwrap()
        .payload
    else {
        panic!("载荷类型错误")
    };
    assert!(saved.bookings.is_empty());
    let calls = transport.calls.load(Ordering::SeqCst);
    assert!(
        runtime
            .block_on(
                client.refresh_cached_libbook(
                    cache,
                    LibBookCacheQuery::Bookings { page: 0, limit: 20 }
                )
            )
            .is_err()
    );
    assert_eq!(transport.calls.load(Ordering::SeqCst), calls);
}

#[test]
fn 图书馆缓存重读保留逐日时段且旧详情不扩张序列化() {
    let root = test_root("libbook-schedule-cache");
    let (mut client, cache, transport) = setup(&root);
    transport.mode.store(5, Ordering::SeqCst);
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let query = LibBookCacheQuery::AreaDetail {
        area_id: "a1".into(),
    };
    let fresh = runtime
        .block_on(client.refresh_cached_libbook(&cache, query.clone()))
        .unwrap();
    assert!(fresh.result.save_error.is_none());
    let CachePayload::LibBookAreaDetail(detail) = cache
        .read_libbook(ConnectionMode::Direct, &query)
        .unwrap()
        .unwrap()
        .payload
    else {
        panic!("应是同分区日程");
    };
    let schedule = detail.schedule.unwrap();
    assert_eq!(schedule.days.len(), 2);
    assert_eq!(schedule.days[0].day, "2026-10-02");
    assert_eq!(schedule.days[0].time_slots[0].start, "08:00");
    assert_eq!(schedule.days[1].day, "2026-10-03");
    assert_eq!(schedule.days[1].time_slots[0].start, "14:00");
    let legacy = runtime.block_on(client.libbook_area_detail("a1")).unwrap();
    assert!(
        !serde_json::to_string(&legacy.data)
            .unwrap()
            .contains("schedule")
    );
    drop(cache);
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}
