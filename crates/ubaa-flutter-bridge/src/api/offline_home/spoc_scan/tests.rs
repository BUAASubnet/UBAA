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
fn response(method: HttpMethod, url: &str, body: &str) -> ExpectedRequest {
    ExpectedRequest::new(
        method,
        url,
        HttpResponse::new(200, url, body.as_bytes().to_vec()),
    )
}
fn status() -> ExpectedRequest {
    response(
        HttpMethod::Get,
        "https://uc.buaa.edu.cn/api/uc/status",
        include_str!("../../../../../../fixtures/auth/userinfo-success.json"),
    )
}
fn bootstrap() -> ExpectedRequest {
    let url = "https://spoc.buaa.edu.cn/spocnewht/cas";
    let mut result = HttpResponse::new(302, url, Vec::new());
    result.headers.insert(
        "Location".into(),
        vec!["https://spoc.buaa.edu.cn/spocnew/cas?token=synthetic".into()],
    );
    ExpectedRequest::new(HttpMethod::Get, url, result)
}
fn page(number: u32) -> ExpectedRequest {
    response(
        HttpMethod::Post,
        "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage",
        if number == 1 {
            r#"{"code":200,"content":{"pageNum":1,"pageSize":15,"pages":2,"hasNextPage":true,"list":[{"zyid":"a1","zymc":"合成作业"}]}}"#
        } else {
            r#"{"code":200,"content":{"pageNum":2,"pageSize":15,"pages":2,"hasNextPage":false,"list":[{"zyid":"a2","zymc":"合成作业"}]}}"#
        },
    )
}
async fn setup(
    root: &std::path::Path,
    detail: bool,
) -> (BridgeClient, BridgeOfflineCache, MockTransport) {
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
    let mut expected = vec![
        status(),
        bootstrap(),
        response(
            HttpMethod::Post,
            "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin",
            r#"{"code":200,"content":{"jsdm":"01"}}"#,
        ),
        response(
            HttpMethod::Post,
            "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne",
            r#"{"code":200,"content":{"mrxq":"synthetic-term"}}"#,
        ),
        response(
            HttpMethod::Get,
            "https://spoc.buaa.edu.cn/spocnewht/jxkj/queryKclb?kcmc=&xnxq=synthetic-term",
            r#"{"code":200,"content":[]}"#,
        ),
        page(1),
        status(),
        page(2),
    ];
    if detail {
        expected.extend([
            response(
                HttpMethod::Get,
                "https://spoc.buaa.edu.cn/spocnewht/kczy/queryKczyInfoByid?id=a1",
                include_str!("../../../../../../fixtures/readonly/spoc-detail.json"),
            ),
            response(
                HttpMethod::Get,
                "https://spoc.buaa.edu.cn/spocnewht/kczy/queryXsSubmitKczyInfo?kczyid=a1",
                r#"{"code":200,"content":null}"#,
            ),
        ]);
    }
    let transport = MockTransport::new(expected);
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
        vec![4; 32],
    )
    .await
    .unwrap();
    (bridge, cache, transport)
}
#[tokio::test]
async fn spoc_生产共享锁在页间可用_确认写意图阻止推进_缓存与在线均受取消保护() {
    for persistent in [true, false] {
        let root = std::env::temp_dir().join(format!(
            "ubaa-spoc-bridge-{}-{persistent}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&root);
        let (bridge, cache, transport) = setup(&root, false).await;
        let task = if persistent {
            bridge.begin_spoc_scan(&cache).await.unwrap()
        } else {
            bridge
                .begin_spoc_online(Some("fixture-user".into()))
                .await
                .unwrap()
        };
        for _ in 0..2 {
            assert_eq!(
                bridge.next_spoc_scan(&task).await.unwrap().completed_pages,
                0
            );
        }
        let first = bridge.next_spoc_scan(&task).await.unwrap();
        assert_eq!(first.completed_pages, 1);
        assert!(!first.finished);
        assert!(!first.state.saved_for_offline);
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
            bridge.next_spoc_scan(&task).await.unwrap_err().code,
            BridgeErrorCode::OperationConflict
        );
        assert_eq!(transport.requests().unwrap().len(), before);
        assert_eq!(bridge.write_intents.lock().await.len(), 1);
        bridge.write_intents.lock().await.clear();
        let last = bridge.next_spoc_scan(&task).await.unwrap();
        assert!(last.finished && last.state.complete);
        assert_eq!(last.state.saved_for_offline, persistent);
        assert_eq!(last.result.data.assignments.len(), 2);
        let saved = cache
            .read_home_spoc(BridgeConnectionMode::Direct)
            .await
            .unwrap();
        assert_eq!(saved.is_some(), persistent);
        task.cancel();
        assert_eq!(
            bridge.next_spoc_scan(&task).await.unwrap_err().code,
            BridgeErrorCode::OperationConflict
        );
        bridge.dispose().await.unwrap();
        assert_eq!(
            bridge.next_spoc_scan(&task).await.unwrap_err().code,
            BridgeErrorCode::ClientDisposed
        );
        drop(cache);
        let _ = std::fs::remove_dir_all(root);
    }
}

#[tokio::test]
async fn spoc_详情前置释放共享锁_写意图期间不读取正文_完成后按目标保存() {
    for persistent in [true, false] {
        let root = std::env::temp_dir().join(format!(
            "ubaa-spoc-detail-bridge-{}-{persistent}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&root);
        let (bridge, cache, transport) = setup(&root, true).await;
        let task = if persistent {
            bridge
                .begin_spoc_detail_scan(&cache, "a1".into())
                .await
                .unwrap()
        } else {
            bridge
                .begin_spoc_detail_online(Some("fixture-user".into()), "a1".into())
                .await
                .unwrap()
        };
        for _ in 0..3 {
            let batch = bridge.next_spoc_detail_scan(&task).await.unwrap();
            assert!(batch.result.is_none());
            assert!(!batch.finished);
        }
        tokio::time::timeout(
            std::time::Duration::from_secs(1),
            bridge.recover_required_session(BridgeRecoveryFeature::Schedule),
        )
        .await
        .unwrap()
        .unwrap();
        let indexed = bridge.next_spoc_detail_scan(&task).await.unwrap();
        assert_eq!(indexed.completed_pages, 2);
        assert!(indexed.result.is_none());
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
            bridge.next_spoc_detail_scan(&task).await.unwrap_err().code,
            BridgeErrorCode::OperationConflict
        );
        assert_eq!(transport.requests().unwrap().len(), before);
        bridge.write_intents.lock().await.clear();
        let last = bridge.next_spoc_detail_scan(&task).await.unwrap();
        assert!(last.finished && last.state.complete);
        assert_eq!(last.result.unwrap().data.assignment_id, "a1");
        assert_eq!(last.state.saved_for_offline, persistent);
        assert_eq!(
            cache
                .read_home_spoc_detail(BridgeConnectionMode::Direct, "a1".into())
                .await
                .unwrap()
                .is_some(),
            persistent
        );
        transport.assert_exhausted().unwrap();
        bridge.dispose().await.unwrap();
        drop(cache);
        let _ = std::fs::remove_dir_all(root);
    }
}
