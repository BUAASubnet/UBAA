use super::*;
use async_trait::async_trait;
use std::sync::Arc;
use ubaa_core::facade::testing::{
    FileSessionStore, GatewayProbe, HttpMethod, HttpRequest, HttpResponse, HttpTransport,
    RouteConfig, to_webvpn_url,
};
use ubaa_test_support::{ExpectedRequest, MockTransport};

struct NeverProbe;
impl GatewayProbe for NeverProbe {
    fn probe(&self, _: std::time::Duration) -> core::NetworkState {
        panic!("固定路线禁止探测");
    }
}

#[derive(Clone)]
struct WaitingTransport(Arc<tokio::sync::Notify>);
#[async_trait]
impl HttpTransport for WaitingTransport {
    async fn execute(&self, _: HttpRequest) -> core::Result<HttpResponse> {
        self.0.notify_one();
        std::future::pending().await
    }
}
fn fixture() -> std::path::PathBuf {
    let root = std::env::temp_dir().join(format!("ubaa-scoped-logout-{}", uuid::Uuid::new_v4()));
    std::fs::create_dir_all(&root).unwrap();
    for (name, value) in [
        ("materials.lock", ""),
        ("transaction.v1", "UBAA1:C"),
        ("account-generation.v1", "UBAA1:1"),
    ] {
        std::fs::write(root.join(name), value).unwrap();
    }
    root
}
fn advance(root: &std::path::Path) {
    let lock = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .open(root.join("materials.lock"))
        .unwrap();
    lock.lock().unwrap();
    std::fs::write(root.join("account-generation.v1"), "UBAA1:2").unwrap();
}
#[tokio::test]
async fn 条件退出只在指定操作使用撤销票据并恢复旧归属() {
    let root = fixture();
    let url = "https://sso.buaa.edu.cn/logout";
    let routed = to_webvpn_url(url).unwrap();
    let direct = MockTransport::new([ExpectedRequest::new(
        HttpMethod::Get,
        url,
        HttpResponse::new(200, url, Vec::new()),
    )]);
    let web = MockTransport::new([ExpectedRequest::new(
        HttpMethod::Get,
        &routed,
        HttpResponse::new(200, &routed, Vec::new()),
    )]);
    let bridge = BridgeClient::open(root.join("core").to_string_lossy().into()).unwrap();
    *bridge.inner.lock().await = Some(
        core::UbaaClient::with_routing(
            direct.clone(),
            web.clone(),
            FileSessionStore::new(root.join("core")).unwrap(),
            RouteConfig::default(),
            NeverProbe,
        )
        .unwrap(),
    );
    let original = BridgeSharedAccount::capture(root.to_string_lossy().into(), 1).unwrap();
    bridge.bind_shared_account(&original).await.unwrap();
    let cache = BridgeOfflineCache::open_shared(
        root.to_string_lossy().into(),
        "0123456789abcdef0123456789abcdef".into(),
        "synthetic-user".into(),
        vec![7; 32],
        &original,
    )
    .await
    .unwrap();
    assert_eq!(cache.usage().await.unwrap().entry_count, 0);
    advance(&root);
    let revoked = BridgeSharedAccount::capture(root.to_string_lossy().into(), 2).unwrap();
    bridge.logout_with_shared_account(&revoked).await.unwrap();
    assert_eq!(direct.requests().unwrap().len(), 1);
    assert_eq!(web.requests().unwrap().len(), 1);
    direct.assert_exhausted().unwrap();
    web.assert_exhausted().unwrap();
    assert!(
        bridge
            .inner
            .lock()
            .await
            .as_ref()
            .unwrap()
            .shared_account_guard()
            .unwrap()
            .check()
            .is_err()
    );
    let before = direct.requests().unwrap().len();
    assert!(
        bridge
            .bykc_chosen_courses_on_route(super::super::client::BridgeConnectionMode::Direct)
            .await
            .is_err()
    );
    assert_eq!(direct.requests().unwrap().len(), before);
    assert!(cache.usage().await.is_err());
    // 受限 RPC 结束后，普通客户端仍持旧票据，不能重新打开实际缓存。
    let restored = BridgeSharedAccount {
        guard: bridge
            .inner
            .lock()
            .await
            .as_ref()
            .unwrap()
            .shared_account_guard()
            .unwrap(),
    };
    assert!(
        BridgeOfflineCache::open_shared(
            root.to_string_lossy().into(),
            "0123456789abcdef0123456789abcdef".into(),
            "synthetic-user".into(),
            vec![7; 32],
            &restored,
        )
        .await
        .is_err()
    );
    cache.close().await.unwrap();
    drop(cache);
    bridge.dispose().await.unwrap();
    drop(bridge);
    std::fs::remove_dir_all(root).unwrap();
}
#[tokio::test]
async fn 退出_future取消也恢复旧归属不遗留活动清理许可() {
    let root = fixture();
    let entered = Arc::new(tokio::sync::Notify::new());
    let bridge = Arc::new(BridgeClient::open(root.join("core").to_string_lossy().into()).unwrap());
    *bridge.inner.lock().await = Some(
        core::UbaaClient::with_routing(
            WaitingTransport(entered.clone()),
            MockTransport::new([]),
            FileSessionStore::new(root.join("core")).unwrap(),
            RouteConfig::default(),
            NeverProbe,
        )
        .unwrap(),
    );
    let original = BridgeSharedAccount::capture(root.to_string_lossy().into(), 1).unwrap();
    bridge.bind_shared_account(&original).await.unwrap();
    let cache = BridgeOfflineCache::open_shared(
        root.to_string_lossy().into(),
        "0123456789abcdef0123456789abcdef".into(),
        "synthetic-user".into(),
        vec![7; 32],
        &original,
    )
    .await
    .unwrap();
    assert_eq!(cache.usage().await.unwrap().entry_count, 0);
    advance(&root);
    let revoked = BridgeSharedAccount::capture(root.to_string_lossy().into(), 2).unwrap();
    let worker = bridge.clone();
    let task = tokio::spawn(async move { worker.logout_with_shared_account(&revoked).await });
    entered.notified().await;
    task.abort();
    assert!(task.await.unwrap_err().is_cancelled());
    assert!(
        bridge
            .inner
            .lock()
            .await
            .as_ref()
            .unwrap()
            .shared_account_guard()
            .unwrap()
            .check()
            .is_err()
    );
    assert!(cache.usage().await.is_err());
    // 受限 RPC 结束后，普通客户端仍持旧票据，不能重新打开实际缓存。
    let restored = BridgeSharedAccount {
        guard: bridge
            .inner
            .lock()
            .await
            .as_ref()
            .unwrap()
            .shared_account_guard()
            .unwrap(),
    };
    assert!(
        BridgeOfflineCache::open_shared(
            root.to_string_lossy().into(),
            "0123456789abcdef0123456789abcdef".into(),
            "synthetic-user".into(),
            vec![7; 32],
            &restored,
        )
        .await
        .is_err()
    );
    cache.close().await.unwrap();
    drop(cache);
    bridge.dispose().await.unwrap();
    drop(bridge);
    std::fs::remove_dir_all(root).unwrap();
}

