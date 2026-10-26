use super::*;
use crate::api::{
    client::{BridgeConnectionMode, BridgeErrorCode},
    recovery::BridgeRecoveryFeature,
    write::{BridgeBykcCourseRequest, PendingEntry, PendingWrite},
};
use ubaa_test_support::{
    ExpectedRequest, FileSessionStore, GatewayProbe, HttpMethod, HttpResponse, MockTransport,
    RouteConfig, SessionSnapshot, SessionStore,
};
struct NoProbe;
impl GatewayProbe for NoProbe {
    fn probe(&self, _: std::time::Duration) -> core::NetworkState {
        panic!("固定路线不探测")
    }
}
fn get(url: &str, body: &str) -> ExpectedRequest {
    ExpectedRequest::new(
        HttpMethod::Get,
        url,
        HttpResponse::new(200, url, body.as_bytes().to_vec()),
    )
}
fn status() -> ExpectedRequest {
    get(
        "https://uc.buaa.edu.cn/api/uc/status",
        include_str!("../../../../../../fixtures/auth/userinfo-success.json"),
    )
}
async fn setup(root: &std::path::Path) -> (BridgeClient, BridgeOfflineCache, MockTransport) {
    let bridge = BridgeClient::open(root.to_string_lossy().into()).unwrap();
    let store = FileSessionStore::new(root).unwrap();
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
        get("https://spoc.buaa.edu.cn/pjxt/cas", ""),
        get(
            "https://spoc.buaa.edu.cn/pjxt/personnelEvaluation/listObtainPersonnelEvaluationTasks?yhdm=TEST-0001&pageNum=1&pageSize=10",
            r#"{"code":200,"result":{"list":[{"rwid":"rw"}]}}"#,
        ),
        get(
            "https://spoc.buaa.edu.cn/pjxt/evaluationMethodSix/getQuestionnaireListToTask?rwid=rw",
            r#"{"code":200,"result":[{"wjid":"w1","msid":"1"},{"wjid":"w2","msid":"1"}]}"#,
        ),
        get(
            "https://spoc.buaa.edu.cn/pjxt/evaluationMethodSix/getRequiredReviewsData?wjid=w1",
            r#"{"code":200,"result":[{"kcdm":"c1","kcmc":"synthetic-course","bpmc":"synthetic-teacher","ypjcs":1}]}"#,
        ),
        status(),
        get(
            "https://spoc.buaa.edu.cn/pjxt/evaluationMethodSix/getRequiredReviewsData?wjid=w2",
            r#"{"code":200,"result":[{"kcdm":"c2","kcmc":"synthetic-course","bpmc":"synthetic-teacher","ypjcs":0}]}"#,
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
        vec![8; 32],
    )
    .await
    .unwrap();
    (bridge, cache, transport)
}
#[tokio::test]
async fn 评教生产_bridge_课程批次间共享锁可用且写意图阻止推进() {
    for persistent in [true, false] {
        let root = std::env::temp_dir().join(format!(
            "ubaa-evaluation-scan-bridge-{}-{persistent}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&root);
        let (bridge, cache, transport) = setup(&root).await;
        let task = if persistent {
            bridge.begin_evaluation_scan(&cache).await.unwrap()
        } else {
            bridge
                .begin_evaluation_online(Some("fixture-user".into()))
                .await
                .unwrap()
        };
        for step in 0..3 {
            let batch = bridge.next_evaluation_scan(&task).await.unwrap();
            assert_eq!(batch.completed_course_lists, 0);
            assert!(
                !batch.finished,
                "合成读取过早结束：步骤{step}，请求数{}",
                transport.requests().unwrap().len()
            );
        }
        let first = bridge.next_evaluation_scan(&task).await.unwrap();
        assert_eq!(first.refresh.data.courses.len(), 1);
        assert!(!first.finished);
        assert!(first.refresh.data.courses[0].submit_target.is_none());
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
            bridge.next_evaluation_scan(&task).await.unwrap_err().code,
            BridgeErrorCode::OperationConflict
        );
        assert_eq!(transport.requests().unwrap().len(), before);
        assert_eq!(bridge.write_intents.lock().await.len(), 1);
        bridge.write_intents.lock().await.clear();
        let last = bridge.next_evaluation_scan(&task).await.unwrap();
        assert!(last.finished && last.refresh.complete);
        assert_eq!(last.refresh.data.courses.len(), 2);
        assert_eq!(last.refresh.saved_for_offline, persistent);
        assert_eq!(
            cache
                .read_evaluation(BridgeConnectionMode::Direct)
                .await
                .unwrap()
                .is_some(),
            persistent
        );
        transport.assert_exhausted().unwrap();
        task.cancel();
        assert_eq!(
            bridge.next_evaluation_scan(&task).await.unwrap_err().code,
            BridgeErrorCode::OperationConflict
        );
        bridge.dispose().await.unwrap();
        drop(cache);
        let _ = std::fs::remove_dir_all(root);
    }
}
