use std::collections::HashMap;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use ubaa_core::facade::testing::{
    HttpRequest, HttpResponse, HttpTransport, from_webvpn_url, to_webvpn_url,
};
use ubaa_core::facade::{ConnectionMode, ErrorCode, ErrorKind, Result, RouteClient, UbaaError};

use super::JUDGE_LOGIN_URL;
use crate::common::{redirect_from, response, session_store_for, session_store_with};

#[derive(Clone)]
struct IsolatedJudgeSessionTransport {
    mode: ConnectionMode,
    activations: Arc<AtomicUsize>,
    selected_courses: Arc<Mutex<HashMap<String, String>>>,
}

impl IsolatedJudgeSessionTransport {
    fn new(mode: ConnectionMode) -> Self {
        Self {
            mode,
            activations: Arc::new(AtomicUsize::new(0)),
            selected_courses: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    fn session_cookie(request: &HttpRequest) -> Option<String> {
        request
            .headers
            .get("Cookie")
            .and_then(|header| {
                header
                    .split(';')
                    .map(str::trim)
                    .find_map(|cookie| cookie.strip_prefix("JUDGE="))
            })
            .map(str::to_owned)
    }

    fn direct_url(&self, url: &str) -> String {
        match self.mode {
            ConnectionMode::Direct => url.into(),
            ConnectionMode::WebVpn => from_webvpn_url(url).unwrap(),
        }
    }

    fn routed_url(&self, url: &str) -> String {
        match self.mode {
            ConnectionMode::Direct => url.into(),
            ConnectionMode::WebVpn => to_webvpn_url(url).unwrap(),
        }
    }
}

#[async_trait]
impl HttpTransport for IsolatedJudgeSessionTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let login_url = JUDGE_LOGIN_URL;
        let judge_home = "https://judge.buaa.edu.cn/";
        let direct_url = self.direct_url(&request.url);
        if direct_url == login_url {
            return Ok(redirect_from(&request.url, &self.routed_url(judge_home)));
        }
        if direct_url == judge_home {
            if Self::session_cookie(&request).is_some() {
                return Ok(response(200, &request.url, "existing judge home"));
            }
            let id = self.activations.fetch_add(1, Ordering::SeqCst) + 1;
            let mut response = response(200, &request.url, "new judge home");
            let (domain, path) = match self.mode {
                ConnectionMode::Direct => ("judge.buaa.edu.cn", "/".into()),
                ConnectionMode::WebVpn => {
                    let routed = self.routed_url(judge_home);
                    let path = routed
                        .strip_prefix("https://d.buaa.edu.cn")
                        .expect("gateway route")
                        .to_string();
                    ("d.buaa.edu.cn", path)
                }
            };
            response.headers.insert(
                "Set-Cookie".into(),
                vec![format!(
                    "JUDGE=session-{id}; Domain={domain}; Path={path}; Secure"
                )],
            );
            return Ok(response);
        }
        if direct_url == "https://judge.buaa.edu.cn/courselist.jsp?courseID=0" {
            return Ok(response(
                200,
                &request.url,
                r#"<a href="courselist.jsp?courseID=1">Course 1</a><a href="courselist.jsp?courseID=2">Course 2</a>"#,
            ));
        }
        if let Some(course_id) =
            direct_url.strip_prefix("https://judge.buaa.edu.cn/courselist.jsp?courseID=")
        {
            let session = Self::session_cookie(&request).ok_or_else(|| {
                UbaaError::new(
                    ErrorCode::InternalError,
                    ErrorKind::Internal,
                    false,
                    "Judge worker has no isolated service session",
                )
            })?;
            if session == "session-1" {
                return Err(UbaaError::new(
                    ErrorCode::InternalError,
                    ErrorKind::Internal,
                    false,
                    "Judge worker reused its parent service session",
                ));
            }
            self.selected_courses
                .lock()
                .expect("selected course lock")
                .insert(session, course_id.into());
            return Ok(response(200, &request.url, "selected"));
        }
        if direct_url == "https://judge.buaa.edu.cn/assignment/index.jsp" {
            let session = Self::session_cookie(&request).expect("worker Judge session");
            let course_id = self
                .selected_courses
                .lock()
                .expect("selected course lock")
                .get(&session)
                .cloned()
                .expect("selected course");
            return Ok(response(
                200,
                &request.url,
                &format!(
                    r#"<a href="assignment/index.jsp?assignID={course_id}">Lab {course_id}</a>"#
                ),
            ));
        }
        if direct_url.starts_with("https://judge.buaa.edu.cn/assignment/index.jsp?assignID=") {
            return Ok(response(
                200,
                &request.url,
                "作业满分:100 共 1 道 作业时间: 2026-08-01 08:00:00 至 2026-08-31 23:00:00 未提交",
            ));
        }
        Err(UbaaError::new(
            ErrorCode::InternalError,
            ErrorKind::Internal,
            false,
            "unexpected isolated Judge request",
        ))
    }
}

#[tokio::test]
async fn judge_workers_activate_isolated_service_sessions_before_course_selection() {
    let transport = IsolatedJudgeSessionTransport::new(ConnectionMode::Direct);
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("judge-isolated-worker-fixture"),
    )
    .unwrap();

    let result = client
        .judge_assignments(false)
        .await
        .expect("isolated Judge workers");

    assert_eq!(result.data.len(), 2);
    assert_eq!(observed.activations.load(Ordering::SeqCst), 3);
}

#[tokio::test]
async fn judge_single_detail_uses_an_isolated_service_session() {
    let transport = IsolatedJudgeSessionTransport::new(ConnectionMode::Direct);
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("judge-single-isolated-worker-fixture"),
    )
    .unwrap();

    let result = client
        .judge_assignment("1", "1")
        .await
        .expect("single Judge detail must use an isolated worker");

    assert_eq!(result.data.assignment_id, "1");
    assert_eq!(observed.activations.load(Ordering::SeqCst), 2);
}

#[tokio::test]
async fn judge_webvpn_workers_drop_parent_gateway_service_cookies() {
    let transport = IsolatedJudgeSessionTransport::new(ConnectionMode::WebVpn);
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::WebVpn,
        transport,
        session_store_for(
            ConnectionMode::WebVpn,
            "judge-webvpn-isolated-worker-fixture",
        ),
    )
    .unwrap();

    let result = client
        .judge_assignments(false)
        .await
        .expect("isolated Judge WebVPN workers");

    assert_eq!(result.data.len(), 2);
    assert_eq!(observed.activations.load(Ordering::SeqCst), 3);
}
