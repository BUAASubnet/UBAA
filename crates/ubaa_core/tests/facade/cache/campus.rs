use super::*;
use ubaa_core::facade::{CacheKey, CacheLimits, CachePayload, CampusCacheQuery, OfflineCache};

#[derive(Clone)]
struct CampusTransport(Arc<AtomicUsize>);
#[async_trait]
impl HttpTransport for CampusTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let path = url::Url::parse(&request.url).unwrap().path().to_owned();
        let body = match path.as_str() {
            "/api/uc/status" => include_str!("../../../../../fixtures/auth/userinfo-success.json"),
            "/personal/frontend/data/info" if self.0.load(Ordering::SeqCst) == 0 => {
                include_str!("../../../../../fixtures/readonly/campus/profile.json")
            }
            "/personal/frontend/data/info" => r#"{"e":1,"m":"合成失败"}"#,
            "/home" => include_str!("../../../../../fixtures/readonly/campus/network.html"),
            _ => panic!("出现未预期请求：{path}"),
        };
        Ok(HttpResponse::new(
            200,
            request.url,
            body.as_bytes().to_vec(),
        ))
    }
}

#[test]
fn 校园快照端到端保留成功值且拒绝错误账号与退出后读取() {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("../../.ubaa_local/supervision/closeout_20261031")
                .join(format!("campus-facade-{}", std::process::id()));
            let store = FileSessionStore::new(&root).unwrap();
            store
                .save(&SessionSnapshot {
                    mode: ConnectionMode::Direct,
                    cookies: vec![],
                    authenticated_at: 1000,
                    last_activity: 1001,
                })
                .unwrap();
            let fail = Arc::new(AtomicUsize::new(0));
            let mut client = UbaaClient::with_routing(
                CampusTransport(fail.clone()),
                CountingTransport(Arc::new(AtomicUsize::new(0))),
                store,
                RouteConfig::parse("[route]\ndefault = \"direct\"\n").unwrap(),
                NeverProbe,
            )
            .unwrap();
            let cache = OfflineCache::open(
                &root,
                "0123456789abcdef0123456789abcdef",
                "fixture-user",
                CacheKey::new([4; 32]),
                CacheLimits::default(),
            )
            .unwrap();
            for query in [CampusCacheQuery::Profile, CampusCacheQuery::NetworkUsage] {
                let online = client.refresh_cached_campus(&cache, query).await.unwrap();
                assert!(online.result.save_error.is_none());
                assert!(online.publication.is_some());
                let saved = cache
                    .read_campus(ConnectionMode::Direct, query)
                    .unwrap()
                    .unwrap();
                assert!(matches!(
                    saved.payload,
                    CachePayload::CampusProfile(_) | CachePayload::NetworkUsage(_)
                ));
                assert!(
                    cache
                        .read_campus(ConnectionMode::WebVpn, query)
                        .unwrap()
                        .is_none()
                );
            }
            let previous = cache
                .read_campus(ConnectionMode::Direct, CampusCacheQuery::Profile)
                .unwrap()
                .unwrap();
            fail.store(1, Ordering::SeqCst);
            assert!(
                client
                    .refresh_cached_campus(&cache, CampusCacheQuery::Profile)
                    .await
                    .is_err()
            );
            let saved = cache
                .read_campus(ConnectionMode::Direct, CampusCacheQuery::Profile)
                .unwrap()
                .unwrap();
            assert_eq!(saved.payload, previous.payload);
            assert_eq!(saved.fetched_at, previous.fetched_at);
            let other = OfflineCache::open(
                &root,
                "abcdef0123456789abcdef0123456789",
                "other-user",
                CacheKey::new([5; 32]),
                CacheLimits::default(),
            )
            .unwrap();
            assert!(
                client
                    .refresh_cached_campus(&other, CampusCacheQuery::Profile)
                    .await
                    .is_err()
            );
            cache.deactivate().unwrap();
            assert!(
                cache
                    .read_campus(ConnectionMode::Direct, CampusCacheQuery::Profile)
                    .is_err()
            );
            drop((cache, other, client));
            std::fs::remove_dir_all(root).unwrap();
        });
}