#[derive(Clone)]
struct PanicTransport;
#[async_trait]
impl HttpTransport for PanicTransport {
    async fn execute(&self, _: HttpRequest) -> core::Result<HttpResponse> {
        panic!("合成 transport panic");
    }
}

#[tokio::test]
async fn 退出传输错误或panic后恢复旧归属且旧缓存仍被拒绝() {
    for panic in [false, true] {
        let root = fixture();
        let bridge = BridgeClient::open(root.join("core").to_string_lossy().into()).unwrap();
        let session = FileSessionStore::new(root.join("core")).unwrap();
        let client = if panic {
            core::UbaaClient::with_routing(
                PanicTransport,
                MockTransport::new([]),
                session,
                RouteConfig::default(),
                NeverProbe,
            )
        } else {
            // 空脚本在任何请求时返回错误，绝不访问真实 HTTP。
            core::UbaaClient::with_routing(
                MockTransport::new([]),
                MockTransport::new([]),
                session,
                RouteConfig::default(),
                NeverProbe,
            )
        }
        .unwrap();
        *bridge.inner.lock().await = Some(client);
        let original = BridgeSharedAccount::capture(root.to_string_lossy().into(), 1).unwrap();
        bridge.bind_shared_account(&original).await.unwrap();
        let cache = BridgeOfflineCache::open_shared(
            root.to_string_lossy().into(),
            "0123456789abcdef0123456789abcdef".into(),
            "synthetic-user".into(),
            vec![7; 32],
            &original,
        )
        .await
        .unwrap();
        advance(&root);
        let revoked = BridgeSharedAccount::capture(root.to_string_lossy().into(), 2).unwrap();
        let result = bridge.logout_with_shared_account(&revoked).await;
        assert_eq!(result.is_err(), panic); // 原注销合同忽略远端错误，panic 映射安全错误。
        let restored = BridgeSharedAccount {
            guard: bridge
                .inner
                .lock()
                .await
                .as_ref()
                .unwrap()
                .shared_account_guard()
                .unwrap(),
        };
        assert!(restored.guard.check().is_err());
        assert!(cache.usage().await.is_err());
        assert!(
            BridgeOfflineCache::open_shared(
                root.to_string_lossy().into(),
                "0123456789abcdef0123456789abcdef".into(),
                "synthetic-user".into(),
                vec![7; 32],
                &restored
            )
            .await
            .is_err()
        );
        cache.close().await.unwrap();
        drop(cache);
        bridge.dispose().await.unwrap();
        drop(bridge);
        std::fs::remove_dir_all(root).unwrap();
    }
}

