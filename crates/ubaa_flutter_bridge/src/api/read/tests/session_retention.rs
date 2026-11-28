use super::{Fixture, SPOC_OLD, SeqCst, Transport, restored};

fn shared_guard(
    fixture: &Fixture,
    generation: u64,
    retain_session: bool,
) -> crate::api::shared_account::BridgeSharedAccount {
    use crate::api::shared_account::BridgeSharedAccount;
    let directory = fixture.0.join("account");
    std::fs::create_dir_all(&directory).unwrap();
    for (name, value) in [
        ("materials.lock", ""),
        ("transaction.v1", "UBAA1:C"),
        ("account-generation.v1", "UBAA1:1"),
    ] {
        std::fs::write(directory.join(name), value).unwrap();
    }
    BridgeSharedAccount::capture(
        directory.to_string_lossy().into(),
        generation,
        retain_session,
    )
    .unwrap()
}

#[tokio::test]
async fn 保留标记_r1_两批读取只在内存复用_spoc() {
    let fixture = Fixture::in_task("session_only_login");
    let transport = Transport::default();
    let bridge = restored(fixture.1.clone(), "direct", &transport).await;
    bridge
        .bind_shared_account(&shared_guard(&fixture, 1, false), None)
        .await
        .unwrap();
    let before = std::fs::read(fixture.cache()).ok();
    for _ in 0..2 {
        bridge.spoc_assignments().await.unwrap();
    }
    assert_eq!(transport.calls.spoc_logins.load(SeqCst), 1);
    assert_eq!(transport.calls.spoc_terms.load(SeqCst), 2);
    drop(bridge);
    assert!(
        std::fs::read(fixture.cache()).ok() == before,
        "只读写回不得改写旁车"
    );
}

#[tokio::test]
async fn 保留标记_r2_两批读取保存_spoc_材料() {
    let fixture = Fixture::in_task("session_only_login");
    let transport = Transport::default();
    let bridge = restored(fixture.1.clone(), "direct", &transport).await;
    bridge
        .bind_shared_account(&shared_guard(&fixture, 1, true), None)
        .await
        .unwrap();
    for _ in 0..2 {
        bridge.spoc_assignments().await.unwrap();
    }
    assert_eq!(transport.calls.spoc_logins.load(SeqCst), 1);
    drop(bridge);
    assert!(fixture.contents().contains(SPOC_OLD));
}

#[tokio::test]
async fn 保留标记_r4_过期退出票据与恢复旧归属不改变旁车() {
    let fixture = Fixture::in_task("session_only_login");
    let transport = Transport::default();
    let bridge = restored(fixture.1.clone(), "direct", &transport).await;
    bridge.spoc_assignments().await.unwrap();
    drop(bridge);
    let before = std::fs::read(fixture.cache()).unwrap();

    let original = shared_guard(&fixture, 1, false);
    let expired = shared_guard(&fixture, 2, false);
    let bridge = restored(fixture.1.clone(), "direct", &transport).await;
    bridge.bind_shared_account(&original, None).await.unwrap();
    assert!(bridge.logout_with_shared_account(&expired).await.is_err());
    let inner = bridge.inner.lock().await;
    let restored = inner.as_ref().unwrap().shared_account_guard().unwrap();
    restored.check().unwrap();
    assert!(!restored.retains_session());
    assert!(
        std::fs::read(fixture.cache()).unwrap() == before,
        "绑定和恢复不得改写旁车"
    );
}
