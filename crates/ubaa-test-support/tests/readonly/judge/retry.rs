use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

use async_trait::async_trait;
use ubaa_core::facade::testing::{
    DualSessionSnapshot, FileSessionStore, HttpMethod, HttpRequest, HttpResponse, HttpTransport,
    RouteConfig, RouteSessionSnapshot, SessionMutation, SessionSnapshot, SessionStore,
    StoredCookie, VersionedSession, to_webvpn_url,
};
use ubaa_core::facade::{
    ConnectionMode, DualLoginInput, ErrorCode, ErrorKind, LoginInput, Result, RouteClient,
    RouteLoginState, SecretValue, UbaaClient, UbaaError,
};
use ubaa_test_support::MemorySessionStore;

use super::{JUDGE_LOGIN_URL, UnknownGatewayProbe};
use crate::common::{SpocTransport, redirect_from, response, session_store_with};

const UC_STATUS_URL: &str = "https://uc.buaa.edu.cn/api/uc/status";
#[derive(Clone)]
struct JudgeRetryTransport {
    course_requests: Arc<AtomicUsize>,
    activation_requests: Arc<AtomicUsize>,
    status_requests: Arc<AtomicUsize>,
    status_response: Option<HttpResponse>,
    successful_attempt: Option<usize>,
}

impl JudgeRetryTransport {
    fn new(successful_attempt: Option<usize>) -> Self {
        Self::with_status(successful_attempt, None)
    }

    fn with_status(
        successful_attempt: Option<usize>,
        status_response: Option<HttpResponse>,
    ) -> Self {
        Self {
            course_requests: Arc::new(AtomicUsize::new(0)),
            activation_requests: Arc::new(AtomicUsize::new(0)),
            status_requests: Arc::new(AtomicUsize::new(0)),
            status_response,
            successful_attempt,
        }
    }
}

#[async_trait]
impl HttpTransport for JudgeRetryTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        if request.url == JUDGE_LOGIN_URL {
            self.activation_requests.fetch_add(1, Ordering::SeqCst);
            return Ok(redirect_from(&request.url, "https://judge.buaa.edu.cn/"));
        }
        if request.url == "https://judge.buaa.edu.cn/" {
            return Ok(response(200, &request.url, "judge ready"));
        }
        if request.url == "https://judge.buaa.edu.cn/courselist.jsp?courseID=0" {
            let attempt = self.course_requests.fetch_add(1, Ordering::SeqCst) + 1;
            let body = if self
                .successful_attempt
                .is_some_and(|successful_attempt| attempt >= successful_attempt)
            {
                "<html><body>no courses</body></html>"
            } else {
                r#"<form><input name="execution" value="fixture"></form>统一身份认证"#
            };
            return Ok(response(200, &request.url, body));
        }
        if request.url == UC_STATUS_URL {
            self.status_requests.fetch_add(1, Ordering::SeqCst);
            return self.status_response.clone().ok_or_else(|| {
                UbaaError::new(
                    ErrorCode::InternalError,
                    ErrorKind::Internal,
                    false,
                    "unexpected Judge status request",
                )
            });
        }
        Err(UbaaError::new(
            ErrorCode::InternalError,
            ErrorKind::Internal,
            false,
            "unexpected Judge retry request",
        ))
    }
}

#[derive(Clone)]
struct ConflictOnRefreshStore {
    inner: MemorySessionStore,
}

impl SessionStore for ConflictOnRefreshStore {
    fn load_versioned(&self) -> Result<VersionedSession> {
        self.inner.load_versioned()
    }

    fn compare_exchange(
        &self,
        _expected_revision: u64,
        _replacement: Option<&SessionSnapshot>,
    ) -> Result<SessionMutation> {
        Ok(SessionMutation::Conflict)
    }
}

#[derive(Clone)]
struct AggregateJudgeInvalidationTransport {
    mode: ConnectionMode,
    sso_gets: Arc<AtomicUsize>,
    sso_posts: Arc<AtomicUsize>,
}

impl AggregateJudgeInvalidationTransport {
    fn new(mode: ConnectionMode) -> Self {
        Self {
            mode,
            sso_gets: Arc::new(AtomicUsize::new(0)),
            sso_posts: Arc::new(AtomicUsize::new(0)),
        }
    }
}

