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
use ubaa_core::session::{FileSessionStore, SessionSnapshot, SessionStore};

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

#[derive(Clone)]
struct CountingTransport(Arc<AtomicUsize>);

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
