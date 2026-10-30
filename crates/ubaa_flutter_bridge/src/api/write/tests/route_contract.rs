//! 十类提交共同的路线合同；业务 authority/正文继续由各领域测试保护。
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use ubaa_core::facade as core;
use ubaa_core::facade::testing::HttpRequest;

use super::*;
use crate::api::write::{
    BridgeCgyyCancelOrderRequest, BridgeLibbookCancelBookingRequest, BridgeLibbookReserveRequest,
    BridgeSigninPerformRequest,
};

#[derive(Clone)]
struct SequenceProbe {
    states: Arc<Mutex<VecDeque<NetworkState>>>,
    calls: Arc<AtomicU64>,
}
impl SequenceProbe {
    fn new(states: impl IntoIterator<Item = NetworkState>) -> Self {
        Self {
            states: Arc::new(Mutex::new(states.into_iter().collect())),
            calls: Arc::new(AtomicU64::new(0)),
        }
    }
}
impl GatewayProbe for SequenceProbe {
    fn probe(&self, _: Duration) -> NetworkState {
        self.calls.fetch_add(1, Ordering::SeqCst);
        self.states
            .lock()
            .unwrap()
            .pop_front()
            .unwrap_or(NetworkState::OffCampus)
    }
}

fn requests() -> Vec<PendingWrite> {
    vec![
        PendingWrite::BykcSelect(BridgeBykcCourseRequest { course_id: 42 }),
        PendingWrite::BykcDeselect(BridgeBykcCourseRequest { course_id: 42 }),
        PendingWrite::BykcSign(BridgeBykcSignCourseRequest {
            course_id: 42,
            lat: Some(39.9),
            lng: Some(116.3),
            sign_type: 1,
        }),
        PendingWrite::Signin(BridgeSigninPerformRequest {
            course_id: "42".into(),
        }),
        PendingWrite::LibbookReserve(BridgeLibbookReserveRequest {
            area_id: "area".into(),
            seat_id: "seat".into(),
            day: "2026-10-07".into(),
            segment: "segment".into(),
            start_time: "08:00".into(),
            end_time: "10:00".into(),
        }),
        PendingWrite::LibbookCancel(BridgeLibbookCancelBookingRequest {
            id: "42".into(),
            page: 1,
            limit: 10,
        }),
        PendingWrite::CgyyReserve(BridgeCgyySubmitReservationRequest {
            venue_site_id: 4,
            reservation_date: "2026-10-07".into(),
            selections: vec![BridgeCgyyReservationSelection {
                space_id: 6,
                time_id: 101,
                venue_space_group_id: Some(9),
            }],
            phone: "010-00000000".into(),
            theme: "合成主题".into(),
            purpose_type: 1,
            joiner_num: 1,
            activity_content: "合成内容".into(),
            joiners: "合成参与者".into(),
            is_philosophy_social_sciences: false,
            is_off_school_joiner: false,
        }),
        PendingWrite::CgyyCancel(BridgeCgyyCancelOrderRequest { order_id: 42 }),
        PendingWrite::Ygdk(core::YgdkClockinSubmitRequest {
            target: core::YgdkSubmitTarget {
                classify_id: 3,
                item_id: 2,
            },
            start_time: "2026-10-07 08:00".into(),
            end_time: "2026-10-07 09:00".into(),
            place: None,
            share_to_square: false,
            photo: core::YgdkPhotoUpload {
                bytes: vec![0xff, 0xd8, 0xff],
                file_name: "fixture.jpg".into(),
                mime_type: "image/jpeg".into(),
            },
        }),
        PendingWrite::Evaluation(core::EvaluationSubmitCoursesRequest {
            targets: vec![core::EvaluationSubmitTarget {
                rwid: "task".into(),
                wjid: "form".into(),
                kcdm: "course".into(),
                bpdm: None,
            }],
        }),
    ]
}

async fn client_with_probe(
    root: &Path,
    direct: impl HttpTransport + 'static,
    webvpn: impl HttpTransport + 'static,
    probe: SequenceProbe,
) -> BridgeClient {
    let store = seed_sessions(root, true, true);
    let core = UbaaClient::with_routing_and_probe_ttl(
        direct,
        webvpn,
        store,
        RouteConfig::default(),
        probe,
        Duration::ZERO,
    )
    .unwrap();
    let bridge = BridgeClient::open(root.to_string_lossy().into_owned()).unwrap();
    *bridge.inner.lock().await = Some(core);
    bridge
}

async fn seed_intent(client: &BridgeClient, request: PendingWrite) {
    client.write_intents.lock().await.insert(
        "fixture-intent".into(),
        PendingEntry {
            request,
            expires_at: i64::MAX,
            resolved_route: BridgeConnectionMode::Direct,
            conflict_key: "fixture-target".into(),
        },
    );
}