#[async_trait]
impl HttpTransport for AggregateJudgeInvalidationTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let sso_url = match self.mode {
            ConnectionMode::Direct => "https://sso.buaa.edu.cn/login".to_string(),
            ConnectionMode::WebVpn => {
                to_webvpn_url("https://sso.buaa.edu.cn/login").expect("WebVPN SSO URL")
            }
        };
        if request.url == sso_url {
            return match request.method {
                HttpMethod::Get => {
                    let attempt = self.sso_gets.fetch_add(1, Ordering::SeqCst) + 1;
                    if self.mode == ConnectionMode::Direct && attempt > 1 {
                        Ok(response(503, &request.url, ""))
                    } else {
                        let page = r#"<form id="fm1" action="/login" method="post"><input type="hidden" name="execution" value="fixture-execution"><input name="username"><input name="password"></form>"#;
                        Ok(response(200, &request.url, page))
                    }
                }
                HttpMethod::Post => {
                    self.sso_posts.fetch_add(1, Ordering::SeqCst);
                    Ok(response(503, &request.url, ""))
                }
            };
        }
        if self.mode == ConnectionMode::Direct && request.url == JUDGE_LOGIN_URL {
            return Ok(redirect_from(&request.url, "https://judge.buaa.edu.cn/"));
        }
        if self.mode == ConnectionMode::Direct && request.url == "https://judge.buaa.edu.cn/" {
            return Ok(response(200, &request.url, "judge ready"));
        }
        if self.mode == ConnectionMode::Direct
            && request.url == "https://judge.buaa.edu.cn/courselist.jsp?courseID=0"
        {
            let body = r#"<form><input name="execution" value="fixture"></form>统一身份认证"#;
            return Ok(response(200, &request.url, body));
        }
        if self.mode == ConnectionMode::Direct && request.url == UC_STATUS_URL {
            return Ok(response(401, UC_STATUS_URL, ""));
        }
        Err(UbaaError::new(
            ErrorCode::InternalError,
            ErrorKind::Internal,
            false,
            "unexpected aggregate Judge invalidation request",
        ))
    }
}

#[tokio::test]
async fn judge_business_request_allows_three_reactivations_then_succeeds() {
    let transport = JudgeRetryTransport::new(Some(4));
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("judge-three-reactivations-fixture"),
    )
    .expect("client");

    let result = client
        .judge_assignments(false)
        .await
        .expect("the fourth business attempt must succeed");

    assert!(result.data.is_empty());
    assert_eq!(observed.course_requests.load(Ordering::SeqCst), 4);
    assert_eq!(observed.activation_requests.load(Ordering::SeqCst), 4);
}

