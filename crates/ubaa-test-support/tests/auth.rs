use std::collections::BTreeMap;

use async_trait::async_trait;
use ubaa_core::connection::{from_webvpn_url, to_webvpn_url};
use ubaa_core::domain::{ConnectionMode, LoginInput, SecretValue};
use ubaa_core::error::ErrorCode;
use ubaa_core::facade::UbaaClient;
use ubaa_core::ports::{HttpMethod, HttpRequest, HttpResponse, HttpTransport};
use ubaa_core::session::{
    SessionMutation, SessionSnapshot, SessionStore, StoredCookie, VersionedSession,
};
use ubaa_test_support::{ExpectedRequest, MemorySessionStore, MockTransport, auth_fixture};

fn response(status: u16, url: &str, body: impl Into<Vec<u8>>) -> HttpResponse {
    HttpResponse::new(status, url, body.into())
}

fn redirect(url: &str, location: &str) -> HttpResponse {
    let mut headers = BTreeMap::new();
    headers.insert("Location".into(), vec![location.into()]);
    HttpResponse {
        status: 302,
        final_url: url.into(),
        headers,
        body: Vec::new(),
    }
}

fn set_cookie(mut response: HttpResponse, cookie: &str) -> HttpResponse {
    response
        .headers
        .insert("Set-Cookie".into(), vec![cookie.into()]);
    response
}

fn login_input(captcha: Option<&str>) -> LoginInput {
    LoginInput {
        username: "fixture-user".into(),
        password: SecretValue::new("fixture-password"),
        captcha: captcha.map(str::to_owned),
    }
}

fn login_page() -> String {
    r#"
    <html><body><form id="fm1" action="/login" method="post">
      <input type="hidden" name="execution" value="e1s1-fixture">
      <input type="hidden" name="lt" value="lt-fixture">
      <input type="text" name="username">
      <input type="password" name="password">
      <input type="checkbox" name="remember" value="yes" checked>
      <input type="submit" name="submit" value="Log in">
      <input type="image" name="ignored-image" value="ignored">
    </form></body></html>
    "#
    .into()
}

fn basic_direct_transport() -> (MockTransport, MemorySessionStore) {
    let login = "https://sso.buaa.edu.cn/login";
    let landing = "https://uc.buaa.edu.cn/landing";
    let activate =
        "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin";
    let status = "https://uc.buaa.edu.cn/api/uc/status";
    let userinfo = "https://uc.buaa.edu.cn/api/uc/userinfo";
    let fixture = auth_fixture("userinfo-success.json").unwrap();
    let transport = MockTransport::new([
        ExpectedRequest::new(
            HttpMethod::Get,
            login,
            set_cookie(
                response(200, login, login_page()),
                "PRELOGIN=fixture; Domain=sso.buaa.edu.cn; Path=/; Secure",
            ),
        ),
        ExpectedRequest::new(
            HttpMethod::Post,
            login,
            set_cookie(
                redirect(login, landing),
                "CASTGC=fixture; Domain=sso.buaa.edu.cn; Path=/; Secure",
            ),
        ),
        ExpectedRequest::new(HttpMethod::Get, landing, response(200, landing, Vec::new())),
        ExpectedRequest::new(
            HttpMethod::Get,
            activate,
            set_cookie(
                response(200, activate, Vec::new()),
                "JSESSIONID=fixture; Domain=uc.buaa.edu.cn; Path=/; Secure",
            ),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            status,
            response(
                200,
                status,
                r#"{"code":0,"data":{"name":"Fixture User","schoolid":"TEST-0001","username":"fixture-user"}}"#,
            ),
        ),
        ExpectedRequest::new(HttpMethod::Get, userinfo, response(200, userinfo, fixture)),
    ]);
    (transport, MemorySessionStore::new())
}

#[test]
fn public_client_facade_is_concrete_and_accepts_injected_ports() {
    fn accepts_concrete_client(client: UbaaClient) -> UbaaClient {
        client
    }

    let client = UbaaClient::with_transport(
        ConnectionMode::Direct,
        MockTransport::new([]),
        MemorySessionStore::new(),
    )
    .unwrap();

    let _client = accepts_concrete_client(client);
}

