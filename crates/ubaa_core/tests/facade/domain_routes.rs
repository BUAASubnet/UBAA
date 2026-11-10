use super::*;
use std::sync::Mutex;
use ubaa_core::facade::testing::from_webvpn_url;
use ubaa_core::facade::{ErrorKind, UbaaError};

#[derive(Clone)]
struct DomainTransport {
    route: ConnectionMode,
    visits: Arc<Mutex<Vec<ConnectionMode>>>,
    direct_error: ErrorCode,
    vpn_error: Option<ErrorCode>,
}
#[async_trait]
impl HttpTransport for DomainTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let direct = from_webvpn_url(&request.url).unwrap();
        let url = url::Url::parse(&direct).unwrap();
        let mut response = HttpResponse::new(200, request.url, Vec::new());
        if url.path() == "/login" {
            response.status = 302;
            response.headers.insert("Location".into(),vec!["https://byxt.buaa.edu.cn/jwapp/sys/homeapp/index.do?contextPath=/jwapp&ticket=ST-domain-test".into()]);
        } else if url.path() == "/serviceValidate" {
            response.body =
                br#"{"user":"fixture-user","attributes":{"employeeNumber":["TEST-0001"]}}"#
                    .to_vec();
        } else {
            self.visits.lock().unwrap().push(self.route);
            if let Some(error) = if self.route == ConnectionMode::Direct {
                Some(self.direct_error)
            } else {
                self.vpn_error
            } {
                return Err(UbaaError::new(
                    error,
                    if matches!(error, ErrorCode::NetworkError | ErrorCode::Timeout) {
                        ErrorKind::Network
                    } else {
                        ErrorKind::Upstream
                    },
                    true,
                    "合成失败",
                ));
            }
            response.body =
                include_bytes!("../../../../fixtures/auth/userinfo-success.json").to_vec();
        }
        Ok(response)
    }
}

#[tokio::test]
async fn 校外先直连且只在网络错误后回退并复用同域名记录() {
    for error in [
        ErrorCode::NetworkError,
        ErrorCode::Timeout,
        ErrorCode::UpstreamChanged,
        ErrorCode::ParseError,
        ErrorCode::PermissionDenied,
    ] {
        let root = test_root("domain-fallback");
        let store = FileSessionStore::new(&root).unwrap();
        let slot = RouteSessionSnapshot {
            cookies: Vec::new(),
            authenticated_at: 1000,
            last_activity: 1000,
        };
        store
            .save_dual(&DualSessionSnapshot::new(Some(slot.clone()), Some(slot)))
            .unwrap();
        let visits = Arc::new(Mutex::new(Vec::new()));
        let transport = |route| DomainTransport {
            route,
            visits: visits.clone(),
            direct_error: error,
            vpn_error: None,
        };
        let mut client = UbaaClient::with_routing(
            transport(ConnectionMode::Direct),
            transport(ConnectionMode::WebVpn),
            store,
            RouteConfig::default(),
            CountingProbe(Arc::default()),
        )
        .unwrap();
        let first = client.get_user_info().await;
        if matches!(error, ErrorCode::NetworkError | ErrorCode::Timeout) {
            let read = first.unwrap();
            assert_eq!(
                read.resolution.diagnostic.initial_route,
                ConnectionMode::Direct
            );
            assert!(read.resolution.diagnostic.used_fallback);
            assert_eq!(
                *visits.lock().unwrap(),
                [ConnectionMode::Direct, ConnectionMode::WebVpn]
            );
            client.get_user_info().await.unwrap();
            assert_eq!(
                *visits.lock().unwrap(),
                [
                    ConnectionMode::Direct,
                    ConnectionMode::WebVpn,
                    ConnectionMode::WebVpn
                ]
            );
        } else {
            assert_eq!(first.unwrap_err().error.code, error);
            assert_eq!(*visits.lock().unwrap(), [ConnectionMode::Direct]);
        }
        let _ = std::fs::remove_dir_all(root);
    }
}

