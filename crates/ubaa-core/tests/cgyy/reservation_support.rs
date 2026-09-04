use std::collections::VecDeque;
use std::io::Cursor;
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use base64::Engine;
use image::{DynamicImage, ImageFormat, Rgba, RgbaImage};
use serde_json::{Map, Value, json};
use ubaa_core::facade::testing::{
    FileSessionStore, HttpRequest, HttpResponse, HttpTransport, SessionSnapshot, SessionStore,
};
use ubaa_core::facade::{
    CgyyReservationSelection, CgyyReservationSubmitRequest, ConnectionMode, ErrorCode, ErrorKind,
    Result, RouteClient, UbaaError,
};

pub(super) const SITE_ID: i32 = 4;
pub(super) const RESERVATION_DATE: &str = "2026-09-05";
pub(super) const OTHER_DATE: &str = "2026-09-06";
pub(super) const SPACE_ID: i32 = 6;
pub(super) const OTHER_SPACE_ID: i32 = 7;
pub(super) const GROUP_ID: i32 = 9;
pub(super) const FIRST_TIME_ID: i32 = 101;
pub(super) const SECOND_TIME_ID: i32 = 305;
pub(super) const THIRD_TIME_ID: i32 = 999;

#[derive(Clone)]
pub(super) struct Scenario {
    state: Arc<Mutex<State>>,
}

struct State {
    requests: Vec<HttpRequest>,
    day_bodies: VecDeque<String>,
    captcha_checks: VecDeque<bool>,
    submit: Submit,
    captcha_challenge: String,
}

#[derive(Clone)]
pub(super) enum Submit {
    Response(u16, String),
    FinalUrl(&'static str, String),
    TransportError,
}

impl Scenario {
    pub(super) fn new(day_bodies: impl IntoIterator<Item = String>) -> Self {
        Self {
            state: Arc::new(Mutex::new(State {
                requests: Vec::new(),
                day_bodies: day_bodies.into_iter().collect(),
                captcha_checks: [true].into_iter().collect(),
                submit: Submit::Response(
                    200,
                    r#"{"code":200,"message":"预约成功","data":{"orderInfo":{"id":88}}}"#.into(),
                ),
                captcha_challenge: captcha_challenge(),
            })),
        }
    }

    pub(super) fn with_submit(self, submit: Submit) -> Self {
        self.state.lock().expect("锁定场馆场景").submit = submit;
        self
    }

    pub(super) fn with_captcha_checks(self, outcomes: impl IntoIterator<Item = bool>) -> Self {
        self.state.lock().expect("锁定场馆场景").captcha_checks = outcomes.into_iter().collect();
        self
    }

    pub(super) fn requests(&self) -> Vec<HttpRequest> {
        self.state.lock().expect("锁定场馆场景").requests.clone()
    }

    pub(super) fn path_count(&self, expected: &str) -> usize {
        self.requests()
            .iter()
            .filter(|request| request_path(request) == expected)
            .count()
    }

    pub(super) fn write_phase_count(&self) -> usize {
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
impl HttpTransport for Scenario {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let path = request_path(&request);
        let mut state = self.state.lock().expect("锁定场馆场景");
        state.requests.push(request.clone());
        match path.as_str() {
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
                let body = state
                    .day_bodies
                    .pop_front()
                    .ok_or_else(|| test_error(ErrorCode::InternalError, "缺少场馆日期响应"))?;
                Ok(HttpResponse::new(200, request.url, body.into_bytes()))
            }
            "/venue-zhjs-server/api/reservation/order/info" => Ok(HttpResponse::new(
                200,
                request.url,
                br#"{"code":200,"data":{}}"#.to_vec(),
            )),
            "/venue-zhjs-server/api/captcha/get" => Ok(HttpResponse::new(
                200,
                request.url,
                state.captcha_challenge.as_bytes().to_vec(),
            )),
            "/venue-zhjs-server/api/captcha/check" => {
                let success = state.captcha_checks.pop_front().unwrap_or(true);
                Ok(HttpResponse::new(
                    200,
                    request.url,
                    json!({"code": 200, "data": {"success": success}})
                        .to_string()
                        .into_bytes(),
                ))
            }
            "/venue-zhjs-server/api/reservation/order/submit" => match state.submit.clone() {
                Submit::Response(status, body) => {
                    Ok(HttpResponse::new(status, request.url, body.into_bytes()))
                }
                Submit::FinalUrl(final_url, body) => {
                    Ok(HttpResponse::new(200, final_url, body.into_bytes()))
                }
                Submit::TransportError => Err(test_error(
                    ErrorCode::NetworkError,
                    "脱敏场馆预约发送后网络失败",
                )),
            },
            _ => Err(test_error(
                ErrorCode::InternalError,
                "未预期的场馆预约测试路径",
            )),
        }
    }
}

pub(super) fn client_for(name: &str, scenario: Scenario) -> (RouteClient, std::path::PathBuf) {
    let root = std::env::temp_dir().join(format!(
        "ubaa-cgyy-reservation-authority-{name}-{}-{:?}",
        std::process::id(),
        std::thread::current().id(),
    ));
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).expect("创建场馆测试会话存储");
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: Vec::new(),
            authenticated_at: 1_000,
            last_activity: 1_001,
        })
        .expect("写入脱敏场馆测试会话");
    let client = RouteClient::with_transport(ConnectionMode::Direct, scenario, store)
        .expect("创建场馆测试客户端");
    (client, root)
}