#[tokio::test]
async fn 十类写入提交只解析一次路线且不能跨探测窗口转路() {
    let mut failures = Vec::new();
    for request in requests() {
        let operation = request.operation();
        let root = test_root("atomic-route-matrix");
        let direct = MockTransport::new([]);
        let webvpn = MockTransport::new([]);
        let probe = SequenceProbe::new([NetworkState::Campus, NetworkState::OffCampus]);
        let client = client_with_probe(&root, direct.clone(), webvpn.clone(), probe.clone()).await;
        seed_intent(&client, request).await;
        // 第一条 authority 请求就确定性停止；不需要复制十套上游协议来检查共同边界。
        let _ = client.commit_write("fixture-intent".into()).await;
        if probe.calls.load(Ordering::SeqCst) != 1
            || direct.requests().unwrap().len() != 1
            || !webvpn.requests().unwrap().is_empty()
        {
            failures.push(format!("{operation:?}"));
        }
        assert!(client.write_intents.lock().await.is_empty());
        client.dispose().await.unwrap();
        std::fs::remove_dir_all(root).unwrap();
    }
    assert!(failures.is_empty(), "重复解析或越过确认路线：{failures:?}");
}

#[tokio::test]
async fn 十类写入路线变化时在任何业务请求前拒绝且消费意图() {
    for request in requests() {
        let root = test_root("changed-route-matrix");
        let direct = MockTransport::new([]);
        let webvpn = MockTransport::new([]);
        let probe = SequenceProbe::new([NetworkState::OffCampus]);
        let client = client_with_probe(&root, direct.clone(), webvpn.clone(), probe).await;
        seed_intent(&client, request).await;
        let error = client
            .commit_write("fixture-intent".into())
            .await
            .unwrap_err();
        assert_eq!(error.code, BridgeErrorCode::OperationConflict);
        assert!(direct.requests().unwrap().is_empty());
        assert!(webvpn.requests().unwrap().is_empty());
        assert!(client.write_intents.lock().await.is_empty());
        client.dispose().await.unwrap();
        std::fs::remove_dir_all(root).unwrap();
    }
}

#[derive(Clone, Default)]
struct BykcTransport(Arc<AtomicU64>);
#[async_trait]
impl HttpTransport for BykcTransport {
    async fn execute(&self, request: HttpRequest) -> core::Result<HttpResponse> {
        if request.url.contains("/cas/login") {
            return Ok(HttpResponse::new(
                302,
                request
                    .url
                    .replace("/sscv/cas/login", "/cas-login?token=synthetic"),
                Vec::new(),
            ));
        }
        if request.url.contains("queryCourseById") {
            return Ok(HttpResponse::new(200, request.url,
                br#"{"status":"0","data":{"id":42,"courseName":"synthetic","courseStartDate":"2999-01-01 08:00:00","courseSelectStartDate":"2000-01-01 00:00:00","courseSelectEndDate":"2998-12-31 23:59:59","courseMaxCount":10,"courseCurrentCount":0,"selected":false}}"#.to_vec()));
        }
        assert!(request.url.contains("choseCourse"));
        self.0.fetch_add(1, Ordering::SeqCst);
        Ok(HttpResponse::new(
            200,
            request.url,
            br#"{"status":"0","data":{"message":"ok"}}"#.to_vec(),
        ))
    }
}

#[tokio::test]
async fn 博雅选课真实准备提交链不因后续探测变化写到另一条路线() {
    let root = test_root("bykc-atomic-route-regression");
    let direct = BykcTransport::default();
    let webvpn = BykcTransport::default();
    let probe = SequenceProbe::new([
        NetworkState::Campus,
        NetworkState::Campus,
        NetworkState::Campus,
        NetworkState::OffCampus,
    ]);
    let client = client_with_probe(&root, direct.clone(), webvpn.clone(), probe.clone()).await;
    let intent = client
        .prepare_bykc_select_course(BridgeBykcCourseRequest { course_id: 42 })
        .await
        .unwrap();
    let result = client.commit_write(intent.intent_id).await.unwrap();
    assert_eq!(intent.resolved_route, BridgeConnectionMode::Direct);
    assert_eq!(result.resolved_route, Some(BridgeConnectionMode::Direct));
    assert_eq!(direct.0.load(Ordering::SeqCst), 1);
    assert_eq!(webvpn.0.load(Ordering::SeqCst), 0);
    assert_eq!(
        probe.calls.load(Ordering::SeqCst),
        2,
        "prepare/commit 各自仅一次权威解析"
    );
    client.dispose().await.unwrap();
    std::fs::remove_dir_all(root).unwrap();
}
