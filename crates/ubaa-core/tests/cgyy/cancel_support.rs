use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use std::time::{Duration, UNIX_EPOCH};

use async_trait::async_trait;
use chrono::DateTime;
use ubaa_core::facade::testing::{
    FileSessionStore, HttpRequest, HttpResponse, HttpTransport, SessionSnapshot, SessionStore,
    from_webvpn_url,
};
use ubaa_core::facade::{
    CgyyCancelOrderRequest, ConnectionMode, ErrorCode, ErrorKind, Result, RouteClient, UbaaError,
};

pub(super) const ORDER_ID: i32 = 77;
pub(super) const DETAIL_PATH: &str = "/venue-zhjs-server/api/orders/77";
pub(super) const CANCEL_PATH: &str = "/venue-zhjs-server/api/orders/new/cancel/77";
pub(super) const FIXED_NOW: &str = "2026-04-04T06:30:00Z";

#[derive(Clone)]
pub(super) struct Scenario {
    state: Arc<Mutex<State>>,
}

struct State {
    requests: Vec<HttpRequest>,
    details: VecDeque<DetailReply>,
    cancel: CancelReply,
}

#[derive(Clone)]
pub(super) enum DetailReply {
    Response(u16, String),
    TransportError,
}

#[derive(Clone)]
pub(super) enum CancelReply {
    Response(u16, String),
    FinalUrl(&'static str, String),
    InvalidCookie(String),
    TransportError,
}

impl Scenario {
    pub(super) fn new(details: impl IntoIterator<Item = String>) -> Self {
        Self {
            state: Arc::new(Mutex::new(State {
                requests: Vec::new(),
                details: details
                    .into_iter()
                    .map(|body| DetailReply::Response(200, body))
                    .collect(),
                cancel: CancelReply::Response(
                    200,
                    r#"{"code":200,"message":"取消成功","data":null}"#.into(),
                ),
            })),
        }
    }

    pub(super) fn with_detail_replies(details: impl IntoIterator<Item = DetailReply>) -> Self {
        Self {
            state: Arc::new(Mutex::new(State {
                requests: Vec::new(),
                details: details.into_iter().collect(),
                cancel: CancelReply::Response(
                    200,
                    r#"{"code":200,"message":"取消成功","data":null}"#.into(),
                ),
            })),
        }
    }

    pub(super) fn with_cancel(self, cancel: CancelReply) -> Self {
        self.state.lock().expect("锁定场馆取消场景").cancel = cancel;
        self
    }

    pub(super) fn requests(&self) -> Vec<HttpRequest> {
        self.state
            .lock()
            .expect("锁定场馆取消场景")
            .requests
            .clone()
    }

    pub(super) fn path_count(&self, expected: &str) -> usize {
        self.requests()
            .iter()
            .filter(|request| request_path(request) == expected)
            .count()
    }

    pub(super) fn detail_count(&self) -> usize {
        self.path_count(DETAIL_PATH)
    }

    pub(super) fn cancel_count(&self) -> usize {
        self.path_count(CANCEL_PATH)
    }

    pub(super) fn login_count(&self) -> usize {
        self.path_count("/venue-zhjs-server/api/login")
    }
}

#[async_trait]
impl HttpTransport for Scenario {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let path = request_path(&request);
        let mut state = self.state.lock().expect("锁定场馆取消场景");
        state.requests.push(request.clone());
        match path.as_str() {
            "/venue-zhjs-server/sso/manageLogin" => {
                let mut response = HttpResponse::new(200, request.url, Vec::new());
                response.headers.insert(
                    "Set-Cookie".into(),
                    vec!["sso_buaa_zhjs_token=sso-cancel-fixture; Path=/".into()],
                );
                Ok(response)
            }
            "/venue-zhjs-server/api/login" => Ok(HttpResponse::new(
                200,
                request.url,
                br#"{"code":200,"data":{"token":{"access_token":"cancel-access-fixture"}}}"#
                    .to_vec(),
            )),
            DETAIL_PATH => match state.details.pop_front().unwrap_or_else(|| {
                DetailReply::Response(200, detail_response(&allowed_order_row()))
            }) {
                DetailReply::Response(status, body) => {
                    Ok(HttpResponse::new(status, request.url, body.into_bytes()))
                }
                DetailReply::TransportError => {
                    Err(test_error(ErrorCode::NetworkError, "脱敏场馆详情读取失败"))
                }
            },
            CANCEL_PATH => match state.cancel.clone() {
                CancelReply::Response(status, body) => {
                    Ok(HttpResponse::new(status, request.url, body.into_bytes()))
                }
                CancelReply::FinalUrl(final_url, body) => {
                    Ok(HttpResponse::new(200, final_url, body.into_bytes()))
                }
                CancelReply::InvalidCookie(body) => {
                    let mut response = HttpResponse::new(200, request.url, body.into_bytes());
                    response
                        .headers
                        .insert("Set-Cookie".into(), vec!["invalid-cookie".into()]);
                    Ok(response)
                }
                CancelReply::TransportError => Err(test_error(
                    ErrorCode::NetworkError,
                    "脱敏场馆取消发送后网络失败",
                )),
            },
            _ => Err(test_error(
                ErrorCode::InternalError,
                "未预期的场馆取消测试路径",
            )),
        }
    }
}

