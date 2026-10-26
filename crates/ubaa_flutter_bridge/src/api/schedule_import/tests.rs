use crate::api::client::{BridgeClient, BridgeConnectionMode, BridgeErrorCode};
use crate::api::offline::BridgeOfflineCache;
use crate::api::recovery::BridgeRecoveryFeature;
use crate::api::write::{BridgeBykcCourseRequest, PendingEntry, PendingWrite};
use ubaa_core::facade as core;
use ubaa_test_support::{
    ExpectedRequest, FileSessionStore, GatewayProbe, HttpMethod, HttpResponse, MockTransport,
    RouteConfig, SessionSnapshot, SessionStore,
};
struct NoProbe;
impl GatewayProbe for NoProbe {
    fn probe(&self, _: std::time::Duration) -> core::NetworkState {
        panic!("固定路线不探测");
    }
}
fn get(url: &str, body: Vec<u8>) -> ExpectedRequest {
    ExpectedRequest::new(HttpMethod::Get, url, HttpResponse::new(200, url, body))
}
fn status() -> ExpectedRequest {
    get(
        "https://uc.buaa.edu.cn/api/uc/status",
        include_bytes!("../../../../../fixtures/auth/userinfo-success.json").to_vec(),
    )
}
#[tokio::test]
async fn 导入批次释放共享锁_待确认写意图阻止后续读取且不被清除() {
    let root = std::env::temp_dir().join(format!("ubaa-bridge-import-{}", std::process::id()));
    let bridge = BridgeClient::open(root.to_string_lossy().into()).unwrap();
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save(&SessionSnapshot {
            mode: core::ConnectionMode::Direct,
            cookies: Vec::new(),
            authenticated_at: 1000,
            last_activity: 1001,
        })
        .unwrap();
    let transport = MockTransport::new([
        status(),
        get(
            "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/currentUser.do",
            br#"{"code":"0","datas":{"userId":"synthetic-user"}}"#.to_vec(),
        ),
        get(
            "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/student/schoolCalendars.do",
            include_bytes!("../../../../../fixtures/readonly/schedule-terms.json").to_vec(),
        ),
        status(),
    ]);
    *bridge.inner.lock().await = Some(
        core::UbaaClient::with_routing(
            transport.clone(),
            MockTransport::new([]),
            store,
            RouteConfig::parse("[route]\ndefault=\"direct\"\n").unwrap(),
            NoProbe,
        )
        .unwrap(),
    );
    let cache = BridgeOfflineCache::open(
        root.to_string_lossy().into(),
        "0123456789abcdef0123456789abcdef".into(),
        "fixture-user".into(),
        vec![9; 32],
    )
    .await
    .unwrap();
    let task = bridge
        .begin_schedule_import(&cache, "2025-2026-1".into())
        .await
        .unwrap();
    let value = bridge.next_schedule_import(&task).await.unwrap();
    assert_eq!(value.completed_weeks, 0);
    assert!(!value.finished);
    tokio::time::timeout(
        std::time::Duration::from_secs(1),
        bridge.recover_required_session(BridgeRecoveryFeature::Schedule),
    )
    .await
    .unwrap()
    .unwrap();
    bridge.write_intents.lock().await.insert(
        "synthetic".into(),
        PendingEntry {
            request: PendingWrite::BykcSelect(BridgeBykcCourseRequest { course_id: 1 }),
            expires_at: i64::MAX,
            resolved_route: BridgeConnectionMode::Direct,
            conflict_key: "synthetic".into(),
        },
    );
    let before = transport.requests().unwrap().len();
    assert_eq!(
        bridge.next_schedule_import(&task).await.unwrap_err().code,
        BridgeErrorCode::OperationConflict
    );
    assert_eq!(bridge.write_intents.lock().await.len(), 1);
    assert_eq!(transport.requests().unwrap().len(), before);
    bridge.write_intents.lock().await.clear();
    task.cancel();
    assert_eq!(
        bridge.next_schedule_import(&task).await.unwrap_err().code,
        BridgeErrorCode::OperationConflict
    );
    assert_eq!(transport.requests().unwrap().len(), before);
    bridge.dispose().await.unwrap();
    assert_eq!(
        bridge.next_schedule_import(&task).await.unwrap_err().code,
        BridgeErrorCode::ClientDisposed
    );
    transport.assert_exhausted().unwrap();
    drop((task, cache, bridge));
    std::fs::remove_dir_all(root).unwrap();
}
