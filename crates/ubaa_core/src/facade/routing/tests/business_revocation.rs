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

fn setup(_name: &str, config: RouteConfig) -> (crate::test_tmp::TestTempDir, UbaaClient) {
    let path =
        crate::test_tmp::test_temp_dir("ubaa_core_facade_routing_business_revocation").unwrap();
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
    client.config_dir = Some(path.to_path_buf());
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

fn session_only_guard(path: &std::path::Path) -> crate::facade::SharedAccountGuard {
    for (name, value) in [
        ("materials.lock", ""),
        ("transaction.v1", "UBAA1:C"),
        ("account-generation.v1", "UBAA1:1"),
    ] {
        std::fs::write(path.join(name), value).unwrap();
    }
    crate::facade::SharedAccountGuard::new(path, 1)
        .unwrap()
        .with_session_retention(false)
}

fn prepare_identity_read(client: &mut UbaaClient) {
    client
        .direct_runtime
        .refresh_authentication(&mut || {})
        .unwrap();
    client
        .direct_runtime
        .remember_account_name(Some("fixture-user"));
}

fn persist_identity(client: &mut UbaaClient) {
    let route = ConnectionMode::Direct;
    let mut group = client.fork_parallel_readonly().unwrap();
    group
        .runtime_for(route)
        .feature_state()
        .seed_academic_identity(Some(StudentKind::Graduate));
    group.persist_business_session(route);
}

#[test]
fn 保留标记_r3_公开路线切换后的读组不写盘() {
    let (path, mut client) = setup("session-only-reopen", RouteConfig::default());
    client.config_dir = Some(path.to_path_buf());
    prepare_identity_read(&mut client);
    persist_identity(&mut client);
    drop(client);

    let file = path.join("business_session.json");
    let old: serde_json::Value = serde_json::from_slice(&std::fs::read(&file).unwrap()).unwrap();
    assert!(old["routes"]["direct"]["identity"].is_object());
    let mut client = UbaaClient::open(&path).unwrap();
    client.bind_shared_account(Some(session_only_guard(&path)));
    client
        .set_default_route_policy(RoutePolicy::Direct)
        .unwrap();
    let mut reopened = client.reopen_for_route_policy().unwrap();
    prepare_identity_read(&mut reopened);
    let before = std::fs::read(&file).unwrap();
    let assert_no_business_entries = |bytes: &[u8]| {
        let document: serde_json::Value = serde_json::from_slice(bytes).unwrap();
        for route in ["direct", "webvpn"] {
            assert!(
                document["routes"][route]
                    .as_object()
                    .is_none_or(serde_json::Map::is_empty)
            );
        }
    };
    assert_no_business_entries(&before);
    persist_identity(&mut reopened);
    drop((reopened, client));
    let after = std::fs::read(&file).unwrap();
    assert_no_business_entries(&after);
    assert!(after == before, "只读写回不得改写旁车");
    std::fs::remove_dir_all(path).unwrap();
}

#[test]
fn 保留标记_a_同步前比较完整共享归属并重新派生() {
    let (path, mut parent) = setup("session-only-sync-scope", RouteConfig::default());
    prepare_identity_read(&mut parent);
    let session_only = session_only_guard(&path);
    let retained = crate::facade::SharedAccountGuard::new(&path, 1).unwrap();
    parent.bind_shared_account(Some(retained));
    let mut stale = parent.fork_parallel_readonly().unwrap();
    // 同目录同代次重新捕获的保留归属也可以继续复用。
    let retained = crate::facade::SharedAccountGuard::new(&path, 1).unwrap();
    parent.bind_shared_account(Some(retained));
    assert!(stale.synchronize_parallel_readonly(&mut parent).unwrap());

    let file = path.join("business_session.json");
    let before = std::fs::read(&file).unwrap();
    parent.bind_shared_account(Some(session_only));
    assert!(!stale.synchronize_parallel_readonly(&mut parent).unwrap());

    let mut fresh = parent.fork_parallel_readonly().unwrap();
    assert!(fresh.synchronize_parallel_readonly(&mut parent).unwrap());
    fresh
        .runtime_for(ConnectionMode::Direct)
        .feature_state()
        .seed_academic_identity(Some(StudentKind::Graduate));
    fresh.persist_business_session(ConnectionMode::Direct);
    drop((stale, fresh, parent));
    assert_eq!(std::fs::read(file).unwrap(), before);
    std::fs::remove_dir_all(path).unwrap();
}

#[test]
fn 保留标记_r4_派生读组只更新内存() {
    let (path, mut client) = setup("session-only-worker", RouteConfig::default());
    prepare_identity_read(&mut client);
    client.bind_shared_account(Some(session_only_guard(&path)));
    let file = path.join("business_session.json");
    let before = std::fs::read(&file).unwrap();
    persist_identity(&mut client);
    let mut next = client.fork_parallel_readonly().unwrap();
    assert_eq!(
        next.runtime_for(ConnectionMode::Direct)
            .feature_state()
            .cached_academic_identity(),
        Some(StudentKind::Graduate)
    );
    drop((next, client));
    assert!(
        std::fs::read(file).unwrap() == before,
        "只读写回不得改写旁车"
    );
    std::fs::remove_dir_all(path).unwrap();
}

#[test]
fn 保留标记_r5_拒绝旧材料只更新内存() {
    use crate::session::business_cache::{BusinessMaterial, BusinessScope};

    let (path, mut client) = setup("session-only-reject", RouteConfig::default());
    prepare_identity_read(&mut client);
    persist_identity(&mut client);
    drop(client);
    let file = path.join("business_session.json");
    let before = std::fs::read(&file).unwrap();

    let mut client = UbaaClient::open(&path).unwrap();
    prepare_identity_read(&mut client);
    client.bind_shared_account(Some(session_only_guard(&path)));
    let route = ConnectionMode::Direct;
    let mut group = client.fork_parallel_readonly().unwrap();
    let runtime = group.runtime_for(route);
    assert_eq!(
        runtime.feature_state().cached_academic_identity(),
        Some(StudentKind::Graduate)
    );
    runtime.reject_business_material(
        BusinessScope::Identity,
        BusinessMaterial::Identity(StudentKind::Graduate),
    );
    let mut next = client.fork_parallel_readonly().unwrap();
    assert_eq!(
        next.runtime_for(route)
            .feature_state()
            .cached_academic_identity(),
        None
    );
    drop((next, group, client));
    assert!(std::fs::read(file).unwrap() == before, "拒绝不得改写旁车");
    std::fs::remove_dir_all(path).unwrap();
}
