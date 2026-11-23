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
    observer.invalidate(Invalidation::RevokeAll).unwrap();
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
async fn 修复三_发现冲突和冲突终态不修改旁车() {
    let path = root("conflict-once");
    let store = signed_in(&path);
    let b = cache(&path);
    b.invalidate(Invalidation::RevokeAll).unwrap();
    write_route(&b, ConnectionMode::Direct);
    let mut a = client(&store, transport(ACCOUNT));
    a.auth_status().await.unwrap();
    drop(a.fork_parallel_readonly().unwrap());
    let snapshot = store.load_dual_versioned().unwrap().snapshot.unwrap();
    store.save_dual(&snapshot).unwrap();
    let file = path.join("business_session.json");
    let before = std::fs::read(&file).unwrap();

    assert!(
        a.fork_parallel_readonly()
            .err()
            .unwrap()
            .is_session_conflict()
    );
    assert_eq!(std::fs::read(&file).unwrap(), before);
    write_route(&b, ConnectionMode::WebVpn);
    let repopulated = std::fs::read(&file).unwrap();
    assert!(a.auth_status().await.unwrap_err().is_session_conflict());
    assert_eq!(std::fs::read(&file).unwrap(), repopulated);
    std::fs::remove_dir_all(path).unwrap();
}

#[tokio::test]
async fn 修复三_注销发出后才产生的双槽冲突不再次清理旁车() {
    let path = root("logout-cas-conflict");
    let store = signed_in(&path);
    let b = cache(&path);
    b.invalidate(Invalidation::RevokeAll).unwrap();
    write_route(&b, ConnectionMode::Direct);
    write_route(&b, ConnectionMode::WebVpn);
    let before = document(&path);
    let replacement = {
        let store = store.clone();
        let path = path.to_path_buf();
        Arc::new(move || {
            let saved = store.load_dual_versioned()?;
            store.save_dual(saved.snapshot.as_ref().unwrap())?;
            let fresh = cache(&path);
            write_route(&fresh, ConnectionMode::Direct);
            Ok(())
        })
    };
    let mut a = client(
        &store,
        Sso {
            replace_on_logout: Some(replacement),
            ..transport(ACCOUNT)
        },
    );
    assert!(a.logout().await.unwrap_err().is_session_conflict());
    let after = document(&path);
    assert!(after["routes"]["direct"]["spoc"].is_object());
    assert!(after["routes"]["webvpn"]["spoc"].is_null());
    for route in ["direct", "webvpn"] {
        assert_ne!(after["clear_nonces"][route], before["clear_nonces"][route]);
    }
    std::fs::remove_dir_all(path).unwrap();
}

#[tokio::test]
async fn 修复三_注销在入口发现冲突时保持旁车原样() {
    let path = root("logout-entry-conflict");
    let store = signed_in(&path);
    let mut a = client(&store, transport(ACCOUNT));
    a.auth_status().await.unwrap();
    let b = cache(&path);
    write_route(&b, ConnectionMode::Direct);
    drop(a.fork_parallel_readonly().unwrap());
    let snapshot = store.load_dual_versioned().unwrap().snapshot.unwrap();
    store.save_dual(&snapshot).unwrap();
    write_route(&b, ConnectionMode::WebVpn);
    let file = path.join("business_session.json");
    let before = std::fs::read(&file).unwrap();
    assert!(a.logout().await.unwrap_err().is_session_conflict());
    assert_eq!(std::fs::read(file).unwrap(), before);
    std::fs::remove_dir_all(path).unwrap();
}

#[tokio::test]
async fn 修复三_首个远端注销请求处取消时墓碑已生效() {
    let path = root("logout-cancel");
    let store = signed_in(&path);
    let b = cache(&path);
    write_route(&b, ConnectionMode::Direct);
    write_route(&b, ConnectionMode::WebVpn);
    let before = document(&path);
    let entered = Arc::new(tokio::sync::Notify::new());
    let mut a = client(
        &store,
        Sso {
            logout_entered: Some(Arc::clone(&entered)),
            ..transport(ACCOUNT)
        },
    );
    {
        let request = std::pin::pin!(a.logout());
        tokio::select! {
            result = request => panic!("注销不应先结束：{result:?}"),
            result = tokio::time::timeout(std::time::Duration::from_secs(5), entered.notified()) => result.unwrap(),
        }
    }
    let after = document(&path);
    assert!(after["account"].is_null() && after["routes"].is_null());
    for route in ["direct", "webvpn"] {
        assert_ne!(after["clear_nonces"][route], before["clear_nonces"][route]);
    }
    std::fs::remove_dir_all(path).unwrap();
}

#[path = "facade_cases/fix4.rs"]
mod fix4;

#[path = "facade_cases/fix5.rs"]
mod fix5;
