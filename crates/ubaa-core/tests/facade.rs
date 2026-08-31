use std::sync::Arc;
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::time::Duration;

use async_trait::async_trait;
use ubaa_core::config::RouteConfig;
use ubaa_core::connection::{GatewayProbe, NetworkState};
use ubaa_core::domain::{ConnectionMode, RoutePolicy};
use ubaa_core::error::ErrorCode;
use ubaa_core::facade::UbaaClient;
use ubaa_core::ports::{HttpRequest, HttpResponse, HttpTransport};
use ubaa_core::session::{
    DualSessionSnapshot, FileSessionStore, RouteSessionSnapshot, SessionSnapshot, SessionStore,
};

#[test]
fn aggregate_facade_opens_saved_routes_without_host_session_inspection() {
    let root = test_root("saved-routes");
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::WebVpn,
            cookies: Vec::new(),
            authenticated_at: 1_000,
            last_activity: 1_001,
        })
        .unwrap();

    let client = UbaaClient::open(&root).unwrap();

    assert_eq!(client.active_routes(), vec![ConnectionMode::WebVpn]);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn aggregate_facade_opens_without_config_or_session() {
    let root = test_root("fresh");
    let _ = std::fs::remove_dir_all(&root);

    let client = UbaaClient::open(&root).unwrap();

    assert!(client.active_routes().is_empty());
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn post_resolution_errors_keep_default_and_feature_diagnostics() {
    let root = test_root("routed-errors");
    let _ = std::fs::remove_dir_all(&root);
    std::fs::create_dir_all(&root).unwrap();
    std::fs::write(
        root.join("config.toml"),
        r#"
schema_version = 1
[route]
default = "webvpn"
[route.features]
schedule = "direct"
"#,
    )
    .unwrap();
    let mut client = UbaaClient::open(&root).unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();

    let user = runtime.block_on(client.get_user_info()).unwrap_err();
    assert_eq!(user.error.code, ErrorCode::AuthenticationRequired);
    let user_resolution = user.resolution.expect("user route was resolved");
    assert_eq!(user_resolution.policy, RoutePolicy::WebVpn);
    assert_eq!(user_resolution.mode, ConnectionMode::WebVpn);

    let schedule = runtime.block_on(client.schedule_terms()).unwrap_err();
    assert_eq!(schedule.error.code, ErrorCode::AuthenticationRequired);
    let schedule_resolution = schedule.resolution.expect("schedule route was resolved");
    assert_eq!(schedule_resolution.policy, RoutePolicy::Direct);
    assert_eq!(schedule_resolution.mode, ConnectionMode::Direct);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn aggregate_facade_owns_one_cached_auto_probe() {
    let root = test_root("cached-probe");
    let _ = std::fs::remove_dir_all(&root);
    let calls = Arc::new(AtomicUsize::new(0));
    let requests = Arc::new(AtomicUsize::new(0));
    let mut client = UbaaClient::with_routing(
        CountingTransport(requests.clone()),
        CountingTransport(requests.clone()),
        FileSessionStore::new(&root).unwrap(),
        RouteConfig::default(),
        CountingProbe(calls.clone()),
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();

    for _ in 0..2 {
        let error = runtime.block_on(client.get_user_info()).unwrap_err();
        assert_eq!(error.error.code, ErrorCode::AuthenticationRequired);
        let resolution = error.resolution.expect("auto route was resolved");
        assert_eq!(resolution.policy, RoutePolicy::Auto);
        assert_eq!(resolution.mode, ConnectionMode::WebVpn);
        assert_eq!(resolution.diagnostic.network, NetworkState::OffCampus);
    }
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    assert_eq!(requests.load(Ordering::SeqCst), 0);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn routed_success_contains_the_core_default_resolution() {
    let root = test_root("routed-success");
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: Vec::new(),
            authenticated_at: 1_000,
            last_activity: 1_001,
        })
        .unwrap();
    let config = RouteConfig::parse("[route]\ndefault = \"direct\"\n").unwrap();
    let mut client = UbaaClient::with_routing(
        StaticTransport(HttpResponse::new(
            200,
            "https://uc.buaa.edu.cn/api/uc/userinfo",
            include_str!("../../../fixtures/auth/userinfo-success.json")
                .as_bytes()
                .to_vec(),
        )),
        CountingTransport(Arc::new(AtomicUsize::new(0))),
        FileSessionStore::new(&root).unwrap(),
        config,
        NeverProbe,
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();

    let routed = runtime.block_on(client.get_user_info()).unwrap();

    assert_eq!(routed.data.username.as_deref(), Some("fixture-user"));
    assert_eq!(routed.resolution.policy, RoutePolicy::Direct);
    assert_eq!(routed.resolution.mode, ConnectionMode::Direct);
    assert_eq!(routed.resolution.diagnostic.network, NetworkState::Unknown);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn aggregate_facade_exposes_safe_judge_diagnostics_with_route_resolution() {
    let root = test_root("judge-diagnostics");
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: Vec::new(),
            authenticated_at: 1_000,
            last_activity: 1_001,
        })
        .unwrap();
    let config = RouteConfig::parse("[route]\ndefault = \"direct\"\n").unwrap();
    let requests = Arc::new(AtomicUsize::new(0));
    let mut client = UbaaClient::with_routing(
        EmptyJudgeTransport(requests.clone()),
        CountingTransport(Arc::new(AtomicUsize::new(0))),
        FileSessionStore::new(&root).unwrap(),
        config,
        NeverProbe,
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();

    let routed = runtime
        .block_on(client.judge_assignments_diagnostics(false))
        .unwrap();

    assert_eq!(routed.data.course_count, 0);
    assert_eq!(routed.data.raw_anchor_count, 0);
    assert_eq!(routed.data.filtered_unique_count, 0);
    assert!(routed.data.summaries.is_empty());
    assert_eq!(routed.resolution.policy, RoutePolicy::Direct);
    assert_eq!(routed.resolution.mode, ConnectionMode::Direct);
    assert_eq!(requests.load(Ordering::SeqCst), 3);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn aggregate_facade_resolves_spoc_diagnostics_before_session_preflight() {
    let root = test_root("spoc-diagnostics-route");
    let _ = std::fs::remove_dir_all(&root);
    let requests = Arc::new(AtomicUsize::new(0));
    let config =
        RouteConfig::parse("[route]\ndefault = \"webvpn\"\n[route.features]\nspoc = \"direct\"\n")
            .unwrap();
    let mut client = UbaaClient::with_routing(
        CountingTransport(requests.clone()),
        CountingTransport(requests.clone()),
        FileSessionStore::new(&root).unwrap(),
        config,
        NeverProbe,
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();

    let error = runtime
        .block_on(client.spoc_assignments_diagnostics())
        .unwrap_err();

    assert_eq!(error.error.code, ErrorCode::AuthenticationRequired);
    let resolution = error.resolution.expect("SPOC route was resolved");
    assert_eq!(resolution.policy, RoutePolicy::Direct);
    assert_eq!(resolution.mode, ConnectionMode::Direct);
    assert_eq!(requests.load(Ordering::SeqCst), 0);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn cgyy_webvpn_uses_webvpn_business_transport_after_route_resolution() {
    let root = test_root("cgyy-direct-business");
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save_dual(&DualSessionSnapshot::new(
            Some(RouteSessionSnapshot {
                cookies: Vec::new(),
                authenticated_at: 1_000,
                last_activity: 1_001,
            }),
            Some(RouteSessionSnapshot {
                cookies: Vec::new(),
                authenticated_at: 1_000,
                last_activity: 1_001,
            }),
        ))
        .unwrap();
    let direct_calls = Arc::new(AtomicUsize::new(0));
    let webvpn_calls = Arc::new(AtomicUsize::new(0));
    let config = RouteConfig::parse("[route]\ndefault = \"webvpn\"\n").unwrap();
    let mut client = UbaaClient::with_routing(
        TaggedTransport {
            calls: direct_calls.clone(),
            status: 401,
        },
        TaggedTransport {
            calls: webvpn_calls.clone(),
            status: 401,
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

    let error = runtime.block_on(client.cgyy_sites()).unwrap_err();

    assert_eq!(error.error.code, ErrorCode::AuthenticationRequired);
    assert_eq!(direct_calls.load(Ordering::SeqCst), 0);
    assert_eq!(webvpn_calls.load(Ordering::SeqCst), 1);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn cgyy_webvpn_writes_use_webvpn_business_transport() {
    let root = test_root("cgyy-direct-write-business");
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save_dual(&DualSessionSnapshot::new(
            Some(RouteSessionSnapshot {
                cookies: Vec::new(),
                authenticated_at: 1_000,
                last_activity: 1_001,
            }),
            Some(RouteSessionSnapshot {
                cookies: Vec::new(),
                authenticated_at: 1_000,
                last_activity: 1_001,
            }),
        ))
        .unwrap();
    let direct_calls = Arc::new(AtomicUsize::new(0));
    let webvpn_calls = Arc::new(AtomicUsize::new(0));
    let config = RouteConfig::parse("[route]\ndefault = \"webvpn\"\n").unwrap();
    let mut client = UbaaClient::with_routing(
        TaggedTransport {
            calls: direct_calls.clone(),
            status: 401,
        },
        TaggedTransport {
            calls: webvpn_calls.clone(),
            status: 401,
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

    let error = runtime.block_on(client.cgyy_cancel_order(77)).unwrap_err();

    assert_eq!(error.error.code, ErrorCode::AuthenticationRequired);
    assert_eq!(direct_calls.load(Ordering::SeqCst), 0);
    assert_eq!(webvpn_calls.load(Ordering::SeqCst), 1);
    let _ = std::fs::remove_dir_all(root);
}

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

#[derive(Clone)]
struct CountingTransport(Arc<AtomicUsize>);

#[derive(Clone)]
struct TaggedTransport {
    calls: Arc<AtomicUsize>,
    status: u16,
}

#[derive(Clone)]
struct CgyyWebVpnTransport {
    requests: Arc<std::sync::Mutex<Vec<HttpRequest>>>,
}

#[async_trait]
impl HttpTransport for CgyyWebVpnTransport {
    async fn execute(&self, request: HttpRequest) -> ubaa_core::error::Result<HttpResponse> {
        self.requests.lock().unwrap().push(request.clone());
        let path = url::Url::parse(&request.url).unwrap().path().to_owned();
        let mut response = match path.as_str() {
            path if path.ends_with("/venue-zhjs-server/sso/manageLogin") => {
                HttpResponse::new(200, request.url.clone(), Vec::new())
            }
            path if path.ends_with("/venue-zhjs-server/api/login") => HttpResponse::new(
                200,
                request.url.clone(),
                br#"{"code":200,"data":{"token":{"access_token":"webvpn-access"}}}"#
                    .to_vec(),
            ),
            path if path.ends_with("/venue-zhjs-server/api/front/website/venues") => {
                HttpResponse::new(
                    200,
                    request.url,
                    r#"{"code":200,"data":[{"id":101,"siteName":"WebVPN 场馆","venueName":"场馆","campusName":"校区"}]}"#
                        .as_bytes()
                        .to_vec(),
                )
            }
            _ => panic!("未预期的 WebVPN Cgyy 请求: {path}"),
        };
        if path.ends_with("/sso/manageLogin") {
            response.headers.insert(
                "Set-Cookie".into(),
                vec!["sso_buaa_zhjs_token=sso-webvpn; Path=/".into()],
            );
        }
        Ok(response)
    }
}

#[async_trait]
impl HttpTransport for TaggedTransport {
    async fn execute(&self, request: HttpRequest) -> ubaa_core::error::Result<HttpResponse> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        Ok(HttpResponse::new(self.status, request.url, Vec::new()))
    }
}

#[async_trait]
impl HttpTransport for CountingTransport {
    async fn execute(&self, _request: HttpRequest) -> ubaa_core::error::Result<HttpResponse> {
        self.0.fetch_add(1, Ordering::SeqCst);
        panic!("route readiness preflight must run before HTTP")
    }
}

#[derive(Clone)]
struct StaticTransport(HttpResponse);

#[async_trait]
impl HttpTransport for StaticTransport {
    async fn execute(&self, _request: HttpRequest) -> ubaa_core::error::Result<HttpResponse> {
        Ok(self.0.clone())
    }
}

#[derive(Clone)]
struct EmptyJudgeTransport(Arc<AtomicUsize>);

#[async_trait]
impl HttpTransport for EmptyJudgeTransport {
    async fn execute(&self, request: HttpRequest) -> ubaa_core::error::Result<HttpResponse> {
        self.0.fetch_add(1, Ordering::SeqCst);
        if request.url == ubaa_core::features::judge::LOGIN_URL {
            let mut response = HttpResponse::new(302, request.url, Vec::new());
            response
                .headers
                .insert("Location".into(), vec!["https://judge.buaa.edu.cn/".into()]);
            return Ok(response);
        }
        if request.url == "https://judge.buaa.edu.cn/" {
            return Ok(HttpResponse::new(200, request.url, b"judge ready".to_vec()));
        }
        if request.url == "https://judge.buaa.edu.cn/courselist.jsp?courseID=0" {
            return Ok(HttpResponse::new(200, request.url, b"no courses".to_vec()));
        }
        panic!("unexpected Judge facade request")
    }
}

#[derive(Clone)]
struct CountingProbe(Arc<AtomicUsize>);

impl GatewayProbe for CountingProbe {
    fn probe(&self, _budget: Duration) -> NetworkState {
        self.0.fetch_add(1, Ordering::SeqCst);
        NetworkState::OffCampus
    }
}

struct NeverProbe;

impl GatewayProbe for NeverProbe {
    fn probe(&self, _budget: Duration) -> NetworkState {
        panic!("explicit policies must not run the gateway probe")
    }
}

fn test_root(label: &str) -> std::path::PathBuf {
    static NEXT_TEST_ROOT: AtomicU64 = AtomicU64::new(0);
    std::env::temp_dir().join(format!(
        "ubaa-facade-{label}-{}-{}",
        std::process::id(),
        NEXT_TEST_ROOT.fetch_add(1, Ordering::Relaxed)
    ))
}
