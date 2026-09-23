use super::*;
use crate::api::judge_scan::online::BridgeJudgeOnlineOptions;
#[tokio::test]
async fn 无缓存逐批共享锁可让位_意图保护及取消不发出后续请求() {
    let root =
        std::env::temp_dir().join(format!("ubaa-judge-online-bridge-{}", std::process::id()));
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
    let transport = scripted_transport();
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
    let task = bridge
        .begin_judge_online(BridgeJudgeOnlineOptions {
            expected_identity: Some("fixture-user".into()),
            ..BridgeJudgeOnlineOptions::default()
        })
        .await
        .unwrap();
    tokio::time::timeout(
        std::time::Duration::from_secs(1),
        bridge.recover_required_session(BridgeRecoveryFeature::Schedule),
    )
    .await
    .unwrap()
    .unwrap();
    let first = bridge.next_judge_online(&task).await.unwrap();
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
    let count = transport.requests().unwrap().len();
    assert_eq!(
        bridge.next_judge_online(&task).await.unwrap_err().code,
        BridgeErrorCode::OperationConflict
    );
    assert!(
        bridge
            .begin_judge_online(BridgeJudgeOnlineOptions::default())
            .await
            .is_err()
    );
    assert_eq!(bridge.write_intents.lock().await.len(), 1);
    assert_eq!(transport.requests().unwrap().len(), count);
    bridge.write_intents.lock().await.clear();
    let last = bridge.next_judge_online(&task).await.unwrap();
    assert!(last.batch.finished && last.batch.complete);
    assert_eq!(last.summaries.len(), 1);
    let count = transport.requests().unwrap().len();
    task.cancel();
    assert_eq!(
        bridge.next_judge_online(&task).await.unwrap_err().code,
        BridgeErrorCode::OperationConflict
    );
    assert_eq!(transport.requests().unwrap().len(), count);
    bridge.dispose().await.unwrap();
    assert_eq!(
        bridge.next_judge_online(&task).await.unwrap_err().code,
        BridgeErrorCode::ClientDisposed
    );
    std::fs::remove_dir_all(root).unwrap();
}

pub(super) fn scripted_transport() -> MockTransport {
    MockTransport::new([
        status(),
        activation(),
        get("https://judge.buaa.edu.cn/", b"<html>ready</html>".to_vec()),
        get(
            "https://judge.buaa.edu.cn/courselist.jsp?courseID=0",
            b"<a href='courselist.jsp?courseID=12'>Course A</a>".to_vec(),
        ),
        status(),
        activation(),
        get("https://judge.buaa.edu.cn/", b"<html>ready</html>".to_vec()),
        get(
            "https://judge.buaa.edu.cn/courselist.jsp?courseID=12",
            b"ready".to_vec(),
        ),
        get(
            "https://judge.buaa.edu.cn/assignment/index.jsp",
            b"<a href='assignment/index.jsp?assignID=101'>Task A</a>".to_vec(),
        ),
        activation(),
        get("https://judge.buaa.edu.cn/", b"<html>ready</html>".to_vec()),
        get(
            "https://judge.buaa.edu.cn/courselist.jsp?courseID=12",
            b"ready".to_vec(),
        ),
        get(
            "https://judge.buaa.edu.cn/assignment/index.jsp?assignID=101",
            include_bytes!("../../../../../../fixtures/readonly/judge-detail.html").to_vec(),
        ),
    ])
}