#[test]
fn mode_mismatch_does_not_clear_a_session_replaced_after_loading() {
    let inner = MemorySessionStore::new();
    inner
        .save(&SessionSnapshot {
            mode: ConnectionMode::WebVpn,
            cookies: vec![StoredCookie::fixture("OLD", "old-fixture-cookie")],
            authenticated_at: 1,
            last_activity: 1,
        })
        .unwrap();
    let newer = SessionSnapshot {
        mode: ConnectionMode::Direct,
        cookies: vec![StoredCookie::fixture("NEW", "new-fixture-cookie")],
        authenticated_at: 2,
        last_activity: 2,
    };
    let store = ReplaceAfterLoadStore {
        inner: inner.clone(),
        replacement: newer.clone(),
    };

    let result = UbaaClient::with_transport(ConnectionMode::Direct, MockTransport::new([]), store);
    let Err(error) = result else {
        panic!("a stale mode-mismatch clear unexpectedly succeeded");
    };

    assert_eq!(error.code, ErrorCode::InternalError);
    assert!(error.retryable);
    assert_eq!(inner.snapshot().unwrap(), Some(newer));
}

#[tokio::test]
async fn direct_login_follows_cas_and_returns_userinfo_profile() {
    let (transport, store) = basic_direct_transport();
    let observer = transport.clone();
    let mut client = UbaaClient::with_transport(ConnectionMode::Direct, transport, store).unwrap();

    let profile = client.login(login_input(None)).await.unwrap();

    assert_eq!(profile.name.as_deref(), Some("Fixture User"));
    assert_eq!(profile.school_id.as_deref(), Some("TEST-0001"));
    let requests = observer.requests().unwrap();
    let body = String::from_utf8_lossy(&requests[1].body);
    assert!(body.contains("execution=e1s1-fixture"));
    assert!(body.contains("lt=lt-fixture"));
    assert!(body.contains("remember=yes"));
    assert!(!body.contains("ignored-image"));
    assert!(
        requests[1]
            .headers
            .get("Cookie")
            .unwrap()
            .contains("PRELOGIN=fixture")
    );
    observer.assert_exhausted().unwrap();
}

#[tokio::test]
async fn prepare_login_keeps_execution_and_captcha_for_same_client_retry() {
    let login = "https://sso.buaa.edu.cn/login";
    let captcha = "https://sso.buaa.edu.cn/captcha?captchaId=captcha-fixture";
    let landing = "https://uc.buaa.edu.cn/landing";
    let activate =
        "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin";
    let status = "https://uc.buaa.edu.cn/api/uc/status";
    let userinfo = "https://uc.buaa.edu.cn/api/uc/userinfo";
    let fixture = auth_fixture("userinfo-success.json").unwrap();
    let page = r#"<form id="fm1"><input type="hidden" name="execution" value="e-cap"><input name="username"><input name="password"></form><script>config.captcha = { type: 'image', id: 'captcha-fixture' }</script>"#;
    let transport = MockTransport::new([
        ExpectedRequest::new(HttpMethod::Get, login, response(200, login, page)),
        ExpectedRequest::new(
            HttpMethod::Get,
            captcha,
            response(200, captcha, vec![1, 2, 3]),
        ),
        ExpectedRequest::new(HttpMethod::Post, login, redirect(login, landing)),
        ExpectedRequest::new(HttpMethod::Get, landing, response(200, landing, Vec::new())),
        ExpectedRequest::new(
            HttpMethod::Get,
            activate,
            response(200, activate, Vec::new()),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            status,
            response(
                200,
                status,
                r#"{"code":0,"data":{"name":"Fixture User","schoolid":"TEST-0001","username":"fixture-user"}}"#,
            ),
        ),
        ExpectedRequest::new(HttpMethod::Get, userinfo, response(200, userinfo, fixture)),
    ]);
    let observer = transport.clone();
    let mut client =
        UbaaClient::with_transport(ConnectionMode::Direct, transport, MemorySessionStore::new())
            .unwrap();

    let challenge = client
        .prepare_login()
        .await
        .unwrap()
        .expect("captcha challenge");
    assert_eq!(challenge.execution, "e-cap");
    assert!(
        challenge
            .image_data_url
            .unwrap()
            .starts_with("data:image/jpeg;base64,")
    );
    let profile = client.login(login_input(Some("abcd"))).await.unwrap();

    assert_eq!(profile.school_id.as_deref(), Some("TEST-0001"));
    let requests = observer.requests().unwrap();
    let body = String::from_utf8_lossy(&requests[2].body);
    assert!(body.contains("captcha=abcd"));
    assert!(body.contains("captchaResponse=abcd"));
    assert!(body.contains("execution=e-cap"));
    observer.assert_exhausted().unwrap();
}

