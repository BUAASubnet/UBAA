use super::*;

#[test]
fn cgyy_webvpn_only_session_does_not_require_direct_session() {
    let root = test_root("cgyy-webvpn-only");
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save_dual(&DualSessionSnapshot::new(
            None,
            Some(RouteSessionSnapshot {
                cookies: Vec::new(),
                authenticated_at: 1_000,
                last_activity: 1_001,
            }),
        ))
        .unwrap();
    let direct_calls = Arc::new(AtomicUsize::new(0));
    let webvpn_requests = Arc::new(std::sync::Mutex::new(Vec::new()));
    let config = RouteConfig::parse("[route]\ndefault = \"webvpn\"\n").unwrap();
    let mut client = UbaaClient::with_routing(
        TaggedTransport {
            calls: direct_calls.clone(),
            status: 500,
        },
        CgyyWebVpnTransport {
            requests: webvpn_requests.clone(),
        },
        store,
        config,
        NeverProbe,
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();

    let routed = runtime.block_on(client.cgyy_sites()).unwrap();

    assert_eq!(routed.data.len(), 1);
    assert_eq!(direct_calls.load(Ordering::SeqCst), 0);
    let requests = webvpn_requests.lock().unwrap();
    assert!(!requests.is_empty());
    assert!(requests.iter().all(|request| {
        url::Url::parse(&request.url)
            .ok()
            .and_then(|url| url.host_str().map(str::to_owned))
            .as_deref()
            == Some("d.buaa.edu.cn")
    }));
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn cgyy_auto_uses_the_resolved_webvpn_runtime() {
    let root = test_root("cgyy-auto-webvpn");
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save_dual(&DualSessionSnapshot::new(
            None,
            Some(RouteSessionSnapshot {
                cookies: Vec::new(),
                authenticated_at: 1_000,
                last_activity: 1_001,
            }),
        ))
        .unwrap();
    let direct_calls = Arc::new(AtomicUsize::new(0));
    let webvpn_calls = Arc::new(AtomicUsize::new(0));
    let config = RouteConfig::parse("[route]\ndefault = \"auto\"\n").unwrap();
    let mut client = UbaaClient::with_routing(
        TaggedTransport {
            calls: direct_calls.clone(),
            status: 500,
        },
        TaggedTransport {
            calls: webvpn_calls.clone(),
            status: 401,
        },
        store,
        config,
        CountingProbe(Arc::new(AtomicUsize::new(0))),
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();

    let error = runtime.block_on(client.cgyy_sites()).unwrap_err();

    assert_eq!(error.resolution.unwrap().mode, ConnectionMode::WebVpn);
    assert_eq!(direct_calls.load(Ordering::SeqCst), 0);
    assert_eq!(webvpn_calls.load(Ordering::SeqCst), 1);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn cgyy_auto_uses_resolved_direct_runtime_when_on_campus() {
    let root = test_root("cgyy-auto-direct");
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save_dual(&DualSessionSnapshot::new(
            Some(RouteSessionSnapshot {
                cookies: Vec::new(),
                authenticated_at: 1_000,
                last_activity: 1_001,
            }),
            None,
        ))
        .unwrap();
    let direct_requests = Arc::new(std::sync::Mutex::new(Vec::new()));
    let webvpn_calls = Arc::new(AtomicUsize::new(0));
    let mut client = UbaaClient::with_routing(
        CgyyWebVpnTransport {
            requests: direct_requests.clone(),
        },
        TaggedTransport {
            calls: webvpn_calls.clone(),
            status: 500,
        },
        store,
        RouteConfig::parse("[route]\ndefault = \"auto\"\n").unwrap(),
        CampusProbe,
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();

    let routed = runtime.block_on(client.cgyy_sites()).unwrap();

    assert_eq!(routed.resolution.mode, ConnectionMode::Direct);
    assert_eq!(webvpn_calls.load(Ordering::SeqCst), 0);
    assert!(direct_requests.lock().unwrap().iter().all(|request| {
        url::Url::parse(&request.url)
            .ok()
            .and_then(|url| url.host_str().map(str::to_owned))
            == Some("cgyy.buaa.edu.cn".into())
    }));
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn stale_writer_is_rejected_before_any_write_request() {
    let root = test_root("stale-writer-before-request");
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    let initial = SessionSnapshot {
        mode: ConnectionMode::Direct,
        cookies: Vec::new(),
        authenticated_at: 1_000,
        last_activity: 1_001,
    };
    store
        .save_dual(&DualSessionSnapshot::new(
            Some(RouteSessionSnapshot {
                cookies: initial.cookies.clone(),
                authenticated_at: initial.authenticated_at,
                last_activity: initial.last_activity,
            }),
            None,
        ))
        .unwrap();
    let writes = Arc::new(AtomicUsize::new(0));
    let probes = Arc::new(AtomicUsize::new(0));
    let config = RouteConfig::parse("[route]\ndefault = \"auto\"\n").unwrap();
    let mut client = UbaaClient::with_routing(
        CountingTransport(writes.clone()),
        CountingTransport(writes.clone()),
        FileSessionStore::new(&root).unwrap(),
        config,
        CountingProbe(probes.clone()),
    )
    .unwrap();

    // 另一个进程已经写入同一路线，推进共享 CAS 修订。
    store
        .save_dual(&DualSessionSnapshot::new(
            Some(RouteSessionSnapshot {
                cookies: Vec::new(),
                authenticated_at: 1_000,
                last_activity: 2_002,
            }),
            None,
        ))
        .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let error = runtime.block_on(client.bykc_select_course(42)).unwrap_err();

    assert_eq!(error.error.code, ErrorCode::InternalError);
    assert!(error.resolution.is_none());
    assert_eq!(probes.load(Ordering::SeqCst), 0);
    assert_eq!(writes.load(Ordering::SeqCst), 0);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn stale_reader_is_rejected_before_any_read_request() {
    let root = test_root("stale-reader-before-request");
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save_dual(&DualSessionSnapshot::new(
            Some(RouteSessionSnapshot {
                cookies: Vec::new(),
                authenticated_at: 1_000,
                last_activity: 1_001,
            }),
            None,
        ))
        .unwrap();
    let reads = Arc::new(AtomicUsize::new(0));
    let probes = Arc::new(AtomicUsize::new(0));
    let mut client = UbaaClient::with_routing(
        CountingTransport(reads.clone()),
        CountingTransport(reads.clone()),
        FileSessionStore::new(&root).unwrap(),
        RouteConfig::parse("[route]\ndefault = \"auto\"\n").unwrap(),
        CountingProbe(probes.clone()),
    )
    .unwrap();
    store
        .save_dual(&DualSessionSnapshot::new(
            Some(RouteSessionSnapshot {
                cookies: Vec::new(),
                authenticated_at: 1_000,
                last_activity: 2_002,
            }),
            None,
        ))
        .unwrap();

    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let error = runtime.block_on(client.get_user_info()).unwrap_err();

    assert_eq!(error.error.code, ErrorCode::InternalError);
    assert!(error.resolution.is_none());
    assert_eq!(probes.load(Ordering::SeqCst), 0);
    assert_eq!(reads.load(Ordering::SeqCst), 0);
    let _ = std::fs::remove_dir_all(root);
}
