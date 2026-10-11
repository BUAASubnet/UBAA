use super::*;
use crate::api::read::BridgeJudgeAssignmentKey;

#[tokio::test]
async fn 批量持久详情逐批让位且写意图不被清除_结果可离线读取() {
    let root =
        std::env::temp_dir().join(format!("ubaa-judge-details-bridge-{}", std::process::id()));
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
    let transport = online::scripted_transport();
    *bridge.inner.lock().await = Some(
        core::UbaaClient::with_routing(
            transport.clone(),
            MockTransport::new([]),
            store,
            RouteConfig::parse("[route]\ndefault = \"direct\"\n").unwrap(),
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
    let key = BridgeJudgeAssignmentKey {
        course_id: "12".into(),
        assignment_id: "101".into(),
    };
    let task = bridge
        .begin_judge_details(&cache, vec![key.clone()])
        .await
        .unwrap();
    tokio::time::timeout(
        std::time::Duration::from_secs(1),
        bridge.recover_required_session(BridgeRecoveryFeature::Schedule),
    )
    .await
    .unwrap()
    .unwrap();
    let first = bridge.next_judge_details(&task).await.unwrap();
    assert_eq!(first.batch.kind, BridgeJudgeScanKind::Assignments);
    assert!(!first.batch.finished);
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
        bridge.next_judge_details(&task).await.unwrap_err().code,
        BridgeErrorCode::OperationConflict
    );
    assert!(bridge.begin_judge_details(&cache, vec![key]).await.is_err());
    assert_eq!(bridge.write_intents.lock().await.len(), 1);
    assert_eq!(before, transport.requests().unwrap().len());
    bridge.write_intents.lock().await.clear();
    let last = bridge.next_judge_details(&task).await.unwrap();
    assert!(last.batch.finished && last.batch.complete);
    assert!(last.save_error.is_none());
    transport.assert_exhausted().unwrap();
    assert!(
        cache
            .read_judge_detail(BridgeConnectionMode::Direct, "12".into(), "101".into())
            .await
            .unwrap()
            .is_some()
    );
    task.cancel();
    let before = transport.requests().unwrap().len();
    assert_eq!(
        bridge.next_judge_details(&task).await.unwrap_err().code,
        BridgeErrorCode::OperationConflict
    );
    assert_eq!(before, transport.requests().unwrap().len());
    bridge.dispose().await.unwrap();
    drop((task, cache, bridge));
    std::fs::remove_dir_all(root).unwrap();
}
