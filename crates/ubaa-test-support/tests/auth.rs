use std::collections::BTreeMap;

use async_trait::async_trait;
use ubaa_core::connection::{from_webvpn_url, to_webvpn_url};
use ubaa_core::domain::{
    CaptchaAnswer, ConnectionMode, DualLoginInput, LoginInput, LoginReadiness, RouteLoginState,
    SecretValue,
};
use ubaa_core::error::ErrorCode;
use ubaa_core::facade::{DualUbaaClient, UbaaClient};
use ubaa_core::ports::{HttpMethod, HttpRequest, HttpResponse, HttpTransport};
use ubaa_core::session::{
    DualSessionSnapshot, FileSessionStore, RouteSessionSnapshot, SessionMutation, SessionSnapshot,
    SessionStore, StoredCookie, VersionedSession,
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

fn basic_webvpn_transport() -> MockTransport {
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
    MockTransport::new([
        ExpectedRequest::new(
            HttpMethod::Get,
            &login,
            set_cookie(
                response(200, &login, login_page()),
                "WEBVPN_ROUTE=fixture; Domain=d.buaa.edu.cn; Path=/; Secure",
            ),
        ),
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
    ])
}

fn captcha_page(execution: &str) -> String {
    format!(
        r#"<form id="fm1"><input type="hidden" name="execution" value="{execution}"><input name="username"><input name="password"></form><script>config.captcha = {{ type: 'image', id: 'captcha-fixture' }}</script>"#
    )
}

fn dual_captcha_transports(prepares: usize, direct_posts: usize) -> (MockTransport, MockTransport) {
    let direct_login = "https://sso.buaa.edu.cn/login";
    let direct_captcha = "https://sso.buaa.edu.cn/captcha?captchaId=captcha-fixture";
    let webvpn_login = to_webvpn_url(direct_login).unwrap();
    let webvpn_captcha = to_webvpn_url(direct_captcha).unwrap();
    let mut direct = Vec::new();
    let mut webvpn = Vec::new();
    for round in 0..prepares {
        direct.push(ExpectedRequest::new(
            HttpMethod::Get,
            direct_login,
            response(
                200,
                direct_login,
                captcha_page(&format!("e-direct-{round}")),
            ),
        ));
        direct.push(ExpectedRequest::new(
            HttpMethod::Get,
            direct_captcha,
            response(200, direct_captcha, vec![1, 2, 3]),
        ));
        webvpn.push(ExpectedRequest::new(
            HttpMethod::Get,
            &webvpn_login,
            response(
                200,
                &webvpn_login,
                captcha_page(&format!("e-webvpn-{round}")),
            ),
        ));
        webvpn.push(ExpectedRequest::new(
            HttpMethod::Get,
            &webvpn_captcha,
            response(200, &webvpn_captcha, vec![4, 5, 6]),
        ));
    }
    for _ in 0..direct_posts {
        direct.push(ExpectedRequest::new(
            HttpMethod::Post,
            direct_login,
            response(401, direct_login, "invalid captcha"),
        ));
    }
    (MockTransport::new(direct), MockTransport::new(webvpn))
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
async fn dual_login_keeps_direct_slot_when_webvpn_route_fails() {
    let (direct_transport, _unused_memory_store) = basic_direct_transport();
    let root = std::env::temp_dir().join(format!("ubaa-dual-login-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let file_store = FileSessionStore::new(&root).unwrap();
    let mut client = DualUbaaClient::with_transports(
        direct_transport,
        MockTransport::new([]),
        file_store.clone(),
    )
    .unwrap();

    let outcome = client
        .login(DualLoginInput {
            username: "fixture-user".into(),
            password: SecretValue::new("fixture-password"),
            captcha_answers: Vec::new(),
        })
        .await
        .unwrap();

    assert_eq!(outcome.readiness, LoginReadiness::Partial);
    assert_eq!(outcome.routes.len(), 2);
    assert_eq!(outcome.routes[0].route, ConnectionMode::Direct);
    assert_eq!(
        outcome.routes[0].state,
        ubaa_core::domain::RouteLoginState::Ready
    );
    assert_eq!(outcome.routes[1].route, ConnectionMode::WebVpn);
    assert_eq!(
        outcome.routes[1].state,
        ubaa_core::domain::RouteLoginState::Failed
    );
    let dual = file_store.load_dual().unwrap().unwrap();
    assert!(dual.direct.is_some());
    assert!(dual.webvpn.is_none());
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn dual_login_persists_both_routes_without_a_false_sibling_conflict() {
    let (direct_transport, _unused_memory_store) = basic_direct_transport();
    let root = std::env::temp_dir().join(format!(
        "ubaa-dual-login-both-routes-{}",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&root);
    let file_store = FileSessionStore::new(&root).unwrap();
    let mut client = DualUbaaClient::with_transports(
        direct_transport,
        basic_webvpn_transport(),
        file_store.clone(),
    )
    .unwrap();

    let outcome = client
        .login(DualLoginInput {
            username: "fixture-user".into(),
            password: SecretValue::new("fixture-password"),
            captcha_answers: Vec::new(),
        })
        .await
        .unwrap();

    assert_eq!(outcome.readiness, LoginReadiness::AllReady);
    assert_eq!(
        client.active_routes(),
        vec![ConnectionMode::Direct, ConnectionMode::WebVpn]
    );
    let dual = file_store.load_dual().unwrap().unwrap();
    let direct = dual.direct().unwrap();
    let webvpn = dual.webvpn().unwrap();
    assert!(
        direct
            .cookies
            .iter()
            .any(|cookie| cookie.name == "PRELOGIN")
    );
    assert!(
        direct
            .cookies
            .iter()
            .all(|cookie| cookie.name != "WEBVPN_ROUTE")
    );
    assert!(
        webvpn
            .cookies
            .iter()
            .any(|cookie| cookie.name == "WEBVPN_ROUTE")
    );
    assert!(
        webvpn
            .cookies
            .iter()
            .all(|cookie| cookie.name != "PRELOGIN")
    );
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn dual_login_challenges_are_opaque_and_route_bound() {
    let (direct_transport, webvpn_transport) = dual_captcha_transports(1, 1);
    let direct_observer = direct_transport.clone();
    let webvpn_observer = webvpn_transport.clone();
    let root = std::env::temp_dir().join(format!(
        "ubaa-dual-captcha-route-bound-{}",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&root);
    let mut client = DualUbaaClient::with_transports(
        direct_transport,
        webvpn_transport,
        FileSessionStore::new(&root).unwrap(),
    )
    .unwrap();

    let preparation = client.prepare_login().await;
    assert_eq!(preparation.challenges.len(), 2);
    assert_ne!(
        preparation.challenges[0].challenge_id,
        preparation.challenges[1].challenge_id
    );
    assert!(
        preparation
            .challenges
            .iter()
            .all(|challenge| challenge.challenge_id != "captcha-fixture")
    );
    let direct_id = preparation.challenges[0].challenge_id.clone();
    let outcome = client
        .login(DualLoginInput {
            username: "fixture-user".into(),
            password: SecretValue::new("fixture-password"),
            captcha_answers: vec![CaptchaAnswer {
                challenge_id: direct_id,
                value: SecretValue::new("abcd"),
            }],
        })
        .await
        .unwrap();

    assert_eq!(outcome.routes[0].state, RouteLoginState::Failed);
    assert_eq!(outcome.routes[1].state, RouteLoginState::CaptchaRequired);
    assert_eq!(direct_observer.requests().unwrap().len(), 3);
    assert_eq!(webvpn_observer.requests().unwrap().len(), 2);
    direct_observer.assert_exhausted().unwrap();
    webvpn_observer.assert_exhausted().unwrap();
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn login_without_explicit_prepare_returns_actionable_captcha_challenges() {
    let (direct_transport, webvpn_transport) = dual_captcha_transports(1, 0);
    let direct_observer = direct_transport.clone();
    let webvpn_observer = webvpn_transport.clone();
    let root = std::env::temp_dir().join(format!(
        "ubaa-dual-captcha-login-prepare-{}",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&root);
    let mut client = DualUbaaClient::with_transports(
        direct_transport,
        webvpn_transport,
        FileSessionStore::new(&root).unwrap(),
    )
    .unwrap();

    let outcome = client
        .login(DualLoginInput {
            username: "fixture-user".into(),
            password: SecretValue::new("fixture-password"),
            captcha_answers: Vec::new(),
        })
        .await
        .unwrap();

    assert_eq!(outcome.readiness, LoginReadiness::NoneReady);
    assert_eq!(outcome.challenges.len(), 2);
    assert_ne!(
        outcome.challenges[0].challenge_id,
        outcome.challenges[1].challenge_id
    );
    assert!(outcome.challenges.iter().all(|challenge| {
        challenge.image_available && challenge.challenge_id != "captcha-fixture"
    }));
    assert_eq!(direct_observer.requests().unwrap().len(), 2);
    assert_eq!(webvpn_observer.requests().unwrap().len(), 2);
    direct_observer.assert_exhausted().unwrap();
    webvpn_observer.assert_exhausted().unwrap();
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn invalidated_password_login_reprepares_before_exposing_a_new_captcha() {
    let login = "https://sso.buaa.edu.cn/login";
    let landing = "https://uc.buaa.edu.cn/landing";
    let activate =
        "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin";
    let status = "https://uc.buaa.edu.cn/api/uc/status";
    let captcha = "https://sso.buaa.edu.cn/captcha?captchaId=captcha-fixture";
    let direct_transport = MockTransport::new([
        ExpectedRequest::new(HttpMethod::Get, login, response(200, login, login_page())),
        ExpectedRequest::new(HttpMethod::Post, login, redirect(login, landing)),
        ExpectedRequest::new(HttpMethod::Get, landing, response(200, landing, Vec::new())),
        ExpectedRequest::new(
            HttpMethod::Get,
            activate,
            response(200, activate, Vec::new()),
        ),
        ExpectedRequest::new(HttpMethod::Get, status, response(401, status, Vec::new())),
        ExpectedRequest::new(
            HttpMethod::Get,
            login,
            response(200, login, captcha_page("e-after-invalidation")),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            captcha,
            response(200, captcha, vec![1, 2, 3]),
        ),
    ]);
    let direct_observer = direct_transport.clone();
    let webvpn_transport = MockTransport::new([]);
    let webvpn_observer = webvpn_transport.clone();
    let root = std::env::temp_dir().join(format!(
        "ubaa-dual-captcha-login-invalidation-{}",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&root);
    let mut client = DualUbaaClient::with_transports(
        direct_transport,
        webvpn_transport,
        FileSessionStore::new(&root).unwrap(),
    )
    .unwrap();

    let preparation = client.prepare_login().await;
    assert_eq!(preparation.routes[0].state, RouteLoginState::Ready);
    assert_eq!(preparation.routes[1].state, RouteLoginState::Failed);
    let first = client
        .login(DualLoginInput {
            username: "fixture-user".into(),
            password: SecretValue::new("fixture-password"),
            captcha_answers: Vec::new(),
        })
        .await
        .unwrap();
    assert_eq!(first.routes[0].state, RouteLoginState::Failed);
    assert_eq!(
        first.routes[0]
            .error
            .as_ref()
            .map(|error| error.code.as_str()),
        Some("authentication_required")
    );
    assert!(first.challenges.is_empty());

    let second = client
        .login(DualLoginInput {
            username: "fixture-user".into(),
            password: SecretValue::new("fixture-password"),
            captcha_answers: Vec::new(),
        })
        .await
        .unwrap();

    assert_eq!(second.routes[0].state, RouteLoginState::CaptchaRequired);
    assert_eq!(second.challenges.len(), 1);
    assert_eq!(second.challenges[0].route, ConnectionMode::Direct);
    assert!(second.challenges[0].image_available);
    assert_ne!(second.challenges[0].challenge_id, "captcha-fixture");
    let direct_requests = direct_observer.requests().unwrap();
    assert_eq!(direct_requests.len(), 7);
    assert_eq!(
        direct_requests
            .iter()
            .filter(|request| request.method == HttpMethod::Post)
            .count(),
        1
    );
    assert_eq!(webvpn_observer.requests().unwrap().len(), 1);
    direct_observer.assert_exhausted().unwrap();
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn prepared_existing_session_is_consumed_without_reentering_sso() {
    let login = "https://sso.buaa.edu.cn/login";
    let landing = "https://uc.buaa.edu.cn/landing";
    let activate =
        "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin";
    let status = "https://uc.buaa.edu.cn/api/uc/status";
    let userinfo = "https://uc.buaa.edu.cn/api/uc/userinfo";
    let fixture = auth_fixture("userinfo-success.json").unwrap();
    let direct_transport = MockTransport::new([
        ExpectedRequest::new(HttpMethod::Get, login, redirect(login, landing)),
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
    let direct_observer = direct_transport.clone();
    let webvpn_transport = MockTransport::new([]);
    let root = std::env::temp_dir().join(format!(
        "ubaa-dual-existing-session-prepare-{}",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&root);
    let mut client = DualUbaaClient::with_transports(
        direct_transport,
        webvpn_transport,
        FileSessionStore::new(&root).unwrap(),
    )
    .unwrap();

    let preparation = client.prepare_login().await;
    assert_eq!(preparation.routes[0].state, RouteLoginState::Ready);
    assert_eq!(preparation.routes[1].state, RouteLoginState::Failed);
    let outcome = client
        .login(DualLoginInput {
            username: "fixture-user".into(),
            password: SecretValue::new("fixture-password"),
            captcha_answers: Vec::new(),
        })
        .await
        .unwrap();

    assert_eq!(outcome.readiness, LoginReadiness::Partial);
    assert_eq!(outcome.routes[0].state, RouteLoginState::Ready);
    assert_eq!(
        outcome
            .profile
            .as_ref()
            .and_then(|user| user.name.as_deref()),
        Some("Fixture User")
    );
    assert!(outcome.challenges.is_empty());
    let direct_requests = direct_observer.requests().unwrap();
    assert_eq!(direct_requests.len(), 4);
    assert_eq!(
        direct_requests
            .iter()
            .filter(|request| request.url == login)
            .count(),
        1
    );
    assert!(
        direct_requests
            .iter()
            .all(|request| request.method == HttpMethod::Get)
    );
    direct_observer.assert_exhausted().unwrap();
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn failed_reprepare_does_not_revive_the_previous_captcha_generation() {
    let direct_login = "https://sso.buaa.edu.cn/login";
    let direct_captcha = "https://sso.buaa.edu.cn/captcha?captchaId=captcha-fixture";
    let webvpn_login = to_webvpn_url(direct_login).unwrap();
    let webvpn_captcha = to_webvpn_url(direct_captcha).unwrap();
    let direct_transport = MockTransport::new([
        ExpectedRequest::new(
            HttpMethod::Get,
            direct_login,
            response(200, direct_login, captcha_page("e-direct-old")),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            direct_captcha,
            response(200, direct_captcha, vec![1, 2, 3]),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            direct_login,
            response(503, direct_login, Vec::new()),
        ),
    ]);
    let webvpn_transport = MockTransport::new([
        ExpectedRequest::new(
            HttpMethod::Get,
            &webvpn_login,
            response(200, &webvpn_login, captcha_page("e-webvpn-old")),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            &webvpn_captcha,
            response(200, &webvpn_captcha, vec![4, 5, 6]),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            &webvpn_login,
            response(503, &webvpn_login, Vec::new()),
        ),
    ]);
    let direct_observer = direct_transport.clone();
    let webvpn_observer = webvpn_transport.clone();
    let root = std::env::temp_dir().join(format!(
        "ubaa-dual-captcha-failed-reprepare-{}",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&root);
    let mut client = DualUbaaClient::with_transports(
        direct_transport,
        webvpn_transport,
        FileSessionStore::new(&root).unwrap(),
    )
    .unwrap();

    let first = client.prepare_login().await;
    let old_id = first.challenges[0].challenge_id.clone();
    let second = client.prepare_login().await;
    assert!(second.challenges.is_empty());
    assert!(
        second
            .routes
            .iter()
            .all(|route| route.state == RouteLoginState::Failed)
    );
    let error = client
        .login(DualLoginInput {
            username: "fixture-user".into(),
            password: SecretValue::new("fixture-password"),
            captcha_answers: vec![CaptchaAnswer {
                challenge_id: old_id,
                value: SecretValue::new("abcd"),
            }],
        })
        .await
        .unwrap_err();

    assert_eq!(error.code, ErrorCode::InvalidInput);
    assert_eq!(direct_observer.requests().unwrap().len(), 3);
    assert_eq!(webvpn_observer.requests().unwrap().len(), 3);
    direct_observer.assert_exhausted().unwrap();
    webvpn_observer.assert_exhausted().unwrap();
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn authentication_invalidation_expires_the_route_captcha_binding_before_post() {
    let direct_login = "https://sso.buaa.edu.cn/login";
    let direct_captcha = "https://sso.buaa.edu.cn/captcha?captchaId=captcha-fixture";
    let direct_status = "https://uc.buaa.edu.cn/api/uc/status";
    let direct_transport = MockTransport::new([
        ExpectedRequest::new(
            HttpMethod::Get,
            direct_login,
            response(200, direct_login, captcha_page("e-old")),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            direct_captcha,
            response(200, direct_captcha, vec![1, 2, 3]),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            direct_status,
            response(401, direct_status, Vec::new()),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            direct_login,
            response(200, direct_login, captcha_page("e-new")),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            direct_captcha,
            response(200, direct_captcha, vec![4, 5, 6]),
        ),
    ]);
    let direct_observer = direct_transport.clone();
    let webvpn_transport = MockTransport::new([]);
    let webvpn_observer = webvpn_transport.clone();
    let root = std::env::temp_dir().join(format!(
        "ubaa-dual-captcha-auth-clear-{}",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save_dual(&DualSessionSnapshot::new(
            Some(RouteSessionSnapshot::from_legacy(&SessionSnapshot {
                mode: ConnectionMode::Direct,
                cookies: vec![StoredCookie::fixture("SESSION", "fixture-cookie")],
                authenticated_at: 1,
                last_activity: 1,
            })),
            None,
        ))
        .unwrap();
    let mut client =
        DualUbaaClient::with_transports(direct_transport, webvpn_transport, store).unwrap();

    let preparation = client.prepare_login().await;
    let old_id = preparation.challenges[0].challenge_id.clone();
    let status = client.auth_status().await.unwrap();
    assert_eq!(status.routes[0].state, RouteLoginState::Failed);
    let error = client
        .login(DualLoginInput {
            username: "fixture-user".into(),
            password: SecretValue::new("fixture-password"),
            captcha_answers: vec![CaptchaAnswer {
                challenge_id: old_id,
                value: SecretValue::new("abcd"),
            }],
        })
        .await
        .unwrap_err();

    assert_eq!(error.code, ErrorCode::InvalidInput);
    let direct_requests = direct_observer.requests().unwrap();
    assert_eq!(direct_requests.len(), 5);
    assert!(
        direct_requests
            .iter()
            .all(|request| request.method == HttpMethod::Get)
    );
    assert_eq!(webvpn_observer.requests().unwrap().len(), 1);
    direct_observer.assert_exhausted().unwrap();
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn captcha_id_survives_a_sibling_route_prepare_failure() {
    let direct_login = "https://sso.buaa.edu.cn/login";
    let direct_captcha = "https://sso.buaa.edu.cn/captcha?captchaId=captcha-fixture";
    let webvpn_login = to_webvpn_url(direct_login).unwrap();
    let direct_transport = MockTransport::new([
        ExpectedRequest::new(
            HttpMethod::Get,
            direct_login,
            response(200, direct_login, captcha_page("e-direct")),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            direct_captcha,
            response(200, direct_captcha, vec![1, 2, 3]),
        ),
        ExpectedRequest::new(
            HttpMethod::Post,
            direct_login,
            response(401, direct_login, "invalid captcha"),
        ),
    ]);
    let webvpn_transport = MockTransport::new([ExpectedRequest::new(
        HttpMethod::Get,
        &webvpn_login,
        response(503, &webvpn_login, Vec::new()),
    )]);
    let direct_observer = direct_transport.clone();
    let webvpn_observer = webvpn_transport.clone();
    let root = std::env::temp_dir().join(format!(
        "ubaa-dual-captcha-partial-prepare-{}",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&root);
    let mut client = DualUbaaClient::with_transports(
        direct_transport,
        webvpn_transport,
        FileSessionStore::new(&root).unwrap(),
    )
    .unwrap();

    let preparation = client.prepare_login().await;
    assert_eq!(preparation.challenges.len(), 1);
    assert_eq!(preparation.challenges[0].route, ConnectionMode::Direct);
    assert_eq!(preparation.routes[1].state, RouteLoginState::Failed);
    let outcome = client
        .login(DualLoginInput {
            username: "fixture-user".into(),
            password: SecretValue::new("fixture-password"),
            captcha_answers: vec![CaptchaAnswer {
                challenge_id: preparation.challenges[0].challenge_id.clone(),
                value: SecretValue::new("abcd"),
            }],
        })
        .await
        .unwrap();

    assert_eq!(outcome.routes[0].state, RouteLoginState::Failed);
    assert_eq!(outcome.routes[1].state, RouteLoginState::Failed);
    assert_eq!(direct_observer.requests().unwrap().len(), 3);
    assert_eq!(webvpn_observer.requests().unwrap().len(), 1);
    direct_observer.assert_exhausted().unwrap();
    webvpn_observer.assert_exhausted().unwrap();
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn dual_login_rejects_unknown_and_duplicate_captcha_answers_before_post() {
    let (direct_transport, webvpn_transport) = dual_captcha_transports(1, 0);
    let direct_observer = direct_transport.clone();
    let webvpn_observer = webvpn_transport.clone();
    let root = std::env::temp_dir().join(format!(
        "ubaa-dual-captcha-validation-{}",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&root);
    let mut client = DualUbaaClient::with_transports(
        direct_transport,
        webvpn_transport,
        FileSessionStore::new(&root).unwrap(),
    )
    .unwrap();
    let preparation = client.prepare_login().await;
    let id = preparation.challenges[0].challenge_id.clone();

    let unknown = client
        .login(DualLoginInput {
            username: "fixture-user".into(),
            password: SecretValue::new("fixture-password"),
            captcha_answers: vec![CaptchaAnswer {
                challenge_id: "unknown-generation-id".into(),
                value: SecretValue::new("abcd"),
            }],
        })
        .await
        .unwrap_err();
    assert_eq!(unknown.code, ErrorCode::InvalidInput);

    let duplicate = client
        .login(DualLoginInput {
            username: "fixture-user".into(),
            password: SecretValue::new("fixture-password"),
            captcha_answers: vec![
                CaptchaAnswer {
                    challenge_id: id.clone(),
                    value: SecretValue::new("abcd"),
                },
                CaptchaAnswer {
                    challenge_id: id,
                    value: SecretValue::new("efgh"),
                },
            ],
        })
        .await
        .unwrap_err();
    assert_eq!(duplicate.code, ErrorCode::InvalidInput);
    assert_eq!(direct_observer.requests().unwrap().len(), 2);
    assert_eq!(webvpn_observer.requests().unwrap().len(), 2);
    direct_observer.assert_exhausted().unwrap();
    webvpn_observer.assert_exhausted().unwrap();
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn dual_login_rejects_empty_captcha_fields_before_post() {
    let (direct_transport, webvpn_transport) = dual_captcha_transports(1, 0);
    let direct_observer = direct_transport.clone();
    let webvpn_observer = webvpn_transport.clone();
    let root = std::env::temp_dir().join(format!(
        "ubaa-dual-captcha-empty-fields-{}",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&root);
    let mut client = DualUbaaClient::with_transports(
        direct_transport,
        webvpn_transport,
        FileSessionStore::new(&root).unwrap(),
    )
    .unwrap();
    let preparation = client.prepare_login().await;
    let id = preparation.challenges[0].challenge_id.clone();

    for answer in [
        CaptchaAnswer {
            challenge_id: "  ".into(),
            value: SecretValue::new("abcd"),
        },
        CaptchaAnswer {
            challenge_id: id.clone(),
            value: SecretValue::new("  "),
        },
    ] {
        let error = client
            .login(DualLoginInput {
                username: "fixture-user".into(),
                password: SecretValue::new("fixture-password"),
                captcha_answers: vec![answer],
            })
            .await
            .unwrap_err();
        assert_eq!(error.code, ErrorCode::InvalidInput);
    }

    assert_eq!(direct_observer.requests().unwrap().len(), 2);
    assert_eq!(webvpn_observer.requests().unwrap().len(), 2);
    direct_observer.assert_exhausted().unwrap();
    webvpn_observer.assert_exhausted().unwrap();
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn consumed_captcha_id_is_rejected_before_a_second_post() {
    let login = "https://sso.buaa.edu.cn/login";
    let captcha = "https://sso.buaa.edu.cn/captcha?captchaId=captcha-fixture";
    let webvpn_login = to_webvpn_url(login).unwrap();
    let direct_transport = MockTransport::new([
        ExpectedRequest::new(
            HttpMethod::Get,
            login,
            response(200, login, captcha_page("e-first")),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            captcha,
            response(200, captcha, vec![1, 2, 3]),
        ),
        ExpectedRequest::new(
            HttpMethod::Post,
            login,
            response(401, login, "invalid captcha"),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            login,
            response(200, login, captcha_page("e-second")),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            captcha,
            response(200, captcha, vec![4, 5, 6]),
        ),
    ]);
    let webvpn_transport = MockTransport::new([ExpectedRequest::new(
        HttpMethod::Get,
        &webvpn_login,
        response(503, &webvpn_login, Vec::new()),
    )]);
    let direct_observer = direct_transport.clone();
    let webvpn_observer = webvpn_transport.clone();
    let root =
        std::env::temp_dir().join(format!("ubaa-dual-captcha-consumed-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let mut client = DualUbaaClient::with_transports(
        direct_transport,
        webvpn_transport,
        FileSessionStore::new(&root).unwrap(),
    )
    .unwrap();
    let preparation = client.prepare_login().await;
    let id = preparation.challenges[0].challenge_id.clone();
    let input = || DualLoginInput {
        username: "fixture-user".into(),
        password: SecretValue::new("fixture-password"),
        captcha_answers: vec![CaptchaAnswer {
            challenge_id: id.clone(),
            value: SecretValue::new("abcd"),
        }],
    };

    let first = client.login(input()).await.unwrap();
    assert_eq!(first.routes[0].state, RouteLoginState::Failed);
    let second = client.login(input()).await.unwrap_err();

    assert_eq!(second.code, ErrorCode::InvalidInput);
    let requests = direct_observer.requests().unwrap();
    assert_eq!(requests.len(), 5);
    assert_eq!(
        requests
            .iter()
            .filter(|request| request.method == HttpMethod::Post)
            .count(),
        1
    );
    assert_eq!(webvpn_observer.requests().unwrap().len(), 1);
    direct_observer.assert_exhausted().unwrap();
    webvpn_observer.assert_exhausted().unwrap();
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn stale_captcha_generation_is_rejected_before_post() {
    let (direct_transport, webvpn_transport) = dual_captcha_transports(2, 0);
    let direct_observer = direct_transport.clone();
    let webvpn_observer = webvpn_transport.clone();
    let root = std::env::temp_dir().join(format!(
        "ubaa-dual-captcha-stale-generation-{}",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&root);
    let mut client = DualUbaaClient::with_transports(
        direct_transport,
        webvpn_transport,
        FileSessionStore::new(&root).unwrap(),
    )
    .unwrap();
    let first = client.prepare_login().await;
    let old_id = first.challenges[0].challenge_id.clone();
    let second = client.prepare_login().await;
    assert_ne!(old_id, second.challenges[0].challenge_id);

    let stale = client
        .login(DualLoginInput {
            username: "fixture-user".into(),
            password: SecretValue::new("fixture-password"),
            captcha_answers: vec![CaptchaAnswer {
                challenge_id: old_id,
                value: SecretValue::new("abcd"),
            }],
        })
        .await
        .unwrap_err();
    assert_eq!(stale.code, ErrorCode::InvalidInput);
    assert_eq!(direct_observer.requests().unwrap().len(), 4);
    assert_eq!(webvpn_observer.requests().unwrap().len(), 4);
    direct_observer.assert_exhausted().unwrap();
    webvpn_observer.assert_exhausted().unwrap();
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn logout_expires_captcha_ids_before_any_later_credential_post() {
    let login = "https://sso.buaa.edu.cn/login";
    let captcha = "https://sso.buaa.edu.cn/captcha?captchaId=captcha-fixture";
    let logout = "https://sso.buaa.edu.cn/logout";
    let webvpn_login = to_webvpn_url(login).unwrap();
    let webvpn_captcha = to_webvpn_url(captcha).unwrap();
    let webvpn_logout = to_webvpn_url(logout).unwrap();
    let direct_transport = MockTransport::new([
        ExpectedRequest::new(
            HttpMethod::Get,
            login,
            response(200, login, captcha_page("e-direct-old")),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            captcha,
            response(200, captcha, vec![1, 2, 3]),
        ),
        ExpectedRequest::new(HttpMethod::Get, logout, response(200, logout, Vec::new())),
        ExpectedRequest::new(
            HttpMethod::Get,
            login,
            response(200, login, captcha_page("e-direct-new")),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            captcha,
            response(200, captcha, vec![4, 5, 6]),
        ),
    ]);
    let webvpn_transport = MockTransport::new([
        ExpectedRequest::new(
            HttpMethod::Get,
            &webvpn_login,
            response(200, &webvpn_login, captcha_page("e-webvpn-old")),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            &webvpn_captcha,
            response(200, &webvpn_captcha, vec![7, 8, 9]),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            &webvpn_logout,
            response(200, &webvpn_logout, Vec::new()),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            &webvpn_login,
            response(200, &webvpn_login, captcha_page("e-webvpn-new")),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            &webvpn_captcha,
            response(200, &webvpn_captcha, vec![10, 11, 12]),
        ),
    ]);
    let direct_observer = direct_transport.clone();
    let webvpn_observer = webvpn_transport.clone();
    let root =
        std::env::temp_dir().join(format!("ubaa-dual-captcha-logout-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let mut client = DualUbaaClient::with_transports(
        direct_transport,
        webvpn_transport,
        FileSessionStore::new(&root).unwrap(),
    )
    .unwrap();
    let preparation = client.prepare_login().await;
    let old_id = preparation.challenges[0].challenge_id.clone();

    client.logout().await.unwrap();
    let error = client
        .login(DualLoginInput {
            username: "fixture-user".into(),
            password: SecretValue::new("fixture-password"),
            captcha_answers: vec![CaptchaAnswer {
                challenge_id: old_id,
                value: SecretValue::new("abcd"),
            }],
        })
        .await
        .unwrap_err();

    assert_eq!(error.code, ErrorCode::InvalidInput);
    for observer in [&direct_observer, &webvpn_observer] {
        assert!(
            observer
                .requests()
                .unwrap()
                .iter()
                .all(|request| request.method == HttpMethod::Get)
        );
        observer.assert_exhausted().unwrap();
    }
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn user_info_without_local_session_makes_zero_requests() {
    let transport = MockTransport::new([]);
    let observer = transport.clone();
    let mut client =
        UbaaClient::with_transport(ConnectionMode::Direct, transport, MemorySessionStore::new())
            .unwrap();

    let error = client.get_user_info().await.unwrap_err();

    assert_eq!(error.code, ErrorCode::AuthenticationRequired);
    assert!(observer.requests().unwrap().is_empty());
}

#[tokio::test]
async fn prepared_login_cookies_do_not_authorize_user_requests() {
    let login = "https://sso.buaa.edu.cn/login";
    let transport = MockTransport::new([ExpectedRequest::new(
        HttpMethod::Get,
        login,
        set_cookie(
            response(200, login, login_page()),
            "PRELOGIN=fixture; Domain=sso.buaa.edu.cn; Path=/; Secure",
        ),
    )]);
    let observer = transport.clone();
    let mut client =
        UbaaClient::with_transport(ConnectionMode::Direct, transport, MemorySessionStore::new())
            .unwrap();

    assert!(client.prepare_login().await.unwrap().is_none());
    let profile_error = client.get_user_info().await.unwrap_err();
    let status_error = client.auth_status().await.unwrap_err();

    assert_eq!(profile_error.code, ErrorCode::AuthenticationRequired);
    assert_eq!(status_error.code, ErrorCode::AuthenticationRequired);
    assert_eq!(observer.requests().unwrap().len(), 1);
    observer.assert_exhausted().unwrap();
}

#[tokio::test]
async fn persistence_error_after_status_clears_uncommitted_authentication() {
    let (transport, _unused_store) = basic_direct_transport();
    let observer = transport.clone();
    let mut client =
        UbaaClient::with_transport(ConnectionMode::Direct, transport, FailingMutationStore)
            .unwrap();

    let persistence_error = client.login(login_input(None)).await.unwrap_err();
    let profile_error = client.get_user_info().await.unwrap_err();

    assert_eq!(persistence_error.code, ErrorCode::InternalError);
    assert_eq!(profile_error.code, ErrorCode::AuthenticationRequired);
    assert_eq!(observer.requests().unwrap().len(), 5);
}

#[tokio::test]
async fn stale_aggregate_logout_preserves_both_newer_slots() {
    let root = std::env::temp_dir().join(format!("ubaa-dual-stale-logout-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store.save_dual(&dual_snapshot("initial")).unwrap();
    let mut client = DualUbaaClient::with_transports(
        MockTransport::new([]),
        MockTransport::new([]),
        store.clone(),
    )
    .unwrap();
    let newer = dual_snapshot("newer");
    store.save_dual(&newer).unwrap();

    let error = client.logout().await.unwrap_err();

    assert_eq!(error.code, ErrorCode::InternalError);
    assert!(error.retryable);
    assert_eq!(store.load_dual().unwrap(), Some(newer));
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn aggregate_logout_opened_empty_rejects_a_later_external_session() {
    let root = std::env::temp_dir().join(format!(
        "ubaa-dual-empty-then-stale-logout-{}",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    let mut client = DualUbaaClient::with_transports(
        MockTransport::new([]),
        MockTransport::new([]),
        store.clone(),
    )
    .unwrap();
    let newer = dual_snapshot("newer");
    store.save_dual(&newer).unwrap();

    let error = client.logout().await.unwrap_err();

    assert_eq!(error.code, ErrorCode::InternalError);
    assert!(error.retryable);
    assert_eq!(store.load_dual().unwrap(), Some(newer));
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn aggregate_logout_without_slots_attempts_both_remote_routes() {
    let root = std::env::temp_dir().join(format!(
        "ubaa-dual-empty-remote-logout-{}",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&root);
    let direct_url = "https://sso.buaa.edu.cn/logout";
    let webvpn_url = to_webvpn_url(direct_url).unwrap();
    let direct = MockTransport::new([ExpectedRequest::new(
        HttpMethod::Get,
        direct_url,
        response(503, direct_url, Vec::new()),
    )]);
    let direct_observer = direct.clone();
    let webvpn = MockTransport::new([ExpectedRequest::new(
        HttpMethod::Get,
        &webvpn_url,
        response(503, &webvpn_url, Vec::new()),
    )]);
    let webvpn_observer = webvpn.clone();
    let mut client =
        DualUbaaClient::with_transports(direct, webvpn, FileSessionStore::new(&root).unwrap())
            .unwrap();

    client.logout().await.unwrap();

    direct_observer.assert_exhausted().unwrap();
    webvpn_observer.assert_exhausted().unwrap();
    assert_eq!(direct_observer.requests().unwrap().len(), 1);
    assert_eq!(webvpn_observer.requests().unwrap().len(), 1);
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn successful_aggregate_logout_advances_revision_once() {
    let root = std::env::temp_dir().join(format!(
        "ubaa-dual-single-logout-cas-{}",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store.save_dual(&dual_snapshot("initial")).unwrap();
    let initial_revision = store.load_dual_versioned().unwrap().revision;
    let mut client = DualUbaaClient::with_transports(
        MockTransport::new([]),
        MockTransport::new([]),
        store.clone(),
    )
    .unwrap();

    client.logout().await.unwrap();

    let final_state = store.load_dual_versioned().unwrap();
    assert!(final_state.snapshot.is_none());
    assert_eq!(final_state.revision, initial_revision + 1);
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn aggregate_status_conflict_clears_both_routes_and_stops_sibling_io() {
    let root =
        std::env::temp_dir().join(format!("ubaa-dual-status-conflict-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store.save_dual(&dual_snapshot("initial")).unwrap();
    let direct_status = "https://uc.buaa.edu.cn/api/uc/status";
    let direct_transport = MockTransport::new([ExpectedRequest::new(
        HttpMethod::Get,
        direct_status,
        response(
            200,
            direct_status,
            r#"{"code":0,"data":{"name":"Fixture User","schoolid":"TEST-0001","username":"fixture-user"}}"#,
        ),
    )]);
    let direct_observer = direct_transport.clone();
    let webvpn_transport = MockTransport::new([]);
    let webvpn_observer = webvpn_transport.clone();
    let mut client =
        DualUbaaClient::with_transports(direct_transport, webvpn_transport, store.clone()).unwrap();
    let newer = dual_snapshot("newer");
    store.save_dual(&newer).unwrap();

    let error = client.auth_status().await.unwrap_err();

    assert_eq!(error.code, ErrorCode::InternalError);
    assert!(error.retryable);
    assert_eq!(direct_observer.requests().unwrap().len(), 1);
    assert!(webvpn_observer.requests().unwrap().is_empty());
    assert!(client.active_routes().is_empty());
    assert_eq!(store.load_dual().unwrap(), Some(newer));

    let preparation = client.prepare_login().await;
    assert_eq!(preparation.routes.len(), 2);
    assert!(
        preparation
            .routes
            .iter()
            .all(|route| route.state == ubaa_core::domain::RouteLoginState::Failed)
    );
    let repeated_login = client
        .login(DualLoginInput {
            username: "fixture-user".into(),
            password: SecretValue::new("fixture-password"),
            captcha_answers: Vec::new(),
        })
        .await
        .unwrap_err();
    assert_eq!(repeated_login.code, ErrorCode::InternalError);
    let repeated = client.auth_status().await.unwrap_err();
    assert_eq!(repeated.code, ErrorCode::InternalError);
    let repeated_logout = client.logout().await.unwrap_err();
    assert_eq!(repeated_logout.code, ErrorCode::InternalError);
    assert_eq!(direct_observer.requests().unwrap().len(), 1);
    assert!(webvpn_observer.requests().unwrap().is_empty());
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn terminal_logout_conflict_expires_prepared_captcha_ids() {
    let login = "https://sso.buaa.edu.cn/login";
    let captcha = "https://sso.buaa.edu.cn/captcha?captchaId=captcha-fixture";
    let logout = "https://sso.buaa.edu.cn/logout";
    let webvpn_login = to_webvpn_url(login).unwrap();
    let webvpn_captcha = to_webvpn_url(captcha).unwrap();
    let webvpn_logout = to_webvpn_url(logout).unwrap();
    let direct_transport = MockTransport::new([
        ExpectedRequest::new(
            HttpMethod::Get,
            login,
            response(200, login, captcha_page("e-direct")),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            captcha,
            response(200, captcha, vec![1, 2, 3]),
        ),
        ExpectedRequest::new(HttpMethod::Get, logout, response(200, logout, Vec::new())),
    ]);
    let webvpn_transport = MockTransport::new([
        ExpectedRequest::new(
            HttpMethod::Get,
            &webvpn_login,
            response(200, &webvpn_login, captcha_page("e-webvpn")),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            &webvpn_captcha,
            response(200, &webvpn_captcha, vec![4, 5, 6]),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            &webvpn_logout,
            response(200, &webvpn_logout, Vec::new()),
        ),
    ]);
    let direct_observer = direct_transport.clone();
    let webvpn_observer = webvpn_transport.clone();
    let root =
        std::env::temp_dir().join(format!("ubaa-dual-captcha-conflict-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    let mut client =
        DualUbaaClient::with_transports(direct_transport, webvpn_transport, store.clone()).unwrap();
    let preparation = client.prepare_login().await;
    let old_id = preparation.challenges[0].challenge_id.clone();
    store.save_dual(&dual_snapshot("external")).unwrap();

    let conflict = client.logout().await.unwrap_err();
    assert_eq!(conflict.code, ErrorCode::InternalError);
    let repeated = client
        .login(DualLoginInput {
            username: "fixture-user".into(),
            password: SecretValue::new("fixture-password"),
            captcha_answers: vec![CaptchaAnswer {
                challenge_id: old_id,
                value: SecretValue::new("abcd"),
            }],
        })
        .await
        .unwrap_err();

    assert_eq!(repeated.code, ErrorCode::InternalError);
    for observer in [&direct_observer, &webvpn_observer] {
        let requests = observer.requests().unwrap();
        assert_eq!(requests.len(), 3);
        assert!(
            requests
                .iter()
                .all(|request| request.method == HttpMethod::Get)
        );
        observer.assert_exhausted().unwrap();
    }
    let _ = std::fs::remove_dir_all(root);
}

fn dual_snapshot(label: &str) -> DualSessionSnapshot {
    let slot = |route| {
        RouteSessionSnapshot::from_legacy(&SessionSnapshot {
            mode: route,
            cookies: vec![StoredCookie::fixture(
                format!("SESSION-{label}-{route:?}"),
                format!("fixture-cookie-{label}-{route:?}"),
            )],
            authenticated_at: 1,
            last_activity: 1,
        })
    };
    DualSessionSnapshot::new(
        Some(slot(ConnectionMode::Direct)),
        Some(slot(ConnectionMode::WebVpn)),
    )
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

struct FailingMutationStore;

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

impl SessionStore for FailingMutationStore {
    fn load_versioned(&self) -> ubaa_core::error::Result<VersionedSession> {
        Ok(VersionedSession {
            snapshot: None,
            revision: 0,
        })
    }

    fn compare_exchange(
        &self,
        _expected_revision: u64,
        _replacement: Option<&SessionSnapshot>,
    ) -> ubaa_core::error::Result<SessionMutation> {
        Err(ubaa_core::error::UbaaError::new(
            ErrorCode::InternalError,
            ubaa_core::error::ErrorKind::Internal,
            true,
            "fixture persistence failure",
        ))
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