#[tokio::test]
async fn 域名记录重启后复用且到期重新直连_两路失败不记录() {
    for vpn_error in [None, Some(ErrorCode::NetworkError)] {
        let root = test_root("domain-persistence");
        let slot = RouteSessionSnapshot {
            cookies: Vec::new(),
            authenticated_at: 1000,
            last_activity: 1000,
        };
        FileSessionStore::new(&root)
            .unwrap()
            .save_dual(&DualSessionSnapshot::new(Some(slot.clone()), Some(slot)))
            .unwrap();
        let visits = Arc::new(Mutex::new(Vec::new()));
        let transport = |route| DomainTransport {
            route,
            visits: visits.clone(),
            direct_error: ErrorCode::NetworkError,
            vpn_error,
        };
        let open = || {
            ubaa_core::facade::testing::with_routing_in_config_directory(
                transport(ConnectionMode::Direct),
                transport(ConnectionMode::WebVpn),
                &root,
                CountingProbe(Arc::default()),
            )
            .unwrap()
        };
        let mut client = open();
        assert_eq!(client.get_user_info().await.is_ok(), vpn_error.is_none());
        drop(client);
        visits.lock().unwrap().clear();
        let mut client = open();
        assert_eq!(client.get_user_info().await.is_ok(), vpn_error.is_none());
        assert_eq!(
            *visits.lock().unwrap(),
            if vpn_error.is_none() {
                vec![ConnectionMode::WebVpn]
            } else {
                vec![ConnectionMode::Direct, ConnectionMode::WebVpn]
            }
        );
        drop(client);
        if vpn_error.is_none() {
            std::fs::write(root.join("domain_routes.json"), br#"{"uc.buaa.edu.cn":0}"#).unwrap();
            visits.lock().unwrap().clear();
            open().get_user_info().await.unwrap();
            assert_eq!(
                *visits.lock().unwrap(),
                [ConnectionMode::Direct, ConnectionMode::WebVpn]
            );
        } else {
            assert!(!root.join("domain_routes.json").exists());
        }
        let _ = std::fs::remove_dir_all(root);
    }
}

#[tokio::test]
async fn 校内单路线会话移到校外后恢复实际缺失的_webvpn() {
    let root = test_root("campus-transition");
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save_dual(&DualSessionSnapshot::new(
            Some(RouteSessionSnapshot {
                cookies: Vec::new(),
                authenticated_at: 1000,
                last_activity: 1000,
            }),
            None,
        ))
        .unwrap();
    let visits = Arc::new(Mutex::new(Vec::new()));
    let transport = |route| DomainTransport {
        route,
        visits: visits.clone(),
        direct_error: ErrorCode::NetworkError,
        vpn_error: None,
    };
    let mut client = UbaaClient::with_routing(
        transport(ConnectionMode::Direct),
        transport(ConnectionMode::WebVpn),
        store,
        RouteConfig::default(),
        CountingProbe(Arc::default()),
    )
    .unwrap();
    // 会话仍有效，但业务直连已不可达，第一次回退缺少 WebVPN 会话。
    let failed = client
        .fork_parallel_readonly()
        .unwrap()
        .signin_today()
        .await
        .unwrap_err();
    assert_eq!(failed.error.code, ErrorCode::AuthenticationRequired);
    assert_eq!(failed.resolution.unwrap().mode, ConnectionMode::WebVpn);
    let recovery = client
        .recover_required_session(ReadonlyFeature::Signin)
        .await;
    assert!(
        recovery.is_err(),
        "不能把 Direct 验票成功当作 WebVPN 恢复成功"
    );
    let error = recovery.unwrap_err();
    assert_eq!(error.error.code, ErrorCode::AuthenticationRequired);
    assert_eq!(error.resolution.unwrap().mode, ConnectionMode::WebVpn);
    assert_eq!(*visits.lock().unwrap(), [ConnectionMode::Direct]);
    assert!(!root.join("domain_routes.json").exists());
    let _ = std::fs::remove_dir_all(root);
}

#[derive(Clone)]
struct MovingNetwork(Arc<AtomicUsize>);
impl GatewayProbe for MovingNetwork {
    fn probe(&self, _: Duration) -> NetworkState {
        if self.0.load(Ordering::SeqCst) == 0 {
            NetworkState::Campus
        } else {
            NetworkState::OffCampus
        }
    }
}

#[tokio::test]
async fn 网络恢复撤销校内探测缓存并保留显式路线() {
    for policy in [RoutePolicy::Auto, RoutePolicy::Direct, RoutePolicy::WebVpn] {
        let root = test_root("network-session");
        let store = FileSessionStore::new(&root).unwrap();
        store
            .save_dual(&DualSessionSnapshot::new(
                Some(RouteSessionSnapshot {
                    cookies: vec![],
                    authenticated_at: 1000,
                    last_activity: 1000,
                }),
                None,
            ))
            .unwrap();
        let network = Arc::new(AtomicUsize::new(0));
        let visits = Arc::new(Mutex::new(vec![]));
        let transport = |route| DomainTransport {
            route,
            visits: visits.clone(),
            direct_error: ErrorCode::NetworkError,
            vpn_error: None,
        };
        let mut config = RouteConfig::default();
        config.default = policy;
        let mut client = UbaaClient::with_routing(
            transport(ConnectionMode::Direct),
            transport(ConnectionMode::WebVpn),
            store,
            config,
            MovingNetwork(network.clone()),
        )
        .unwrap();
        if policy != RoutePolicy::WebVpn {
            assert_eq!(
                client
                    .recover_connection_session()
                    .await
                    .unwrap()
                    .resolution
                    .mode,
                ConnectionMode::Direct
            );
        }
        network.store(1, Ordering::SeqCst);
        let recovered = client.recover_connection_session().await;
        if policy == RoutePolicy::Direct {
            assert_eq!(recovered.unwrap().resolution.mode, ConnectionMode::Direct);
        } else {
            let error = recovered.unwrap_err();
            assert_eq!(error.error.code, ErrorCode::AuthenticationRequired);
            assert_eq!(error.resolution.unwrap().mode, ConnectionMode::WebVpn);
        }
        assert!(visits.lock().unwrap().is_empty(), "准备会话不读取业务网站");
        let _ = std::fs::remove_dir_all(root);
    }
}
