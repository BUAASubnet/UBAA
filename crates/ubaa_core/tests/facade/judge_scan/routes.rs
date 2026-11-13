use super::*;
use ubaa_core::facade::testing::from_webvpn_url;

#[derive(Clone)]
struct RouteTransport(ScanTransport);
#[async_trait]
impl HttpTransport for RouteTransport {
    async fn execute(&self, mut request: HttpRequest) -> Result<HttpResponse> {
        let outer = request.url.clone();
        request.url = from_webvpn_url(&outer).unwrap();
        let mut response = self.0.execute(request).await?;
        response.final_url = outer;
        Ok(response)
    }
}
#[tokio::test]
async fn 网络未知时分段详情断网仍在独立路线重建选课上下文() {
    for path in ["online", "refresh", "details"] {
        let (root, mut client, cache, vpn) = setup_routes();
        let (resolution, kind) = if path == "refresh" {
            let mut plan = client
                .begin_judge_refresh(&cache, ubaa_core::facade::JudgeRefreshOptions::default())
                .await
                .unwrap();
            assert_eq!(
                client
                    .next_judge_refresh(&mut plan)
                    .await
                    .unwrap()
                    .resolution
                    .mode,
                ConnectionMode::Direct
            );
            let result = client.next_judge_refresh(&mut plan).await.unwrap();

            (result.resolution, result.batch.kind)
        } else if path == "details" {
            let mut plan = client
                .begin_judge_details(
                    &cache,
                    vec![ubaa_core::facade::JudgeAssignmentKey {
                        course_id: "12".into(),
                        assignment_id: "101".into(),
                    }],
                )
                .await
                .unwrap();
            client.next_judge_details(&mut plan).await.unwrap();
            let result = client.next_judge_details(&mut plan).await.unwrap();
            (result.progress.resolution, result.progress.batch.kind)
        } else {
            let mut plan = client
                .begin_judge_online(ubaa_core::facade::JudgeOnlineOptions::default())
                .await
                .unwrap();
            assert_eq!(
                client
                    .next_judge_online(&mut plan)
                    .await
                    .unwrap()
                    .resolution
                    .mode,
                ConnectionMode::Direct
            );
            let result = client.next_judge_online(&mut plan).await.unwrap();
            (result.resolution, result.batch.kind)
        };
        if path != "online" {
            assert_eq!(
                cache
                    .read_judge_detail(ConnectionMode::Direct, "12".into(), "101".into())
                    .unwrap()
                    .unwrap()
                    .scope
                    .route,
                ConnectionMode::WebVpn
            );
        }
        assert_eq!(kind, JudgeScanKind::Detail);
        assert_eq!(resolution.mode, ConnectionMode::WebVpn);
        assert!(
            vpn.requests
                .lock()
                .unwrap()
                .iter()
                .any(|request| request.url.contains("courseID=12"))
        );
        drop((client, cache));
        let _ = std::fs::remove_dir_all(root);
    }
}

fn setup_routes() -> (std::path::PathBuf, UbaaClient, OfflineCache, ScanTransport) {
    struct UnknownProbe;
    impl GatewayProbe for UnknownProbe {
        fn probe(&self, _: Duration) -> NetworkState {
            NetworkState::Unknown
        }
    }
    let root = test_root("judge-scan-domain");
    let store = FileSessionStore::new(&root).unwrap();
    let slot = RouteSessionSnapshot {
        cookies: Vec::new(),
        authenticated_at: 1000,
        last_activity: 1001,
    };
    store
        .save_dual(&DualSessionSnapshot::new(Some(slot.clone()), Some(slot)))
        .unwrap();
    let direct = ScanTransport::default();
    direct.fail_detail.store(true, Ordering::SeqCst);
    let vpn = ScanTransport::default();
    let client = UbaaClient::with_routing(
        RouteTransport(direct),
        RouteTransport(vpn.clone()),
        store,
        RouteConfig::default(),
        UnknownProbe,
    )
    .unwrap();
    let cache = OfflineCache::open(
        &root,
        "0123456789abcdef0123456789abcdef",
        "fixture-user",
        CacheKey::new([9; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    (root, client, cache, vpn)
}