#[tokio::test]
async fn persistence_conflict_clears_pending_login_workflow_state() {
    let login = "https://sso.buaa.edu.cn/login";
    let captcha = "https://sso.buaa.edu.cn/captcha?captchaId=captcha-fixture";
    let landing = "https://uc.buaa.edu.cn/landing";
    let activate =
        "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin";
    let status = "https://uc.buaa.edu.cn/api/uc/status";
    let page = r#"<form id="fm1"><input type="hidden" name="execution" value="e-cap"><input name="username"><input name="password"></form><script>config.captcha = { type: 'image', id: 'captcha-fixture' }</script>"#;
    let transport = MockTransport::new([
        ExpectedRequest::new(HttpMethod::Get, login, response(200, login, page)),
        ExpectedRequest::new(
            HttpMethod::Get,
            captcha,
            response(200, captcha, vec![1, 2, 3]),
        ),
        ExpectedRequest::new(HttpMethod::Post, login, redirect(login, landing)),
        ExpectedRequest::new(HttpMethod::Get, landing, response(200, landing, Vec::new())),
        ExpectedRequest::new(
            HttpMethod::Get,
            activate,
            response(200, activate, Vec::new()),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            status,
            response(
                200,
                status,
                r#"{"code":0,"data":{"name":"Fixture User","schoolid":"TEST-0001","username":"fixture-user"}}"#,
            ),
        ),
        ExpectedRequest::new(HttpMethod::Get, login, response(503, login, Vec::new())),
    ]);
    let observer = transport.clone();
    let store = MemorySessionStore::new();
    let mut client =
        UbaaClient::with_transport(ConnectionMode::Direct, transport, store.clone()).unwrap();

    client
        .prepare_login()
        .await
        .unwrap()
        .expect("captcha challenge");
    store.clear().unwrap();
    let conflict = client.login(login_input(Some("abcd"))).await.unwrap_err();
    assert_eq!(conflict.code, ErrorCode::InternalError);
    assert!(conflict.retryable);

    let next = client.login(login_input(None)).await.unwrap_err();
    assert_eq!(next.code, ErrorCode::UpstreamUnavailable);
    observer.assert_exhausted().unwrap();
}

#[tokio::test]
async fn captcha_challenge_without_answer_never_submits_credentials() {
    let login = "https://sso.buaa.edu.cn/login";
    let captcha = "https://sso.buaa.edu.cn/captcha?captchaId=captcha-fixture";
    let page = r#"<form id="fm1"><input type="hidden" name="execution" value="e-cap"></form><script>config.captcha = { type: 'image', id: 'captcha-fixture' }</script>"#;
    let transport = MockTransport::new([
        ExpectedRequest::new(HttpMethod::Get, login, response(200, login, page)),
        ExpectedRequest::new(
            HttpMethod::Get,
            captcha,
            response(200, captcha, vec![1, 2, 3]),
        ),
    ]);
    let observer = transport.clone();
    let mut client =
        UbaaClient::with_transport(ConnectionMode::Direct, transport, MemorySessionStore::new())
            .unwrap();

    let error = client.login(login_input(None)).await.unwrap_err();

    assert_eq!(error.code, ErrorCode::CaptchaRequired);
    assert_eq!(error.challenge.unwrap().execution, "e-cap");
    assert_eq!(observer.requests().unwrap().len(), 2);
    observer.assert_exhausted().unwrap();
}

