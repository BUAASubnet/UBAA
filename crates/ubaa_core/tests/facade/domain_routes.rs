use super::*;
use std::sync::Mutex;
use ubaa_core::facade::testing::from_webvpn_url;
use ubaa_core::facade::{ErrorKind, UbaaError};

#[test]
fn 校外名单直接选择网关且校园网和显式策略保持原选择() {
    for (policy, network, expected) in [
        (
            RoutePolicy::Auto,
            NetworkState::OffCampus,
            ConnectionMode::WebVpn,
        ),
        (
            RoutePolicy::Auto,
            NetworkState::Campus,
            ConnectionMode::Direct,
        ),
        (
            RoutePolicy::Auto,
            NetworkState::Unknown,
            ConnectionMode::Direct,
        ),
        (
            RoutePolicy::Direct,
            NetworkState::OffCampus,
            ConnectionMode::Direct,
        ),
        (
            RoutePolicy::WebVpn,
            NetworkState::Campus,
            ConnectionMode::WebVpn,
        ),
    ] {
        struct Probe(NetworkState);
        impl GatewayProbe for Probe {
            fn probe(&self, _: Duration) -> NetworkState {
                self.0
            }
        }
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../.ubaa_local/off_campus_domains/tests")
            .join(format!("{}-{policy:?}-{network:?}", std::process::id()));
        let store = FileSessionStore::new(&root).unwrap();
        let slot = RouteSessionSnapshot {
            cookies: vec![],
            authenticated_at: 1000,
            last_activity: 1000,
        };
        store
            .save_dual(&DualSessionSnapshot::new(Some(slot.clone()), Some(slot)))
            .unwrap();
        let calls = Arc::new(AtomicUsize::new(0));
        let mut config = RouteConfig::default();
        config.default = policy;
        let mut client = UbaaClient::with_routing(
            CountingTransport(calls.clone()),
            CountingTransport(calls.clone()),
            store,
            config,
            Probe(network),
        )
        .unwrap();
        for feature in [
            ReadonlyFeature::Judge,
            ReadonlyFeature::Signin,
            ReadonlyFeature::Ihome,
            ReadonlyFeature::Finance,
        ] {
            let resolved = client.resolve_route_for_feature(feature).unwrap();
            assert_eq!(
                resolved.mode, expected,
                "{policy:?}/{network:?}/{feature:?}"
            );
        }
        if policy == RoutePolicy::Auto {
            for feature in [
                ReadonlyFeature::Schedule,
                ReadonlyFeature::Spoc,
                ReadonlyFeature::Bykc,
                ReadonlyFeature::Portal,
            ] {
                assert_eq!(
                    client.resolve_route_for_feature(feature).unwrap().mode,
                    ConnectionMode::Direct
                );
            }
        }
        assert_eq!(calls.load(Ordering::SeqCst), 0);
        drop(client);
        std::fs::remove_dir_all(root).unwrap();
    }
}

#[tokio::test]
async fn 名单域名缺少网关会话时直接请求恢复且不发送直连() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/off_campus_domains/tests")
        .join(format!("missing-{}", std::process::id()));
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: vec![],
            authenticated_at: 1000,
            last_activity: 1000,
        })
        .unwrap();
    let calls = Arc::new(AtomicUsize::new(0));
    let mut client = UbaaClient::with_routing(
        CountingTransport(calls.clone()),
        CountingTransport(calls.clone()),
        store,
        RouteConfig::default(),
        CountingProbe(Arc::default()),
    )
    .unwrap();
    for error in [
        client.get_user_info().await.unwrap_err(),
        client.signin_today().await.unwrap_err(),
        client
            .recover_required_session(ReadonlyFeature::Finance)
            .await
            .unwrap_err(),
    ] {
        assert_eq!(error.error.code, ErrorCode::AuthenticationRequired);
        assert_eq!(error.resolution.unwrap().mode, ConnectionMode::WebVpn);
    }
    assert_eq!(calls.load(Ordering::SeqCst), 0);
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}

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
                include_bytes!("../../../../fixtures/readonly/campus/profile.json").to_vec();
        }
        Ok(response)
    }
}