#[derive(Clone)]
struct RevokeTransport(std::path::PathBuf);
#[async_trait]
impl HttpTransport for RevokeTransport {
    async fn execute(&self, request: HttpRequest) -> core::Result<HttpResponse> {
        // 网络等待期间不持材料锁，模拟另一进程在此时推进共享身份。
        std::fs::write(self.0.join("account-generation.v1"), "UBAA1:3").unwrap();
        Ok(HttpResponse::new(200, request.url, Vec::new()))
    }
}
#[tokio::test]
async fn 受限退出本地失败也恢复旧归属不采纳更新版本() {
    let root = fixture();
    let bridge = BridgeClient::open(root.join("core").to_string_lossy().into()).unwrap();
    *bridge.inner.lock().await = Some(
        core::UbaaClient::with_routing(
            RevokeTransport(root.clone()),
            MockTransport::new([]),
            FileSessionStore::new(root.join("core")).unwrap(),
            RouteConfig::default(),
            NeverProbe,
        )
        .unwrap(),
    );
    let original = BridgeSharedAccount::capture(root.to_string_lossy().into(), 1).unwrap();
    bridge.bind_shared_account(&original).await.unwrap();
    advance(&root);
    let revoked = BridgeSharedAccount::capture(root.to_string_lossy().into(), 2).unwrap();
    assert!(bridge.logout_with_shared_account(&revoked).await.is_err());
    // 将合成记录设回 1 后，原 guard 才能通过，证明恢复的是原归属而非票据 2 或版本 3。
    std::fs::write(root.join("account-generation.v1"), "UBAA1:1").unwrap();
    assert!(
        bridge
            .inner
            .lock()
            .await
            .as_ref()
            .unwrap()
            .shared_account_guard()
            .unwrap()
            .check()
            .is_ok()
    );
    bridge.dispose().await.unwrap();
    drop(bridge);
    std::fs::remove_dir_all(root).unwrap();
}