#[tokio::test]
async fn password_risk_page_is_continued_once_with_new_execution() {
    let login = "https://sso.buaa.edu.cn/login";
    let landing = "https://uc.buaa.edu.cn/landing";
    let activate =
        "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin";
    let status = "https://uc.buaa.edu.cn/api/uc/status";
    let userinfo = "https://uc.buaa.edu.cn/api/uc/userinfo";
    let fixture = auth_fixture("userinfo-success.json").unwrap();
    let warning = r#"<form id="continueForm"><input type="hidden" name="execution" value="e-risk"><div>账号存在安全风险，请修改密码</div><button name="_eventId" value="ignoreAndContinue">继续</button></form>"#;
    let transport = MockTransport::new([
        ExpectedRequest::new(HttpMethod::Get, login, response(200, login, login_page())),
        ExpectedRequest::new(HttpMethod::Post, login, response(200, login, warning)),
        ExpectedRequest::new(HttpMethod::Post, login, redirect(login, landing)),
        ExpectedRequest::new(HttpMethod::Get, landing, response(200, landing, Vec::new())),
        ExpectedRequest::new(
            HttpMethod::Get,
            activate,
            response(200, activate, Vec::new()),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            status,
            response(
                200,
                status,
                r#"{"code":0,"data":{"name":"Fixture User","schoolid":"TEST-0001","username":"fixture-user"}}"#,
            ),
        ),
        ExpectedRequest::new(HttpMethod::Get, userinfo, response(200, userinfo, fixture)),
    ]);
    let observer = transport.clone();
    let mut client =
        UbaaClient::with_transport(ConnectionMode::Direct, transport, MemorySessionStore::new())
            .unwrap();

    client.login(login_input(None)).await.unwrap();

    let requests = observer.requests().unwrap();
    let body = String::from_utf8_lossy(&requests[2].body);
    assert!(body.contains("execution=e-risk"));
    assert!(body.contains("_eventId=ignoreAndContinue"));
    observer.assert_exhausted().unwrap();
}

#[tokio::test]
async fn repeated_password_risk_page_fails_after_one_continuation() {
    let login = "https://sso.buaa.edu.cn/login";
    let warning = r#"<form id="continueForm"><input name="execution" value="e-risk"><button value="ignoreAndContinue">Continue</button></form>"#;
    let transport = MockTransport::new([
        ExpectedRequest::new(HttpMethod::Get, login, response(200, login, login_page())),
        ExpectedRequest::new(HttpMethod::Post, login, response(200, login, warning)),
        ExpectedRequest::new(HttpMethod::Post, login, response(200, login, warning)),
    ]);
    let mut client =
        UbaaClient::with_transport(ConnectionMode::Direct, transport, MemorySessionStore::new())
            .unwrap();

    let error = client.login(login_input(None)).await.unwrap_err();

    assert_eq!(error.code, ErrorCode::PasswordRiskConfirmationFailed);
}

#[tokio::test]
async fn webvpn_login_uses_gateway_for_every_auth_request() {
    let direct_login = "https://sso.buaa.edu.cn/login";
    let direct_landing = "https://uc.buaa.edu.cn/landing";
    let direct_activate =
        "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin";
    let direct_status = "https://uc.buaa.edu.cn/api/uc/status";
    let direct_userinfo = "https://uc.buaa.edu.cn/api/uc/userinfo";
    let login = to_webvpn_url(direct_login).unwrap();
    let landing = to_webvpn_url(direct_landing).unwrap();
    let activate = to_webvpn_url(direct_activate).unwrap();
    let status = to_webvpn_url(direct_status).unwrap();
    let userinfo = to_webvpn_url(direct_userinfo).unwrap();
    let fixture = auth_fixture("userinfo-success.json").unwrap();
    let transport = MockTransport::new([
        ExpectedRequest::new(HttpMethod::Get, &login, response(200, &login, login_page())),
        ExpectedRequest::new(HttpMethod::Post, &login, redirect(&login, &landing)),
        ExpectedRequest::new(
            HttpMethod::Get,
            &landing,
            response(200, &landing, Vec::new()),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            &activate,
            response(200, &activate, Vec::new()),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            &status,
            response(
                200,
                &status,
                r#"{"code":0,"data":{"name":"Fixture User","schoolid":"TEST-0001","username":"fixture-user"}}"#,
            ),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            &userinfo,
            response(200, &userinfo, fixture),
        ),
    ]);
    let observer = transport.clone();
    let mut client =
        UbaaClient::with_transport(ConnectionMode::WebVpn, transport, MemorySessionStore::new())
            .unwrap();

    client.login(login_input(None)).await.unwrap();
    assert!(
        observer
            .requests()
            .unwrap()
            .iter()
            .all(|request| request.url.starts_with("https://d.buaa.edu.cn/"))
    );
    observer.assert_exhausted().unwrap();
    assert_eq!(from_webvpn_url(&status).unwrap(), direct_status);
}

