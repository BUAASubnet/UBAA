use super::*;
use crate::config::RouteConfig;
use crate::connection::SystemGatewayProbe;
use crate::internal::route_state::StudentKind;
use crate::ports::{HttpRequest, HttpResponse, HttpTransport};
use crate::session::FileSessionStore;

#[derive(Clone, Copy)]
struct NoRequests;

#[async_trait::async_trait]
impl HttpTransport for NoRequests {
    async fn execute(&self, _: HttpRequest) -> Result<HttpResponse> {
        panic!("不应发出请求");
    }
}

fn setup(name: &str, config: RouteConfig) -> (std::path::PathBuf, UbaaClient) {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/biz_cache_p2")
        .join(format!("{name}-{}", uuid::Uuid::new_v4()));
    let store = FileSessionStore::new(&path).unwrap();
    let client =
        UbaaClient::with_routing(NoRequests, NoRequests, store, config, SystemGatewayProbe)
            .unwrap();
    (path, client)
}

#[test]
fn 修复三_过期读组不撤销其他读组材料() {
    let (path, mut parent) = setup("stale-group", RouteConfig::default());
    parent
        .direct_runtime
        .refresh_authentication(&mut || {})
        .unwrap();
    parent
        .direct_runtime
        .remember_account_name(Some("fixture-user"));
    let mut stale = parent.fork_parallel_readonly().unwrap();
    parent.direct_runtime.clear_feature_state();
    let mut current = parent.fork_parallel_readonly().unwrap();
    let route = ConnectionMode::Direct;
    current
        .runtime_for(route)
        .feature_state()
        .seed_academic_identity(Some(StudentKind::Graduate));
    current.persist_business_session(route);
    let error = stale.guard_latest_session_ownership().unwrap_err();
    assert_eq!(error.code, ErrorCode::AuthenticationRequired);
    let mut fresh = parent.fork_parallel_readonly().unwrap();
    assert_eq!(
        fresh
            .runtime_for(route)
            .feature_state()
            .cached_academic_identity(),
        Some(StudentKind::Graduate)
    );
    drop((stale, current, fresh, parent));
    std::fs::remove_dir_all(path).unwrap();
}

#[test]
fn 修复三_仅移除有效功能路线覆盖也全量撤销() {
    let config =
        RouteConfig::parse("[route]\ndefault = \"direct\"\n[route.features]\nspoc = \"webvpn\"\n")
            .unwrap();
    let (path, mut client) = setup("feature-route", config);
    client.config_dir = Some(path.clone());
    client.clear_business_session_cache();
    let file = path.join("business_session.json");
    let before: serde_json::Value = serde_json::from_slice(&std::fs::read(&file).unwrap()).unwrap();
    client
        .set_default_route_policy(RoutePolicy::Direct)
        .unwrap();
    assert_eq!(
        client.config.feature(ReadonlyFeature::Spoc),
        RoutePolicy::Direct
    );
    let after: serde_json::Value = serde_json::from_slice(&std::fs::read(file).unwrap()).unwrap();
    for route in ["direct", "webvpn"] {
        assert_ne!(after["clear_nonces"][route], before["clear_nonces"][route]);
    }
    std::fs::remove_dir_all(path).unwrap();
}

#[test]
fn 修复三_冲突客户端不再提供内存种子() {
    let (path, mut client) = setup("conflicting-seeds", RouteConfig::default());
    let route = ConnectionMode::Direct;
    client
        .direct_runtime
        .refresh_authentication(&mut || {})
        .unwrap();
    client
        .direct_runtime
        .remember_account_name(Some("fixture-user"));
    let mut group = client.fork_parallel_readonly().unwrap();
    group
        .runtime_for(route)
        .feature_state()
        .seed_academic_identity(Some(StudentKind::Graduate));
    group.persist_business_session(route);
    let now = chrono::Utc::now().timestamp();
    let identity = crate::session::business_cache::BusinessScope::Identity as usize;
    assert!(
        client.business_sessions.seeds("fixture-user", route, now).1[identity]
            .material
            .is_some()
    );
    let store = FileSessionStore::new(&path).unwrap();
    store
        .save_dual(&store.load_dual().unwrap().unwrap())
        .unwrap();
    assert!(
        client
            .guard_latest_session_ownership()
            .unwrap_err()
            .is_session_conflict()
    );
    assert!(
        client.business_sessions.seeds("fixture-user", route, now).1[identity]
            .material
            .is_none()
    );
    drop((group, client));
    std::fs::remove_dir_all(path).unwrap();
}
