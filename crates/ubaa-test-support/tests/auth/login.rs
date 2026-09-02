use ubaa_core::connection::{from_webvpn_url, to_webvpn_url};
use ubaa_core::domain::ConnectionMode;
use ubaa_core::error::ErrorCode;
use ubaa_core::facade::RouteClient;
use ubaa_core::ports::HttpMethod;
use ubaa_test_support::{ExpectedRequest, MemorySessionStore, MockTransport, auth_fixture};

use crate::common::{
    basic_direct_transport, login_input, login_page, persisted_store, redirect, response,
};

#[test]
fn public_client_facade_is_concrete_and_accepts_injected_ports() {
    fn accepts_concrete_client(client: RouteClient) -> RouteClient {
        client
    }

    let client = RouteClient::with_transport(
        ConnectionMode::Direct,
        MockTransport::new([]),
        MemorySessionStore::new(),
    )
    .unwrap();

    let _client = accepts_concrete_client(client);
}

#[tokio::test]
async fn direct_login_follows_cas_and_returns_userinfo_profile() {
    let (transport, store) = basic_direct_transport();
    let observer = transport.clone();
    let mut client = RouteClient::with_transport(ConnectionMode::Direct, transport, store).unwrap();

    let profile = client.login(login_input()).await.unwrap();

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
async fn captcha_marker_is_rejected_without_fetching_image_or_posting_credentials() {
    let login = "https://sso.buaa.edu.cn/login";
    let page = r#"<form id="fm1"><input type="hidden" name="execution" value="e-captcha"><input name="username"><input name="password"></form><script>config.captcha = { type: 'image', id: 'captcha-fixture' }</script>"#;
    let transport = MockTransport::new([ExpectedRequest::new(
        HttpMethod::Get,
        login,
        response(200, login, page),
    )]);
    let observer = transport.clone();
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, transport, MemorySessionStore::new())
            .unwrap();

    let error = client.login(login_input()).await.unwrap_err();

    assert_eq!(error.code, ErrorCode::UpstreamChanged);
    let requests = observer.requests().unwrap();
    assert_eq!(requests.len(), 1);
    assert_eq!(requests[0].method, HttpMethod::Get);
    assert!(
        requests
            .iter()
            .all(|request| request.method != HttpMethod::Post)
    );
    observer.assert_exhausted().unwrap();
}

#[tokio::test]
async fn nonstandard_interactive_login_control_is_rejected_without_posting_credentials() {
    let login = "https://sso.buaa.edu.cn/login";
    let page = r#"
      <form id="fm1">
        <input type="hidden" name="execution" value="e-verification">
        <input type="text" name="username">
        <input type="password" name="password">
        <input type="text" name="verificationCode">
      </form>
    "#;
    let transport = MockTransport::new([ExpectedRequest::new(
        HttpMethod::Get,
        login,
        response(200, login, page),
    )]);
    let observer = transport.clone();
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, transport, MemorySessionStore::new())
            .unwrap();

    let error = client.login(login_input()).await.unwrap_err();

    assert_eq!(error.code, ErrorCode::UpstreamChanged);
    let requests = observer.requests().unwrap();
    assert_eq!(requests.len(), 1);
    assert!(
        requests
            .iter()
            .all(|request| request.method == HttpMethod::Get)
    );
    observer.assert_exhausted().unwrap();
}

#[tokio::test]
async fn nameless_input_and_button_login_controls_are_rejected_without_posting_credentials() {
    let login = "https://sso.buaa.edu.cn/login";
    let page = r#"
      <form id="fm1">
        <input type="hidden" name="execution" value="e-verification">
        <input type="text" name="username">
        <input type="password" name="password">
        <input type="text">
        <button type="button">验证</button>
      </form>
    "#;
    let transport = MockTransport::new([ExpectedRequest::new(
        HttpMethod::Get,
        login,
        response(200, login, page),
    )]);
    let observer = transport.clone();
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, transport, MemorySessionStore::new())
            .unwrap();

    let error = client.login(login_input()).await.unwrap_err();

    assert_eq!(error.code, ErrorCode::UpstreamChanged);
    let requests = observer.requests().unwrap();
    assert_eq!(requests.len(), 1);
    assert!(
        requests
            .iter()
            .all(|request| request.method == HttpMethod::Get)
    );
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
        RouteClient::with_transport(ConnectionMode::Direct, transport, MemorySessionStore::new())
            .unwrap();

    client.login(login_input()).await.unwrap();

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
        RouteClient::with_transport(ConnectionMode::Direct, transport, MemorySessionStore::new())
            .unwrap();

    let error = client.login(login_input()).await.unwrap_err();

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
        RouteClient::with_transport(ConnectionMode::WebVpn, transport, MemorySessionStore::new())
            .unwrap();

    client.login(login_input()).await.unwrap();
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
    let mut client = RouteClient::with_transport(ConnectionMode::Direct, transport, store).unwrap();

    assert!(client.prepare_login().await.is_ok());
    assert!(
        observer
            .requests()
            .unwrap()
            .iter()
            .all(|request| request.method == HttpMethod::Get)
    );
    observer.assert_exhausted().unwrap();
}