#[tokio::test]
async fn invalid_status_clears_session_but_server_error_keeps_it() {
    let status = "https://uc.buaa.edu.cn/api/uc/status";
    let invalid_transport = MockTransport::new([ExpectedRequest::new(
        HttpMethod::Get,
        status,
        response(401, status, Vec::new()),
    )]);
    let invalid_store = persisted_store();
    let mut invalid_client = UbaaClient::with_transport(
        ConnectionMode::Direct,
        invalid_transport,
        invalid_store.clone(),
    )
    .unwrap();
    let error = invalid_client.auth_status().await.unwrap_err();
    assert_eq!(error.code, ErrorCode::AuthenticationRequired);
    assert!(invalid_store.snapshot().unwrap().is_none());

    let server_transport = MockTransport::new([ExpectedRequest::new(
        HttpMethod::Get,
        status,
        response(503, status, Vec::new()),
    )]);
    let server_store = persisted_store();
    let mut server_client = UbaaClient::with_transport(
        ConnectionMode::Direct,
        server_transport,
        server_store.clone(),
    )
    .unwrap();
    let error = server_client.auth_status().await.unwrap_err();
    assert_eq!(error.code, ErrorCode::UpstreamUnavailable);
    assert!(server_store.snapshot().unwrap().is_some());
}

#[tokio::test]
async fn stale_client_cannot_recreate_a_session_cleared_by_another_process() {
    let status = "https://uc.buaa.edu.cn/api/uc/status";
    let transport = MockTransport::new([ExpectedRequest::new(
        HttpMethod::Get,
        status,
        response(
            200,
            status,
            r#"{"code":0,"data":{"name":"Fixture User","schoolid":"TEST-0001","username":"fixture-user"}}"#,
        ),
    )]);
    let observer = transport.clone();
    let store = persisted_store();
    let mut stale_client =
        UbaaClient::with_transport(ConnectionMode::Direct, transport, store.clone()).unwrap();
    store.clear().unwrap();

    let error = stale_client.auth_status().await.unwrap_err();

    assert_eq!(error.code, ErrorCode::InternalError);
    assert!(error.retryable);
    assert_eq!(error.message, "local session changed in another process");
    assert!(!error.message.contains("fixture-cookie"));
    assert!(store.snapshot().unwrap().is_none());
    let next = stale_client.auth_status().await.unwrap_err();
    assert_eq!(next.code, ErrorCode::AuthenticationRequired);
    assert_eq!(observer.requests().unwrap().len(), 1);
}

#[tokio::test]
async fn stale_logout_cannot_clear_a_newer_persisted_session() {
    let store = persisted_store();
    let mut stale_client = UbaaClient::with_transport(
        ConnectionMode::Direct,
        MockTransport::new([]),
        store.clone(),
    )
    .unwrap();
    let newer = SessionSnapshot {
        mode: ConnectionMode::Direct,
        cookies: vec![StoredCookie::fixture("NEWER", "newer-fixture-cookie")],
        authenticated_at: 2,
        last_activity: 2,
    };
    store.save(&newer).unwrap();

    let error = stale_client.logout().await.unwrap_err();

    assert_eq!(error.code, ErrorCode::InternalError);
    assert!(error.retryable);
    assert_eq!(store.snapshot().unwrap(), Some(newer));
}

#[tokio::test]
async fn existing_sso_cookie_activates_and_validates_user_center_without_password_submission() {
    let login = "https://sso.buaa.edu.cn/login";
    let activate =
        "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin";
    let status = "https://uc.buaa.edu.cn/api/uc/status";
    let transport = MockTransport::new([
        ExpectedRequest::new(
            HttpMethod::Get,
            login,
            redirect(login, "/already-authenticated"),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            activate,
            response(200, activate, Vec::new()),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            status,
            response(
                200,
                status,
                r#"{"code":0,"data":{"name":"Fixture User","schoolid":"TEST-0001","username":"fixture-user"}}"#,
            ),
        ),
    ]);
    let observer = transport.clone();
    let store = persisted_store();
    let mut client = UbaaClient::with_transport(ConnectionMode::Direct, transport, store).unwrap();

    assert!(client.prepare_login().await.unwrap().is_none());
    assert!(
        observer
            .requests()
            .unwrap()
            .iter()
            .all(|request| request.method == HttpMethod::Get)
    );
    observer.assert_exhausted().unwrap();
}

