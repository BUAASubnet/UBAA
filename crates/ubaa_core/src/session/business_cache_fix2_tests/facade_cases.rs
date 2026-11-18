use super::*;
use crate::facade::UbaaClient;

fn client(store: &FileSessionStore, mock: Sso) -> UbaaClient {
    UbaaClient::with_transports(mock.clone(), mock, store.clone()).unwrap()
}

fn signed_in(path: &Path) -> FileSessionStore {
    let store = FileSessionStore::new(path).unwrap();
    let sessions = DualSessionCoordinator::new(store.clone()).unwrap();
    for route in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        let mut runtime =
            ClientRuntime::new(route, transport(ACCOUNT), sessions.route_store(route)).unwrap();
        runtime.refresh_authentication(&mut || {}).unwrap();
    }
    store
}

#[tokio::test]
async fn 修复二_交互准备后取消时两条路线已清空() {
    let path = root("interactive-cancel");
    let store = signed_in(&path);
    let observer = cache(&path);
    observer.invalidate(Invalidation::RevokeAll);
    for route in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        write_route(&observer, route);
    }
    let before = document(&path);
    let mut client = client(
        &store,
        Sso {
            interactive_pending: true,
            ..transport(ACCOUNT)
        },
    );
    let cancellation = client.interactive_login_cancellation();
    let login = cancellation.begin(ACCOUNT).unwrap();
    // 合成登录页不自动完成业务登录。
    let prepared = client.prepare_interactive_login_for(&login).await.unwrap();
    assert!(
        prepared
            .routes
            .iter()
            .all(|route| route.state == crate::domain::InteractiveRouteState::Prepared)
    );
    let cleared = document(&path);
    cancellation.cancel();
    client.discard_cancelled_interactive_login();
    let after = document(&path);
    assert_eq!(after, cleared);
    assert!(after["account"].is_null() && after["routes"].is_null());
    for route in ["direct", "webvpn"] {
        assert_ne!(before["clear_nonces"][route], after["clear_nonces"][route]);
    }
    std::fs::remove_dir_all(path).unwrap();
}

#[tokio::test]
async fn 修复二_首次冲突仅轮换此前观察且仍匹配的路线并只清理一次() {
    let path = root("conflict-once");
    let store = signed_in(&path);
    let b = cache(&path);
    b.invalidate(Invalidation::RevokeAll);
    write_route(&b, ConnectionMode::Direct);
    let mut a = client(&store, transport(ACCOUNT));
    a.auth_status().await.unwrap();
    drop(a.fork_parallel_readonly().unwrap());
    let before = document(&path);
    b.invalidate(Invalidation::SameAccountLogin(ConnectionMode::WebVpn));
    write_route(&b, ConnectionMode::WebVpn);
    let fresh = document(&path);
    let snapshot = store.load_dual_versioned().unwrap().snapshot.unwrap();
    store.save_dual(&snapshot).unwrap();

    assert!(
        a.fork_parallel_readonly()
            .err()
            .unwrap()
            .is_session_conflict()
    );
    let after = document(&path);
    assert_ne!(
        after["clear_nonces"]["direct"],
        before["clear_nonces"]["direct"]
    );
    assert_eq!(
        after["clear_nonces"]["webvpn"],
        fresh["clear_nonces"]["webvpn"]
    );
    assert!(after["routes"]["direct"]["spoc"].is_null());
    assert!(after["routes"]["webvpn"]["spoc"].is_object());
    write_route(&b, ConnectionMode::Direct);
    let repopulated = document(&path);
    assert!(a.auth_status().await.unwrap_err().is_session_conflict());
    assert_eq!(document(&path), repopulated);
    std::fs::remove_dir_all(path).unwrap();
}

#[tokio::test]
async fn 修复二_注销中的双槽比较交换冲突仍无条件清空旁车() {
    let path = root("logout-cas-conflict");
    let store = signed_in(&path);
    let b = cache(&path);
    b.invalidate(Invalidation::RevokeAll);
    write_route(&b, ConnectionMode::Direct);
    write_route(&b, ConnectionMode::WebVpn);
    let mut a = client(
        &store,
        Sso {
            replace_on_logout: Some(store.clone()),
            ..transport(ACCOUNT)
        },
    );
    let before = document(&path);
    assert!(a.logout().await.unwrap_err().is_session_conflict());
    let after = document(&path);
    assert!(after["account"].is_null() && after["routes"].is_null());
    for route in ["direct", "webvpn"] {
        assert_ne!(after["clear_nonces"][route], before["clear_nonces"][route]);
    }
    std::fs::remove_dir_all(path).unwrap();
}