pub(super) fn runtime() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("创建场馆测试 runtime")
}

pub(super) fn cleanup(root: std::path::PathBuf) {
    let _ = std::fs::remove_dir_all(root);
}

pub(super) fn selection(
    space_id: i32,
    time_id: i32,
    group_id: Option<i32>,
) -> CgyyReservationSelection {
    CgyyReservationSelection {
        space_id,
        time_id,
        venue_space_group_id: group_id,
    }
}

pub(super) fn reservation_request(
    selections: Vec<CgyyReservationSelection>,
) -> CgyyReservationSubmitRequest {
    let mut request = CgyyReservationSubmitRequest::default();
    request.venue_site_id = SITE_ID;
    request.reservation_date = RESERVATION_DATE.into();
    request.selections = selections;
    request.phone = "010-00000000".into();
    request.theme = "脱敏测试预约".into();
    request.purpose_type = 1;
    request.joiner_num = 1;
    request.activity_content = "脱敏测试内容".into();
    request.joiners = "脱敏测试人员".into();
    request.is_philosophy_social_sciences = false;
    request.is_off_school_joiner = false;
    request
}

pub(super) fn external_captcha_request(
    selections: Vec<CgyyReservationSelection>,
) -> CgyyReservationSubmitRequest {
    reservation_request(selections).with_captcha_material(
        "verification-fixture",
        "point-fixture",
        "captcha-fixture",
    )
}

pub(super) fn standard_spaces(slot: Value) -> Vec<Value> {
    vec![space(
        SPACE_ID,
        SITE_ID,
        Some(GROUP_ID),
        [(FIRST_TIME_ID, slot)],
    )]
}

pub(super) fn space(
    space_id: i32,
    site_id: i32,
    group_id: Option<i32>,
    slots: impl IntoIterator<Item = (i32, Value)>,
) -> Value {
    let mut object = Map::new();
    object.insert("id".into(), json!(space_id));
    object.insert("spaceName".into(), json!(format!("脱敏空间-{space_id}")));
    object.insert("venueSiteId".into(), json!(site_id));
    object.insert("venueSpaceGroupId".into(), json!(group_id));
    for (time_id, slot) in slots {
        object.insert(time_id.to_string(), slot);
    }
    Value::Object(object)
}

pub(super) fn allowed_slot() -> Value {
    json!({
        "reservationStatus": 1,
        "tradeNo": null,
        "orderId": null,
        "takeUp": false,
        "startDate": "2026-09-05 08:00:00",
        "endDate": "2026-09-05 09:00:00"
    })
}

pub(super) fn denied_slot() -> Value {
    json!({
        "reservationStatus": 2,
        "tradeNo": null,
        "orderId": null,
        "takeUp": false
    })
}

pub(super) fn day_body(date: &str, spaces: Vec<Value>) -> String {
    day_body_with_time_slots(
        date,
        vec![
            json!({"id": FIRST_TIME_ID, "beginTime": "08:00", "endTime": "09:00"}),
            json!({"id": SECOND_TIME_ID, "beginTime": "09:30", "endTime": "10:30"}),
            json!({"id": THIRD_TIME_ID, "beginTime": "14:00", "endTime": "15:00"}),
        ],
        spaces,
    )
}

pub(super) fn day_body_with_time_slots(
    date: &str,
    time_slots: Vec<Value>,
    spaces: Vec<Value>,
) -> String {
    let mut dates = Map::new();
    dates.insert(date.into(), Value::Array(spaces));
    let time_slots = Value::Array(time_slots);
    json!({
        "code": 200,
        "data": {
            "token": "reservation-fixture",
            "reservationDateList": [RESERVATION_DATE, OTHER_DATE],
            "spaceTimeInfo": time_slots,
            "reservationDateSpaceInfo": dates
        }
    })
    .to_string()
}

pub(super) fn request_path(request: &HttpRequest) -> String {
    url::Url::parse(&request.url)
        .expect("场馆请求 URL 有效")
        .path()
        .to_owned()
}

fn captcha_challenge() -> String {
    let mut background = RgbaImage::from_pixel(64, 32, Rgba([255, 255, 255, 255]));
    let mut piece = RgbaImage::from_pixel(12, 12, Rgba([255, 255, 255, 0]));
    for y in 0..12 {
        for x in 0..12 {
            if x == 0 || y == 0 || x == 11 || y == 11 {
                piece.put_pixel(x, y, Rgba([0, 0, 0, 255]));
                background.put_pixel(30 + x, 10 + y, Rgba([0, 0, 0, 255]));
            }
        }
    }
    json!({
        "code": 200,
        "data": {
            "success": true,
            "repData": {
                "secretKey": "0123456789abcdef",
                "token": "captcha-challenge-fixture",
                "originalImageBase64": encode_png(background),
                "jigsawImageBase64": encode_png(piece)
            }
        }
    })
    .to_string()
}

fn encode_png(image: RgbaImage) -> String {
    let mut bytes = Vec::new();
    DynamicImage::ImageRgba8(image)
        .write_to(&mut Cursor::new(&mut bytes), ImageFormat::Png)
        .expect("编码脱敏验证码图片");
    base64::engine::general_purpose::STANDARD.encode(bytes)
}

fn test_error(code: ErrorCode, message: &'static str) -> UbaaError {
    let kind = if code == ErrorCode::NetworkError {
        ErrorKind::Network
    } else {
        ErrorKind::Internal
    };
    UbaaError::new(code, kind, false, message)
}
