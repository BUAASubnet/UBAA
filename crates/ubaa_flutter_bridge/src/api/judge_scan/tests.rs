//! 合成传输证明批次之间客户端锁可用，且写意图不会被扫描清理。
use super::*;
use crate::api::client::{BridgeConnectionMode, BridgeErrorCode};
use crate::api::recovery::BridgeRecoveryFeature;
use crate::api::write::{BridgeBykcCourseRequest, PendingEntry, PendingWrite};
use ubaa_test_support::{
    ExpectedRequest, FileSessionStore, GatewayProbe, HttpMethod, HttpResponse, MockTransport,
    RouteConfig, SessionSnapshot, SessionStore,
};

struct NoProbe;
impl GatewayProbe for NoProbe {
    fn probe(&self, _: std::time::Duration) -> core::NetworkState {
        panic!("固定路线不应探测");
    }
}
fn status() -> ExpectedRequest {
    let url = "https://uc.buaa.edu.cn/api/uc/status";
    get(
        url,
        include_bytes!("../../../../../fixtures/auth/userinfo-success.json").to_vec(),
    )
}
fn get(url: &str, body: Vec<u8>) -> ExpectedRequest {
    ExpectedRequest::new(HttpMethod::Get, url, HttpResponse::new(200, url, body))
}
fn activation() -> ExpectedRequest {
    let url = "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fjudge.buaa.edu.cn%2F";
    let mut response = HttpResponse::new(302, url, Vec::new());
    response
        .headers
        .insert("Location".into(), vec!["https://judge.buaa.edu.cn/".into()]);
    ExpectedRequest::new(HttpMethod::Get, url, response)
}
#[tokio::test]
async fn batches_release_client_lock_and_protect_pending_writes() {
    let root = std::env::temp_dir().join(format!("ubaa-judge-bridge-scan-{}", std::process::id()));
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
        activation(),
        get("https://judge.buaa.edu.cn/", b"<html>ready</html>".to_vec()),
        get(
            "https://judge.buaa.edu.cn/courselist.jsp?courseID=0",
            b"<a href='courselist.jsp?courseID=12'>Course A</a>".to_vec(),
        ),
        status(),
        get(
            "https://judge.buaa.edu.cn/courselist.jsp?courseID=12",
            b"ready".to_vec(),
        ),
        get(
            "https://judge.buaa.edu.cn/assignment/index.jsp",
            b"<a href='assignment/index.jsp?assignID=101'>Task A</a>".to_vec(),
        ),
    ]);
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
    let scan = bridge.begin_judge_scan(&cache, false, None).await.unwrap();
    assert_eq!(scan.courses().await.len(), 1);
    // 扫描尚未消费任何作业时，另一个真实 Bridge 调用可获得同一共享锁并完成。
    tokio::time::timeout(
        std::time::Duration::from_secs(1),
        bridge.recover_required_session(BridgeRecoveryFeature::Schedule),
    )
    .await
    .unwrap()
    .unwrap();
    let batch = bridge.next_judge_scan(&scan).await.unwrap();
    assert_eq!(batch.kind, BridgeJudgeScanKind::Assignments);
    assert_eq!(batch.assignments.len(), 1);
    assert!(!batch.finished);
    transport.assert_exhausted().unwrap();
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
        bridge.next_judge_scan(&scan).await.unwrap_err().code,
        BridgeErrorCode::OperationConflict
    );
    assert_eq!(bridge.write_intents.lock().await.len(), 1);
    bridge.write_intents.lock().await.clear();
    scan.cancel();
    assert_eq!(
        bridge.next_judge_scan(&scan).await.unwrap_err().code,
        BridgeErrorCode::OperationConflict
    );
    assert_eq!(transport.requests().unwrap().len(), before);
    bridge.dispose().await.unwrap();
    assert_eq!(
        bridge.next_judge_scan(&scan).await.unwrap_err().code,
        BridgeErrorCode::ClientDisposed
    );
    drop(cache);
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn persistent_refresh_delivers_index_then_saved_summary_through_bridge() {
    use crate::api::judge_refresh::BridgeJudgeRefreshOptions;
    let root =
        std::env::temp_dir().join(format!("ubaa-judge-bridge-refresh-{}", std::process::id()));
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
        activation(),
        get("https://judge.buaa.edu.cn/", b"<html>ready</html>".to_vec()),
        get(
            "https://judge.buaa.edu.cn/courselist.jsp?courseID=0",
            b"<a href='courselist.jsp?courseID=12'>Course A</a>".to_vec(),
        ),
        get(
            "https://judge.buaa.edu.cn/courselist.jsp?courseID=12",
            b"ready".to_vec(),
        ),
        get(
            "https://judge.buaa.edu.cn/assignment/index.jsp",
            b"<a href='assignment/index.jsp?assignID=101'>Task A</a>".to_vec(),
        ),
        get(
            "https://judge.buaa.edu.cn/assignment/index.jsp?assignID=101",
            include_bytes!("../../../../../fixtures/readonly/judge-detail.html").to_vec(),
        ),
    ]);
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
    let task = bridge
        .begin_judge_refresh(&cache, BridgeJudgeRefreshOptions::default())
        .await
        .unwrap();
    let index = bridge.next_judge_refresh(&task).await.unwrap();
    assert_eq!(index.batch.kind, BridgeJudgeScanKind::Assignments);
    assert!(!index.batch.finished);
    assert!(index.summaries.is_empty());
    let detail = bridge.next_judge_refresh(&task).await.unwrap();
    assert!(detail.batch.finished && detail.batch.complete);
    assert_eq!(detail.summaries.len(), 1);
    assert!(detail.save_error.is_none());
    transport.assert_exhausted().unwrap();
    let saved = cache
        .read_judge(BridgeConnectionMode::Direct, false)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        saved.data[0].assignment_id,
        detail.summaries[0].assignment_id
    );
    assert_eq!(saved.fetched_at, detail.summary_fetched_at);
    task.cancel();
    bridge.dispose().await.unwrap();
    drop(cache);
    let _ = std::fs::remove_dir_all(root);
}

#[path = "tests/details.rs"]
mod details;
#[path = "tests/online.rs"]
mod online;
