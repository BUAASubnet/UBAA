use super::client::{BridgeClient, BridgeConnectionMode, BridgeErrorCode, BridgeRoutePolicy};
use super::read_pool::ReadGroup;
use super::shared_account::BridgeSharedAccount;
use futures_util::FutureExt;
use std::path::PathBuf;
use ubaa_core::facade::testing::{DualSessionSnapshot, FileSessionStore, RouteSessionSnapshot};

fn fixture() -> PathBuf {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/command_delivery/tests")
        .join(uuid::Uuid::new_v4().to_string());
    std::fs::create_dir_all(&root).unwrap();
    for (name, value) in [
        ("materials.lock", ""),
        ("transaction.v1", "UBAA1:C"),
        ("account-generation.v1", "UBAA1:1"),
    ] {
        std::fs::write(root.join(name), value).unwrap();
    }
    FileSessionStore::new(root.join("core"))
        .unwrap()
        .save_dual(&DualSessionSnapshot::new(
            Some(RouteSessionSnapshot {
                cookies: vec![],
                authenticated_at: 1000,
                last_activity: 1001,
            }),
            None,
        ))
        .unwrap();
    root
}

#[tokio::test]
async fn 手动路线切换等待读取结束并阻止新读取插队() {
    for policy in [BridgeRoutePolicy::Direct, BridgeRoutePolicy::WebVpn] {
        let root = fixture();
        let bridge = BridgeClient::open(root.join("core").to_string_lossy().into()).unwrap();
        let reading = bridge.inner.read(Some(ReadGroup::Profile)).await.unwrap();
        let switching = bridge.set_default_route_policy(policy);
        tokio::pin!(switching);
        assert!(
            switching.as_mut().now_or_never().is_none(),
            "后台读取期间应等待切换，不能立即报告状态冲突"
        );
        assert!(
            bridge
                .inner
                .read(Some(ReadGroup::Academic))
                .now_or_never()
                .is_none(),
            "路线切换排队后，新读取必须等待"
        );
        drop(reading);
        let settings = switching.await.unwrap();
        assert_eq!(settings.default_policy, policy);
        assert_eq!(settings.active_routes, vec![BridgeConnectionMode::Direct]);
        let reading = bridge.inner.read(Some(ReadGroup::Profile)).await.unwrap();
        assert_eq!(
            reading.as_ref().unwrap().default_route_policy(),
            policy.into()
        );
        drop(reading);
        bridge.dispose().await.unwrap();
        let reopened = BridgeClient::open(root.join("core").to_string_lossy().into()).unwrap();
        assert_eq!(
            reopened.route_settings().await.unwrap().default_policy,
            policy
        );
        reopened.dispose().await.unwrap();
        std::fs::remove_dir_all(root).unwrap();
    }
}

#[tokio::test]
async fn 等待路线切换时关闭客户端不再保存策略() {
    let root = fixture();
    let bridge = BridgeClient::open(root.join("core").to_string_lossy().into()).unwrap();
    let reading = bridge.inner.read(Some(ReadGroup::Profile)).await.unwrap();
    let switching = bridge.set_default_route_policy(BridgeRoutePolicy::WebVpn);
    tokio::pin!(switching);
    assert!(switching.as_mut().now_or_never().is_none());
    let closing = bridge.dispose();
    tokio::pin!(closing);
    assert!(closing.as_mut().now_or_never().is_none());
    drop(reading);
    assert_eq!(
        switching.await.unwrap_err().code,
        BridgeErrorCode::ClientDisposed
    );
    closing.await.unwrap();
    let reopened = BridgeClient::open(root.join("core").to_string_lossy().into()).unwrap();
    assert_eq!(
        reopened.route_settings().await.unwrap().default_policy,
        BridgeRoutePolicy::Auto
    );
    reopened.dispose().await.unwrap();
    std::fs::remove_dir_all(root).unwrap();
}

#[tokio::test]
async fn 路线重开保持原共享归属且外部撤销仍拒绝派生() {
    let root = fixture();
    let bridge = BridgeClient::open(root.join("core").to_string_lossy().into()).unwrap();
    let scope = BridgeSharedAccount::capture(root.to_string_lossy().into(), 1).unwrap();
    bridge.bind_shared_account(&scope).await.unwrap();
    bridge
        .set_default_route_policy(BridgeRoutePolicy::Direct)
        .await
        .unwrap();
    let retained = bridge
        .inner
        .lock()
        .await
        .as_ref()
        .unwrap()
        .shared_account_guard()
        .is_some();
    std::fs::write(root.join("account-generation.v1"), "UBAA1:2").unwrap();
    let rejected = bridge
        .inner
        .lock()
        .await
        .as_mut()
        .unwrap()
        .fork_parallel_readonly()
        .is_err();
    bridge.dispose().await.unwrap();
    drop((bridge, scope));
    std::fs::remove_dir_all(root).unwrap();
    assert!(retained, "路线重开必须传递捕获时的固定共享归属");
    assert!(rejected, "撤销后重开的客户端不得派生读取");
}

#[tokio::test]
async fn 路线重开后关闭仍撤销当前客户端及在途派生() {
    let root = fixture();
    let bridge = BridgeClient::open(root.join("core").to_string_lossy().into()).unwrap();
    bridge
        .set_default_route_policy(BridgeRoutePolicy::Direct)
        .await
        .unwrap();
    let mut current = bridge.inner.lock().await.take().unwrap();
    let mut child = current.fork_parallel_readonly().unwrap();
    assert!(child.synchronize_parallel_readonly(&mut current).unwrap());
    bridge.dispose().await.unwrap();
    let current_closed = current
        .fork_parallel_readonly()
        .err()
        .is_some_and(|e| e.is_client_closed());
    let child_closed = !matches!(child.synchronize_parallel_readonly(&mut current), Ok(true));
    drop((bridge, current, child));
    std::fs::remove_dir_all(root).unwrap();
    assert!(current_closed, "关闭必须作用于当前重开客户端");
    assert!(child_closed, "当前客户端的派生任务也必须关闭");
}
