use super::*;
use crate::{
    agenda::sync::coordinator::{
        BeforeCommit, RemoteCommit, RemoteError, RemoteLocation, SyncCoordinator, SyncRemote,
    },
    domain::RoutePolicy,
    error::{ErrorCode, ErrorKind, Result, UbaaError},
    facade::{
        NetworkState, SharedAccountGuard,
        testing::{
            FileSessionStore, GatewayProbe, HttpRequest, HttpResponse, HttpTransport, RouteConfig,
        },
    },
};
use async_trait::async_trait;
use std::path::PathBuf;
struct NeverNetwork;
#[async_trait]
impl HttpTransport for NeverNetwork {
    async fn execute(&self, _: HttpRequest) -> Result<HttpResponse> {
        panic!("未验证同步不得发送请求")
    }
}
struct NeverProbe;
impl GatewayProbe for NeverProbe {
    fn probe(&self, _: std::time::Duration) -> NetworkState {
        panic!("固定路线不得探测")
    }
}
fn root() -> PathBuf {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/agenda_sync_dev")
        .join(uuid::Uuid::new_v4().to_string());
    std::fs::create_dir_all(&root).unwrap();
    root
}
fn now() -> AgendaTime {
    AgendaTime::new(chrono::DateTime::parse_from_rfc3339("2026-03-01T00:00:00+08:00").unwrap())
}
fn fixture() -> (PathBuf, AgendaStore, UbaaClient) {
    let root = root();
    for (name, value) in [
        ("materials.lock", ""),
        ("transaction.v1", "UBAA1:C"),
        ("account-generation.v1", "UBAA1:1"),
    ] {
        std::fs::write(root.join(name), value).unwrap();
    }
    let owner = SharedAccountGuard::new(&root, 1).unwrap();
    let store =
        AgendaStore::open_shared(&root, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", owner.clone()).unwrap();
    let mut config = RouteConfig::default();
    config.default = RoutePolicy::Direct;
    let mut client = UbaaClient::with_routing(
        NeverNetwork,
        NeverNetwork,
        FileSessionStore::new(&root).unwrap(),
        config,
        NeverProbe,
    )
    .unwrap();
    client.bind_shared_account(Some(owner));
    client.config_dir = Some(root.clone());
    (root, store, client)
}
#[test]
fn 独立快照使用本身作用域而旧共享条件覆盖能力保持关闭() {
    let (root, _store, mut client) = fixture();
    let scratch = root.join("scratch");
    assert_eq!(
        client.bhpan_capabilities().conditional_replace,
        crate::domain::bhpan::BhpanCapability::Unverified
    );
    let binding = Binding::capture(&client);
    let remote = remote::BhpanRemote::new(&mut client, binding, &scratch);
    assert!(remote.check_current().is_ok());
    assert!(!scratch.exists());
    drop(remote);
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn 不同材料域或共享代次不能绑定同一同步库() {
    let root = root();
    let first = SharedAccountGuard::new(&root, 1).unwrap();
    let store = AgendaStore::open(&root, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        .unwrap()
        .with_shared_account(first.clone());
    assert!(store.matches_sync_guard(Some(&first)));
    assert!(!store.matches_sync_guard(None));
    assert!(!store.matches_sync_guard(Some(&SharedAccountGuard::new(&root, 2).unwrap())));
    assert!(!store.matches_sync_guard(Some(
        &SharedAccountGuard::new(&root.join("other"), 1).unwrap()
    )));
    std::fs::remove_dir_all(root).unwrap();
}
struct ErrorRemote(UbaaError);
#[async_trait]
impl SyncRemote for ErrorRemote {
    type Version = ();
    fn check_current(&self) -> std::result::Result<(), RemoteError> {
        Err(RemoteError::Core(self.0.clone()))
    }
    fn same_version(&self, (): &(), (): &()) -> bool {
        true
    }
    fn publication(&self, (): &()) -> crate::agenda::sync::publication::Publication {
        unreachable!()
    }
    fn object_key(&self, (): &()) -> String {
        "fixture".into()
    }
    async fn locate(&mut self) -> std::result::Result<RemoteLocation<Vec<()>>, RemoteError> {
        unreachable!()
    }
    async fn read_version(&mut self, (): &()) -> std::result::Result<Vec<u8>, RemoteError> {
        unreachable!()
    }
    async fn publish_once(
        &mut self,
        _: crate::agenda::sync::publication::Publication,
        _: &[u8],
        _: BeforeCommit<'_>,
    ) -> std::result::Result<RemoteCommit<()>, RemoteError> {
        unreachable!()
    }
}
#[tokio::test]
async fn 同步保留云盘原始类型错误供命令映射退出码() {
    let root = root();
    for error in [
        UbaaError::new(ErrorCode::Timeout, ErrorKind::Network, true, "合成超时"),
        UbaaError::authentication_required("合成认证要求"),
        UbaaError::client_closed(),
        UbaaError::shared_account_conflict(),
    ] {
        let store = AgendaStore::open(&root, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa").unwrap();
        let result = SyncCoordinator::new(store, ErrorRemote(error.clone()))
            .run(AgendaSyncAction::Pull, now())
            .await;
        assert!(matches!(result, Err(AgendaSyncError::Remote(actual)) if actual == error));
    }
    std::fs::remove_dir_all(root).unwrap();
}

#[tokio::test]
async fn 同账号新路线使旧确认失效并允许重新捕获当前作用域() {
    let (root, store, mut client) = fixture();
    let mut service = AgendaSyncService::new(store, root.join("scratch"));
    let original = client.agenda_sync_scope().unwrap();
    client
        .set_default_route_policy(RoutePolicy::Direct)
        .unwrap();
    let current = client.agenda_sync_scope().unwrap();
    assert!(original.binding != current.binding);
    assert!(matches!(
        service.run_confirmed(&mut client, &original, now()).await,
        Err(AgendaSyncError::Local(CacheError::Superseded))
    ));
    drop(service);
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}

struct SyntheticNetwork {
    campus: std::sync::atomic::AtomicBool,
    calls: std::sync::atomic::AtomicUsize,
}

impl GatewayProbe for std::sync::Arc<SyntheticNetwork> {
    fn probe(&self, _: std::time::Duration) -> NetworkState {
        use std::sync::atomic::Ordering::SeqCst;
        self.calls.fetch_add(1, SeqCst);
        if self.campus.load(SeqCst) {
            NetworkState::Campus
        } else {
            NetworkState::OffCampus
        }
    }
}

fn auto_client(
    root: &std::path::Path,
    campus: bool,
    ttl: std::time::Duration,
) -> (UbaaClient, std::sync::Arc<SyntheticNetwork>) {
    let network = std::sync::Arc::new(SyntheticNetwork {
        campus: campus.into(),
        calls: 0.into(),
    });
    let mut config = RouteConfig::default();
    config.default = RoutePolicy::Auto;
    let mut client = UbaaClient::with_routing_and_probe_ttl(
        NeverNetwork,
        NeverNetwork,
        FileSessionStore::new(root).unwrap(),
        config,
        network.clone(),
        ttl,
    )
    .unwrap();
    client
        .direct_runtime
        .refresh_authentication(&mut || {})
        .unwrap();
    (client, network)
}

#[test]
fn auto确认只复用未过期且支持创建的实际路线观察() {
    use std::{sync::atomic::Ordering::SeqCst, time::Duration};
    for (campus, ttl, allowed) in [
        (true, Duration::from_mins(1), true),
        (false, Duration::from_mins(1), false),
        (true, Duration::ZERO, false),
    ] {
        let root = root();
        let (mut client, network) = auto_client(&root, campus, ttl);
        assert!(matches!(
            client.agenda_sync_scope(),
            Err(AgendaSyncError::Local(CacheError::Superseded))
        ));
        assert_eq!(network.calls.load(SeqCst), 0);
        let actual = match client.resolve_bhpan_route() {
            Ok(route) => route.resolution.mode,
            Err(error) => error.resolution.unwrap().mode,
        };
        let confirmation = client.agenda_sync_scope();
        if allowed {
            assert_eq!(confirmation.unwrap().mode, actual);
        } else {
            assert!(matches!(
                confirmation,
                Err(AgendaSyncError::Local(CacheError::Superseded))
            ));
        }
        assert_eq!(network.calls.load(SeqCst), 1);
        drop(client);
        std::fs::remove_dir_all(root).unwrap();
    }
}

#[tokio::test]
async fn auto确认由实际云盘路线解析拒绝且不再选择路线() {
    use std::{sync::atomic::Ordering::SeqCst, time::Duration};
    let root = root();
    let (mut client, network) = auto_client(&root, true, Duration::ZERO);
    let original = client.resolve_bhpan_route().unwrap().resolution.mode;
    assert_eq!(original, ConnectionMode::Direct);
    // 零 TTL 模拟确认发起后，原 Direct 观察已经过期。
    network.campus.store(false, SeqCst);
    let error = CONFIRMED_AGENDA_ROUTE
        .scope(original, client.bhpan_personal_root())
        .await
        .unwrap_err();
    assert!(error.is_agenda_creation_route_changed());
    assert_eq!(
        network.calls.load(SeqCst),
        2,
        "确认检查复用云盘本次实际解析"
    );
    let ordinary = client.bhpan_personal_root().await.unwrap_err();
    assert_eq!(ordinary.code, ErrorCode::PermissionDenied);
    assert!(!ordinary.is_agenda_creation_route_changed());
    assert_eq!(network.calls.load(SeqCst), 3, "普通 Auto 保留原解析");
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}