pub(super) fn request() -> CgyyCancelOrderRequest {
    CgyyCancelOrderRequest { order_id: ORDER_ID }
}

pub(super) fn client_for(name: &str, scenario: Scenario) -> (RouteClient, std::path::PathBuf) {
    client_for_at(name, scenario, FIXED_NOW)
}

pub(super) fn client_for_at(
    name: &str,
    scenario: Scenario,
    now: &str,
) -> (RouteClient, std::path::PathBuf) {
    let root = std::env::temp_dir().join(format!(
        "ubaa-cgyy-cancel-authority-{name}-{}-{:?}",
        std::process::id(),
        std::thread::current().id(),
    ));
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).expect("创建场馆取消测试会话存储");
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: Vec::new(),
            authenticated_at: 1_000,
            last_activity: 1_001,
        })
        .expect("写入脱敏场馆取消测试会话");
    let timestamp = DateTime::parse_from_rfc3339(now)
        .expect("固定时间格式有效")
        .timestamp();
    let fixed_time = UNIX_EPOCH
        .checked_add(Duration::from_secs(
            u64::try_from(timestamp).expect("固定时间晚于 Unix epoch"),
        ))
        .expect("固定时间可表示");
    let client =
        RouteClient::with_transport_at(ConnectionMode::Direct, scenario, store, fixed_time)
            .expect("创建场馆取消测试客户端");
    (client, root)
}

pub(super) fn runtime() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("创建场馆取消测试 runtime")
}

pub(super) fn cleanup(root: std::path::PathBuf) {
    let _ = std::fs::remove_dir_all(root);
}

pub(super) fn allowed_order_row() -> String {
    order_row(
        ORDER_ID.to_string().as_str(),
        "1",
        "1",
        Some("invalid-start"),
        Some("invalid-end"),
    )
}

pub(super) fn order_row(
    id: &str,
    order_status: &str,
    check_status: &str,
    start: Option<&str>,
    end: Option<&str>,
) -> String {
    let mut fields = vec![
        format!(r#""id":{id}"#),
        format!(r#""orderStatus":{order_status}"#),
        format!(r#""checkStatus":{check_status}"#),
        r#""siteName":"脱敏场馆""#.to_owned(),
    ];
    if let Some(start) = start {
        fields.push(format!(
            r#""reservationStartDate":{}"#,
            serde_json::to_string(start).expect("编码脱敏开始时间")
        ));
    }
    if let Some(end) = end {
        fields.push(format!(
            r#""reservationEndDate":{}"#,
            serde_json::to_string(end).expect("编码脱敏结束时间")
        ));
    }
    format!("{{{}}}", fields.join(","))
}

pub(super) fn detail_response(row: &str) -> String {
    format!(r#"{{"code":200,"data":{row}}}"#)
}

pub(super) fn request_path(request: &HttpRequest) -> String {
    let direct = from_webvpn_url(&request.url).unwrap_or_else(|_| request.url.clone());
    url::Url::parse(&direct)
        .expect("场馆请求 URL 有效")
        .path()
        .to_owned()
}

pub(super) fn request_for_path<'a>(requests: &'a [HttpRequest], expected: &str) -> &'a HttpRequest {
    requests
        .iter()
        .find(|request| request_path(request) == expected)
        .expect("应存在指定场馆请求")
}

fn test_error(code: ErrorCode, message: &'static str) -> UbaaError {
    let kind = if code == ErrorCode::NetworkError {
        ErrorKind::Network
    } else {
        ErrorKind::Internal
    };
    UbaaError::new(code, kind, false, message)
}