#[tokio::test]
async fn html_and_non_json_status_responses_clear_persisted_session() {
    for body in [
        "<!DOCTYPE html><html>统一身份认证</html>",
        "<!doctype html><HTML><body>signed out</body></HTML>",
        "<!DoCtYpE hTmL><html><body>signed out</body></html>",
        "<HTML><body>signed out</body></HTML>",
        "<HtMl><body>signed out</body></HtMl>",
        "temporarily not json",
    ] {
        let status = "https://uc.buaa.edu.cn/api/uc/status";
        let transport = MockTransport::new([ExpectedRequest::new(
            HttpMethod::Get,
            status,
            response(200, status, body),
        )]);
        let store = persisted_store();
        let mut client =
            UbaaClient::with_transport(ConnectionMode::Direct, transport, store.clone()).unwrap();

        let error = client.auth_status().await.unwrap_err();

        assert_eq!(error.code, ErrorCode::AuthenticationRequired);
        assert!(store.snapshot().unwrap().is_none());
    }
}

#[tokio::test]
async fn html_userinfo_response_clears_session_and_logout_always_clears_local_state() {
    let userinfo = "https://uc.buaa.edu.cn/api/uc/userinfo";
    for body in [
        "<!DOCTYPE html><html>统一身份认证</html>",
        "<!doctype html><HTML><body>signed out</body></HTML>",
        "<!DoCtYpE hTmL><html><body>signed out</body></html>",
        "<HTML><body>signed out</body></HTML>",
        "<HtMl><body>signed out</body></HtMl>",
    ] {
        let transport = MockTransport::new([ExpectedRequest::new(
            HttpMethod::Get,
            userinfo,
            response(200, userinfo, body),
        )]);
        let store = persisted_store();
        let mut client =
            UbaaClient::with_transport(ConnectionMode::Direct, transport, store.clone()).unwrap();
        let error = client.get_user_info().await.unwrap_err();
        assert_eq!(error.code, ErrorCode::AuthenticationRequired);
        assert!(store.snapshot().unwrap().is_none());
    }

    let logout_store = persisted_store();
    let mut logout_client = UbaaClient::with_transport(
        ConnectionMode::Direct,
        MockTransport::new([]),
        logout_store.clone(),
    )
    .unwrap();
    logout_client.logout().await.unwrap();
    assert!(logout_store.snapshot().unwrap().is_none());
}

#[tokio::test]
async fn timeout_error_is_preserved_without_clearing_persisted_session() {
    let store = persisted_store();
    let mut client =
        UbaaClient::with_transport(ConnectionMode::Direct, TimeoutTransport, store.clone())
            .unwrap();
    let error = client.auth_status().await.unwrap_err();
    assert_eq!(error.code, ErrorCode::Timeout);
    assert!(store.snapshot().unwrap().is_some());
}

fn persisted_store() -> MemorySessionStore {
    let store = MemorySessionStore::new();
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: vec![StoredCookie::fixture("SESSION", "fixture-cookie")],
            authenticated_at: 1,
            last_activity: 1,
        })
        .unwrap();
    store
}

struct TimeoutTransport;

struct ReplaceAfterLoadStore {
    inner: MemorySessionStore,
    replacement: SessionSnapshot,
}

impl SessionStore for ReplaceAfterLoadStore {
    fn load_versioned(&self) -> ubaa_core::error::Result<VersionedSession> {
        let loaded = self.inner.load_versioned()?;
        self.inner.save(&self.replacement)?;
        Ok(loaded)
    }

    fn compare_exchange(
        &self,
        expected_revision: u64,
        replacement: Option<&SessionSnapshot>,
    ) -> ubaa_core::error::Result<SessionMutation> {
        self.inner.compare_exchange(expected_revision, replacement)
    }
}

#[async_trait]
impl HttpTransport for TimeoutTransport {
    async fn execute(&self, _request: HttpRequest) -> ubaa_core::error::Result<HttpResponse> {
        Err(ubaa_core::error::UbaaError::new(
            ErrorCode::Timeout,
            ubaa_core::error::ErrorKind::Network,
            true,
            "fixture timeout",
        ))
    }
}
