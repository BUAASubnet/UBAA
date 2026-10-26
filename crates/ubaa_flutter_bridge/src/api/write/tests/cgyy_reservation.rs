use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use ubaa_core::facade::testing::{HttpRequest, HttpResponse, HttpTransport};
use ubaa_core::facade::{ErrorCode, ErrorKind, Result, UbaaError};

use super::*;
use crate::api::write::{
    BridgeCgyyReservationSelection, BridgeCgyySubmitReservationRequest, BridgeWriteOperation,
};

const SITE_ID: i32 = 4;
const RESERVATION_DATE: &str = "2026-09-05";
const SPACE_ID: i32 = 6;
const GROUP_ID: i32 = 9;
const TIME_ID: i32 = 101;

#[tokio::test]
async fn 场馆预约准备通过_core_fresh_target_签发安全意图() {
    let root = test_root("prepare-cgyy-reservation");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = CgyyTransport::new([day_body(1)]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;

    let intent = client
        .prepare_cgyy_submit_reservation(request())
        .await
        .expect("明确允许的 fresh target 应签发意图");

    assert!(matches!(
        intent.operation,
        BridgeWriteOperation::CgyySubmitReservation
    ));
    assert_eq!(intent.resolved_route, BridgeConnectionMode::Direct);
    for expected in ["4", RESERVATION_DATE, "6", "101"] {
        assert!(
            intent.target_summary.contains(expected),
            "安全摘要缺少权威目标字段 {expected}"
        );
    }
    for forbidden in ["010-00000000", "脱敏主题", "脱敏参与者", "脱敏内容"] {
        assert!(!intent.target_summary.contains(forbidden));
    }
    assert_eq!(
        direct.path_count("/venue-zhjs-server/api/reservation/day/info"),
        1
    );
    assert_eq!(direct.write_phase_count(), 0);
    assert_eq!(client.write_intents.lock().await.len(), 1);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 场馆预约准备清理权威日期中的双向控制字符() {
    let root = test_root("prepare-cgyy-safe-date-summary");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let unsafe_date = format!("{RESERVATION_DATE}\u{202e}欺骗");
    let direct = CgyyTransport::new([day_body_for_date(&unsafe_date, 1)]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;
    let mut unsafe_request = request();
    unsafe_request.reservation_date = unsafe_date;

    let intent = client
        .prepare_cgyy_submit_reservation(unsafe_request)
        .await
        .expect("权威日期可用于定位但确认摘要必须清理");

    assert!(intent.target_summary.contains(RESERVATION_DATE));
    assert!(!intent.target_summary.contains('\u{202e}'));
    assert!(!intent.target_summary.chars().any(char::is_control));
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 场馆预约准备拒绝非_allowed_target_且不保存意图() {
    let root = test_root("prepare-cgyy-denied");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = CgyyTransport::new([day_body(2)]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;

    let error = client
        .prepare_cgyy_submit_reservation(request())
        .await
        .expect_err("非 Allowed target 不得签发意图");

    assert_eq!(error.code, BridgeErrorCode::OperationConflict);
    assert!(error.retryable);
    assert!(client.write_intents.lock().await.is_empty());
    assert_eq!(direct.write_phase_count(), 0);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 场馆预约提交前资格漂移会消费意图且不发送写请求() {
    let root = test_root("commit-cgyy-drift");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = CgyyTransport::new([day_body(1), day_body(2)]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;
    let intent = client
        .prepare_cgyy_submit_reservation(request())
        .await
        .expect("准备场馆预约");

    let error = client
        .commit_write(intent.intent_id.clone())
        .await
        .expect_err("commit 必须重新读取 fresh authority");

    assert_eq!(error.code, BridgeErrorCode::OperationConflict);
    assert!(error.retryable);
    assert_eq!(
        direct.path_count("/venue-zhjs-server/api/reservation/day/info"),
        2
    );
    assert_eq!(direct.write_phase_count(), 0);
    let reused = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("资格漂移后 intent 已消费");
    assert_eq!(reused.code, BridgeErrorCode::IntentExpired);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 场馆预约准备规范化同一目标并拒绝第二个待确认意图() {
    let root = test_root("prepare-cgyy-canonical-conflict");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = CgyyTransport::new([day_body(1), day_body(1)]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;

    client
        .prepare_cgyy_submit_reservation(request())
        .await
        .expect("准备首个场馆预约意图");
    let mut equivalent = request();
    equivalent.reservation_date = format!("  {RESERVATION_DATE}  ");
    equivalent.phone = " 010-00000000 ".into();
    equivalent.theme = " 脱敏主题 ".into();
    equivalent.activity_content = " 脱敏内容 ".into();
    equivalent.joiners = " 脱敏参与者 ".into();

    let conflict = client
        .prepare_cgyy_submit_reservation(equivalent)
        .await
        .expect_err("规范化后相同目标不能保存第二个待确认意图");

    assert_eq!(conflict.code, BridgeErrorCode::OperationConflict);
    assert_eq!(client.write_intents.lock().await.len(), 1);
    assert_eq!(
        direct.path_count("/venue-zhjs-server/api/reservation/day/info"),
        2
    );
    assert_eq!(direct.write_phase_count(), 0);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 场馆预约准备拒绝与待确认意图重叠的时段集合() {
    let root = test_root("prepare-cgyy-overlapping-conflict");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = CgyyTransport::new([two_slot_day_body(), two_slot_day_body()]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;

    client
        .prepare_cgyy_submit_reservation(request())
        .await
        .expect("准备单时段场馆预约意图");
    let mut overlapping = request();
    overlapping.selections.push(BridgeCgyyReservationSelection {
        space_id: SPACE_ID,
        time_id: 102,
        venue_space_group_id: Some(GROUP_ID),
    });

    let conflict = client
        .prepare_cgyy_submit_reservation(overlapping)
        .await
        .expect_err("含已待确认时段的目标集合必须冲突");

    assert_eq!(conflict.code, BridgeErrorCode::OperationConflict);
    assert_eq!(client.write_intents.lock().await.len(), 1);
    assert_eq!(direct.write_phase_count(), 0);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

fn request() -> BridgeCgyySubmitReservationRequest {
    BridgeCgyySubmitReservationRequest {
        venue_site_id: SITE_ID,
        reservation_date: RESERVATION_DATE.into(),
        selections: vec![BridgeCgyyReservationSelection {
            space_id: SPACE_ID,
            time_id: TIME_ID,
            venue_space_group_id: Some(GROUP_ID),
        }],
        phone: "010-00000000".into(),
        theme: "脱敏主题".into(),
        purpose_type: 1,
        joiner_num: 1,
        activity_content: "脱敏内容".into(),
        joiners: "脱敏参与者".into(),
        is_philosophy_social_sciences: false,
        is_off_school_joiner: false,
    }
}

fn day_body(status: i32) -> String {
    day_body_for_date(RESERVATION_DATE, status)
}

fn day_body_for_date(reservation_date: &str, status: i32) -> String {
    format!(
        r#"{{"code":200,"data":{{"token":"reservation-fixture","reservationDateList":["{reservation_date}"],"spaceTimeInfo":[{{"id":{TIME_ID},"beginTime":"08:00","endTime":"09:00"}}],"reservationDateSpaceInfo":{{"{reservation_date}":[{{"id":{SPACE_ID},"spaceName":"脱敏空间","venueSiteId":{SITE_ID},"venueSpaceGroupId":{GROUP_ID},"{TIME_ID}":{{"reservationStatus":{status},"tradeNo":null,"orderId":null,"takeUp":false}}}}]}}}}}}"#
    )
}

fn two_slot_day_body() -> String {
    format!(
        r#"{{"code":200,"data":{{"token":"reservation-fixture","reservationDateList":["{RESERVATION_DATE}"],"spaceTimeInfo":[{{"id":{TIME_ID},"beginTime":"08:00","endTime":"09:00"}},{{"id":102,"beginTime":"09:00","endTime":"10:00"}}],"reservationDateSpaceInfo":{{"{RESERVATION_DATE}":[{{"id":{SPACE_ID},"spaceName":"脱敏空间","venueSiteId":{SITE_ID},"venueSpaceGroupId":{GROUP_ID},"{TIME_ID}":{{"reservationStatus":1,"tradeNo":null,"orderId":null,"takeUp":false}},"102":{{"reservationStatus":1,"tradeNo":null,"orderId":null,"takeUp":false}}}}]}}}}}}"#
    )
}

#[derive(Clone)]
struct CgyyTransport {
    state: Arc<Mutex<CgyyState>>,
}

struct CgyyState {
    days: VecDeque<String>,
    requests: Vec<HttpRequest>,
}

impl CgyyTransport {
    fn new(days: impl IntoIterator<Item = String>) -> Self {
        Self {
            state: Arc::new(Mutex::new(CgyyState {
                days: days.into_iter().collect(),
                requests: Vec::new(),
            })),
        }
    }

    fn path_count(&self, expected: &str) -> usize {
        self.state
            .lock()
            .expect("锁定场馆 bridge 场景")
            .requests
            .iter()
            .filter(|request| request_path(request) == expected)
            .count()
    }

    fn write_phase_count(&self) -> usize {
        [
            "/venue-zhjs-server/api/reservation/order/info",
            "/venue-zhjs-server/api/captcha/get",
            "/venue-zhjs-server/api/captcha/check",
            "/venue-zhjs-server/api/reservation/order/submit",
        ]
        .into_iter()
        .map(|path| self.path_count(path))
        .sum()
    }
}

#[async_trait]
impl HttpTransport for CgyyTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let path = request_path(&request);
        let mut state = self.state.lock().expect("锁定场馆 bridge 场景");
        state.requests.push(request.clone());
        match path {
            "/venue-zhjs-server/sso/manageLogin" => {
                let mut response = HttpResponse::new(200, request.url, Vec::new());
                response.headers.insert(
                    "Set-Cookie".into(),
                    vec!["sso_buaa_zhjs_token=sso-fixture; Path=/".into()],
                );
                Ok(response)
            }
            "/venue-zhjs-server/api/login" => Ok(HttpResponse::new(
                200,
                request.url,
                br#"{"code":200,"data":{"token":{"access_token":"access-fixture"}}}"#.to_vec(),
            )),
            "/venue-zhjs-server/api/reservation/day/info" => {
                let body = state.days.pop_front().ok_or_else(|| {
                    UbaaError::new(
                        ErrorCode::InternalError,
                        ErrorKind::Internal,
                        false,
                        "缺少脱敏场馆日期响应",
                    )
                })?;
                Ok(HttpResponse::new(200, request.url, body.into_bytes()))
            }
            _ => Err(UbaaError::new(
                ErrorCode::InternalError,
                ErrorKind::Internal,
                false,
                "未预期的脱敏场馆 bridge 请求",
            )),
        }
    }
}

fn request_path(request: &HttpRequest) -> &str {
    request
        .url
        .split_once('?')
        .map_or(request.url.as_str(), |(path, _)| path)
        .strip_prefix("https://cgyy.buaa.edu.cn")
        .unwrap_or_default()
}