#[tokio::test]
async fn judge_business_request_stops_after_three_failed_reactivations() {
    let transport = JudgeRetryTransport::with_status(None, Some(response(503, UC_STATUS_URL, "")));
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("judge-reactivation-exhaustion-fixture"),
    )
    .expect("client");

    let error = client
        .judge_assignments(false)
        .await
        .expect_err("the fourth failed business attempt must be terminal");

    assert_eq!(error.code, ErrorCode::UpstreamUnavailable);
    assert!(error.retryable);
    assert_eq!(observed.course_requests.load(Ordering::SeqCst), 4);
    assert_eq!(observed.activation_requests.load(Ordering::SeqCst), 4);
    assert_eq!(observed.status_requests.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn judge_authentication_exhaustion_preserves_session_when_uc_is_valid() {
    let profile = r#"{"code":0,"data":{"name":"Fixture User","schoolid":"TEST-0001","username":"fixture-user"}}"#;
    let status = response(200, UC_STATUS_URL, profile);
    let transport = JudgeRetryTransport::with_status(None, Some(status));
    let observed = transport.clone();
    let store = session_store_with("judge-auth-valid-fixture");
    let mut client = RouteClient::with_transport(ConnectionMode::Direct, transport, store.clone())
        .expect("client");

    let error = client
        .judge_assignments(false)
        .await
        .expect_err("Judge auth exhaustion must remain a business failure");

    assert_eq!(error.code, ErrorCode::UpstreamUnavailable);
    assert!(error.retryable);
    assert!(store.snapshot().unwrap().is_some());
    assert_eq!(observed.status_requests.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn judge_authentication_exhaustion_preserves_session_when_uc_is_unavailable() {
    let status = response(503, UC_STATUS_URL, "");
    let transport = JudgeRetryTransport::with_status(None, Some(status));
    let observed = transport.clone();
    let store = session_store_with("judge-auth-unavailable-fixture");
    let mut client = RouteClient::with_transport(ConnectionMode::Direct, transport, store.clone())
        .expect("client");

    let error = client
        .judge_assignments(false)
        .await
        .expect_err("Judge auth exhaustion must remain inconclusive when UC is unavailable");

    assert_eq!(error.code, ErrorCode::UpstreamUnavailable);
    assert!(error.retryable);
    assert!(store.snapshot().unwrap().is_some());
    assert_eq!(observed.status_requests.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn judge_authentication_exhaustion_preserves_session_when_uc_json_is_malformed() {
    let status = response(200, UC_STATUS_URL, r#"{"code":0,"data": "#);
    let transport = JudgeRetryTransport::with_status(None, Some(status));
    let observed = transport.clone();
    let store = session_store_with("judge-auth-malformed-json-fixture");
    let mut client = RouteClient::with_transport(ConnectionMode::Direct, transport, store.clone())
        .expect("client");

    let error = client
        .judge_assignments(false)
        .await
        .expect_err("malformed UC JSON must remain an inconclusive business failure");

    assert_eq!(error.code, ErrorCode::UpstreamUnavailable);
    assert!(error.retryable);
    assert!(store.snapshot().unwrap().is_some());
    assert_eq!(observed.status_requests.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn judge_authentication_exhaustion_preserves_refresh_conflict_as_internal_error() {
    let profile = r#"{"code":0,"data":{"name":"Fixture User","schoolid":"TEST-0001","username":"fixture-user"}}"#;
    let status = response(200, UC_STATUS_URL, profile);
    let inner = session_store_with("judge-auth-conflict-fixture");
    let store = ConflictOnRefreshStore {
        inner: inner.clone(),
    };
    let transport = JudgeRetryTransport::with_status(None, Some(status));
    let observed = transport.clone();
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, transport, store).expect("client");

    let error = client
        .judge_assignments(false)
        .await
        .expect_err("a session CAS conflict must escape UC arbitration");

    assert_eq!(error.code, ErrorCode::InternalError);
    assert_eq!(error.kind, ErrorKind::Internal);
    assert!(error.retryable);
    assert!(inner.snapshot().unwrap().is_some());
    assert_eq!(observed.status_requests.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn judge_authentication_exhaustion_clears_session_when_uc_rejects_it() {
    let status = response(401, UC_STATUS_URL, "");
    let transport = JudgeRetryTransport::with_status(None, Some(status));
    let observed = transport.clone();
    let store = session_store_with("judge-auth-invalid-fixture");
    let mut client = RouteClient::with_transport(ConnectionMode::Direct, transport, store.clone())
        .expect("client");

    let error = client
        .judge_assignments(false)
        .await
        .expect_err("an explicitly invalid UC session must remain an auth failure");

    assert_eq!(error.code, ErrorCode::AuthenticationRequired);
    assert!(!error.retryable);
    assert!(store.snapshot().unwrap().is_none());
    assert_eq!(observed.status_requests.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn judge_invalid_primary_session_clears_only_the_selected_route_slot() {
    let status = response(401, UC_STATUS_URL, "");
    let direct_transport = JudgeRetryTransport::with_status(None, Some(status));
    let observed = direct_transport.clone();
    let root = std::env::temp_dir().join(format!(
        "ubaa-judge-selected-route-invalidation-{}",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).expect("session store");
    let slot = |mode, label| {
        RouteSessionSnapshot::from_legacy(&SessionSnapshot {
            mode,
            cookies: vec![StoredCookie::fixture("SID", label)],
            authenticated_at: 1,
            last_activity: 2,
        })
    };
    store
        .save_dual(&DualSessionSnapshot::new(
            Some(slot(ConnectionMode::Direct, "judge-direct-fixture")),
            Some(slot(ConnectionMode::WebVpn, "judge-webvpn-fixture")),
        ))
        .expect("seed dual sessions");
    let config = RouteConfig::parse("[route]\ndefault = 'direct'\n").expect("route config");
    let mut client = UbaaClient::with_routing(
        direct_transport,
        JudgeRetryTransport::new(Some(4)),
        store.clone(),
        config,
        UnknownGatewayProbe,
    )
    .expect("aggregate client");

    let error = client
        .judge_assignments(false)
        .await
        .expect_err("UC rejected Direct");

    assert_eq!(error.error.code, ErrorCode::AuthenticationRequired);
    let persisted = store
        .load_dual()
        .expect("load dual sessions")
        .expect("dual sessions");
    assert!(persisted.direct().is_none());
    assert!(persisted.webvpn().is_some());
    assert_eq!(observed.status_requests.load(Ordering::SeqCst), 1);
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn aggregate_judge_invalidation_clears_the_selected_pending_login_workflow() {
    let root = std::env::temp_dir().join(format!(
        "ubaa-judge-workflow-invalidation-{}",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).expect("session store");
    let slot = |mode, label| {
        RouteSessionSnapshot::from_legacy(&SessionSnapshot {
            mode,
            cookies: vec![StoredCookie::fixture("SID", label)],
            authenticated_at: 1,
            last_activity: 2,
        })
    };
    store
        .save_dual(&DualSessionSnapshot::new(
            Some(slot(ConnectionMode::Direct, "judge-direct-fixture")),
            Some(slot(ConnectionMode::WebVpn, "judge-webvpn-fixture")),
        ))
        .expect("seed dual sessions");
    let direct = AggregateJudgeInvalidationTransport::new(ConnectionMode::Direct);
    let observed_direct = direct.clone();
    let webvpn = AggregateJudgeInvalidationTransport::new(ConnectionMode::WebVpn);
    let config = RouteConfig::parse("[route]\ndefault = 'direct'\n").expect("route config");
    let mut client = UbaaClient::with_routing(direct, webvpn, store, config, UnknownGatewayProbe)
        .expect("aggregate client");

    let preparation = client.prepare_login().await;
    assert!(
        preparation
            .routes
            .iter()
            .all(|route| { route.state == RouteLoginState::Ready })
    );
    let error = client
        .judge_assignments(false)
        .await
        .expect_err("UC must reject the selected Direct route");
    assert_eq!(error.error.code, ErrorCode::AuthenticationRequired);

    let outcome = client
        .login(DualLoginInput {
            username: "fixture-user".into(),
            password: SecretValue::new("fixture-password"),
        })
        .await
        .expect("route failures remain aggregate login data");

    assert_eq!(
        outcome.routes[0]
            .error
            .as_ref()
            .expect("Direct login failure")
            .code,
        "upstream_unavailable"
    );
    assert_eq!(observed_direct.sso_gets.load(Ordering::SeqCst), 2);
    assert_eq!(observed_direct.sso_posts.load(Ordering::SeqCst), 0);
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn successful_primary_login_invalidates_route_owned_judge_caches() {
    let judge_login = JUDGE_LOGIN_URL;
    let judge_home = "https://judge.buaa.edu.cn/";
    let courses_url = "https://judge.buaa.edu.cn/courselist.jsp?courseID=0";
    let select_url = "https://judge.buaa.edu.cn/courselist.jsp?courseID=1";
    let assignments_url = "https://judge.buaa.edu.cn/assignment/index.jsp";
    let detail_url = "https://judge.buaa.edu.cn/assignment/index.jsp?assignID=101";
    let primary_login = "https://sso.buaa.edu.cn/login";
    let activate =
        "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin";
    let status = "https://uc.buaa.edu.cn/api/uc/status";
    let userinfo = "https://uc.buaa.edu.cn/api/uc/userinfo";
    let profile = r#"{"code":0,"data":{"name":"Fixture User","schoolid":"TEST-0001","username":"fixture-user"}}"#;
    let courses = r#"<a href="courselist.jsp?courseID=1">Course 1</a>"#;
    let assignments = r#"<a href="assignment/index.jsp?assignID=101">Assignment</a>"#;
    let detail = "作业满分: 10 共 1 道 作业时间: 2026-08-01 08:00 至 2026-08-31 23:00 未提交";
    let one_judge_read = || {
        [
            (judge_login.into(), redirect_from(judge_login, judge_home)),
            (judge_home.into(), response(200, judge_home, "judge ready")),
            (courses_url.into(), response(200, courses_url, courses)),
            (judge_login.into(), redirect_from(judge_login, judge_home)),
            (judge_home.into(), response(200, judge_home, "judge ready")),
            (select_url.into(), response(200, select_url, "selected")),
            (
                assignments_url.into(),
                response(200, assignments_url, assignments),
            ),
            (select_url.into(), response(200, select_url, "selected")),
            (detail_url.into(), response(200, detail_url, detail)),
        ]
    };
    let transport = SpocTransport::new(
        one_judge_read()
            .into_iter()
            .chain([
                (
                    primary_login.into(),
                    redirect_from(primary_login, "/already-authenticated"),
                ),
                (activate.into(), response(200, activate, "")),
                (status.into(), response(200, status, profile)),
                (userinfo.into(), response(200, userinfo, profile)),
            ])
            .chain(one_judge_read()),
    );
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("judge-primary-relogin-fixture"),
    )
    .expect("client");

    client
        .judge_assignment("1", "101")
        .await
        .expect("first Judge detail");
    client.prepare_login().await.unwrap();
    client
        .login(LoginInput {
            username: "fixture-user".into(),
            password: SecretValue::new("fixture-password"),
        })
        .await
        .expect("primary relogin");
    client
        .judge_assignment("1", "101")
        .await
        .expect("Judge detail after relogin");

    observed.assert_exhausted();
    assert_eq!(
        observed
            .requests()
            .iter()
            .filter(|request| request.url == courses_url)
            .count(),
        2,
        "a successful primary relogin must clear Judge list caches"
    );
    assert_eq!(
        observed
            .requests()
            .iter()
            .filter(|request| request.url == detail_url)
            .count(),
        2,
        "a successful primary relogin must clear Judge detail caches"
    );
}
