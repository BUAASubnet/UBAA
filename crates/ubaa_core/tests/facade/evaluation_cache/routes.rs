use super::*;
use ubaa_core::facade::{ErrorKind, UbaaError};
#[derive(Clone)]
struct RouteTransport {
    inner: CacheTransport,
    vpn: bool,
    activated: Arc<std::sync::atomic::AtomicBool>,
}
#[async_trait]
impl HttpTransport for RouteTransport {
    async fn execute(&self, mut request: HttpRequest) -> Result<HttpResponse> {
        let outer = request.url.clone();
        request.url = ubaa_core::facade::testing::from_webvpn_url(&outer).unwrap();
        if request.url.contains("/pjxt/cas") {
            self.activated.store(true, Ordering::SeqCst);
        }
        if request.url.contains("getRequiredReviewsData") {
            if !self.vpn {
                return Err(UbaaError::new(
                    ErrorCode::NetworkError,
                    ErrorKind::Network,
                    true,
                    "合成断网",
                ));
            }
            assert!(
                self.activated.load(Ordering::SeqCst),
                "回退后须激活独立评教会话"
            );
        }
        let mut response = self.inner.execute(request).await?;
        response.final_url = outer;
        Ok(response)
    }
}
#[tokio::test]
async fn 分段课程网络失败回退后保留游标并激活新路线() {
    let root = test_root("evaluation-domain");
    let (client, cache, transport) = setup(&root);
    drop(client);
    let store = FileSessionStore::new(&root).unwrap();
    let slot = RouteSessionSnapshot {
        cookies: Vec::new(),
        authenticated_at: 1000,
        last_activity: 1001,
    };
    store
        .save_dual(&DualSessionSnapshot::new(Some(slot.clone()), Some(slot)))
        .unwrap();
    let route = |vpn| RouteTransport {
        inner: transport.clone(),
        vpn,
        activated: Arc::default(),
    };
    let mut client = UbaaClient::with_routing(
        route(false),
        route(true),
        store,
        RouteConfig::default(),
        CountingProbe(Arc::default()),
    )
    .unwrap();
    let mut plan = client
        .begin_evaluation_scan(Some(&cache), None)
        .await
        .unwrap();
    loop {
        let result = client.next_evaluation_scan(&mut plan).await.unwrap();
        if result.finished {
            assert!(result.complete);
            assert_eq!(result.resolution.mode, ConnectionMode::WebVpn);
            assert_eq!(result.data.courses.len(), 1);
            break;
        }
    }
    drop((client, cache));
    let _ = std::fs::remove_dir_all(root);
}