#[tokio::test]
async fn 换网也取消回退前的网关会话核验() {
    struct WaitingVpn {
        started: Arc<tokio::sync::Notify>,
    }
    #[async_trait]
    impl HttpTransport for WaitingVpn {
        async fn execute(&self, _: HttpRequest) -> Result<HttpResponse> {
            self.started.notify_one();
            std::future::pending().await
        }
    }
    let root = test_root("fallback-auth-cancel");
    let store = FileSessionStore::new(&root).unwrap();
    let slot = RouteSessionSnapshot {
        cookies: vec![],
        authenticated_at: 1000,
        last_activity: 1000,
    };
    store
        .save_dual(&DualSessionSnapshot::new(Some(slot.clone()), Some(slot)))
        .unwrap();
    let started = Arc::new(tokio::sync::Notify::new());
    let mut client = UbaaClient::with_routing(
        DomainTransport {
            route: ConnectionMode::Direct,
            visits: Arc::default(),
            direct_error: ErrorCode::NetworkError,
            vpn_error: None,
        },
        WaitingVpn {
            started: started.clone(),
        },
        store,
        RouteConfig::default(),
        CountingProbe(Arc::default()),
    )
    .unwrap();
    let control = client.network_control();
    let read = client.portal_profile();
    tokio::pin!(read);
    tokio::select! {
        () = started.notified() => {},
        result = &mut read => panic!("必须等待网关核验：{:?}", result.err()),
    }
    let change = control.begin_change(true, Duration::from_secs(30)).unwrap();
    let result = tokio::time::timeout(Duration::from_secs(1), read)
        .await
        .expect("核验属于只读回退，不应阻塞换网");
    assert!(result.unwrap_err().error.is_network_changed());
    change.finish();
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
        let first = client.portal_profile().await;
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
            client.portal_profile().await.unwrap();
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
async fn 已记录的网关路线网络失败后下次重新判断域名() {
    let root = test_root("domain-vpn-failure");
    let store = FileSessionStore::new(&root).unwrap();
    let slot = RouteSessionSnapshot {
        cookies: vec![],
        authenticated_at: 1000,
        last_activity: 1000,
    };
    store
        .save_dual(&DualSessionSnapshot::new(Some(slot.clone()), Some(slot)))
        .unwrap();
    let expires = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 86400;
    std::fs::write(
        root.join("domain_routes.json"),
        format!("{{\"it.buaa.edu.cn\":{expires}}}"),
    )
    .unwrap();
    let visits = Arc::new(Mutex::new(Vec::new()));
    let transport = |route| DomainTransport {
        route,
        visits: visits.clone(),
        direct_error: ErrorCode::NetworkError,
        vpn_error: Some(ErrorCode::NetworkError),
    };
    let mut client = ubaa_core::facade::testing::with_routing_in_config_directory(
        transport(ConnectionMode::Direct),
        transport(ConnectionMode::WebVpn),
        &root,
        CountingProbe(Arc::default()),
    )
    .unwrap();
    client.portal_profile().await.unwrap_err();
    assert_eq!(*visits.lock().unwrap(), [ConnectionMode::WebVpn]);
    client.portal_profile().await.unwrap_err();
    assert_eq!(
        *visits.lock().unwrap(),
        [
            ConnectionMode::WebVpn,
            ConnectionMode::Direct,
            ConnectionMode::WebVpn
        ]
    );
    let saved: serde_json::Value =
        serde_json::from_slice(&std::fs::read(root.join("domain_routes.json")).unwrap()).unwrap();
    assert!(saved.get("it.buaa.edu.cn").is_none());
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
        assert_eq!(client.portal_profile().await.is_ok(), vpn_error.is_none());
        drop(client);
        visits.lock().unwrap().clear();
        let mut client = open();
        assert_eq!(client.portal_profile().await.is_ok(), vpn_error.is_none());
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
            std::fs::write(root.join("domain_routes.json"), br#"{"it.buaa.edu.cn":0}"#).unwrap();
            visits.lock().unwrap().clear();
            open().portal_profile().await.unwrap();
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
        .portal_profile()
        .await
        .unwrap_err();
    assert_eq!(failed.error.code, ErrorCode::AuthenticationRequired);
    assert_eq!(failed.resolution.unwrap().mode, ConnectionMode::WebVpn);
    let recovery = client
        .recover_required_session(ReadonlyFeature::Portal)
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
async fn 直连失败后重新检测并推翻尚未过期的校内判断() {
    let root = test_root("stale-campus-fallback");
    let store = FileSessionStore::new(&root).unwrap();
    let slot = RouteSessionSnapshot {
        cookies: vec![],
        authenticated_at: 1000,
        last_activity: 1000,
    };
    store
        .save_dual(&DualSessionSnapshot::new(Some(slot.clone()), Some(slot)))
        .unwrap();
    let network = Arc::new(AtomicUsize::new(0));
    let visits = Arc::new(Mutex::new(vec![]));
    let transport = |route| DomainTransport {
        route,
        visits: visits.clone(),
        direct_error: ErrorCode::Timeout,
        vpn_error: None,
    };
    let mut client = UbaaClient::with_routing(
        transport(ConnectionMode::Direct),
        transport(ConnectionMode::WebVpn),
        store,
        RouteConfig::default(),
        MovingNetwork(network.clone()),
    )
    .unwrap();
    client.recover_connection_session().await.unwrap();
    network.store(1, Ordering::SeqCst);
    let read = client.portal_profile().await.unwrap();
    assert_eq!(read.resolution.mode, ConnectionMode::WebVpn);
    assert_eq!(
        *visits.lock().unwrap(),
        [ConnectionMode::Direct, ConnectionMode::WebVpn]
    );
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
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
