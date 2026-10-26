use async_trait::async_trait;
use ubaa_core::facade::testing::{
    FileSessionStore, HttpMethod, HttpRequest, HttpResponse, HttpTransport, SessionMutation,
    SessionSnapshot, SessionStore, VersionedSession,
};
use ubaa_core::facade::{
    ConnectionMode, DualLoginInput, ErrorCode, ErrorKind, LoginReadiness, Result, RouteClient,
    RouteLoginState, SecretValue, UbaaClient, UbaaError,
};
use ubaa_test_support::{ExpectedRequest, MemorySessionStore, MockTransport, auth_fixture};

use crate::common::{
    basic_direct_transport, login_input, login_page, persisted_store, redirect, response,
    set_cookie,
};

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
    let mut client = UbaaClient::with_transports(
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
async fn user_info_without_local_session_makes_zero_requests() {
    let transport = MockTransport::new([]);
    let observer = transport.clone();
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, transport, MemorySessionStore::new())
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
        RouteClient::with_transport(ConnectionMode::Direct, transport, MemorySessionStore::new())
            .unwrap();

    assert!(client.prepare_login().await.is_ok());
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
        RouteClient::with_transport(ConnectionMode::Direct, transport, FailingMutationStore)
            .unwrap();

    let persistence_error = client.login(login_input()).await.unwrap_err();
    let profile_error = client.get_user_info().await.unwrap_err();

    assert_eq!(persistence_error.code, ErrorCode::InternalError);
    assert_eq!(profile_error.code, ErrorCode::AuthenticationRequired);
    assert_eq!(observer.requests().unwrap().len(), 5);
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
    let mut invalid_client = RouteClient::with_transport(
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
    let mut server_client = RouteClient::with_transport(
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
            RouteClient::with_transport(ConnectionMode::Direct, transport, store.clone()).unwrap();

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
            RouteClient::with_transport(ConnectionMode::Direct, transport, store.clone()).unwrap();
        let error = client.get_user_info().await.unwrap_err();
        assert_eq!(error.code, ErrorCode::AuthenticationRequired);
        assert!(store.snapshot().unwrap().is_none());
    }

    let logout_store = persisted_store();
    let mut logout_client = RouteClient::with_transport(
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
        RouteClient::with_transport(ConnectionMode::Direct, TimeoutTransport, store.clone())
            .unwrap();
    let error = client.auth_status().await.unwrap_err();
    assert_eq!(error.code, ErrorCode::Timeout);
    assert!(store.snapshot().unwrap().is_some());
}

struct TimeoutTransport;

struct FailingMutationStore;

impl SessionStore for FailingMutationStore {
    fn load_versioned(&self) -> Result<VersionedSession> {
        Ok(VersionedSession {
            snapshot: None,
            revision: 0,
        })
    }

    fn compare_exchange(
        &self,
        _expected_revision: u64,
        _replacement: Option<&SessionSnapshot>,
    ) -> Result<SessionMutation> {
        Err(UbaaError::new(
            ErrorCode::InternalError,
            ErrorKind::Internal,
            true,
            "fixture persistence failure",
        ))
    }
}

#[async_trait]
impl HttpTransport for TimeoutTransport {
    async fn execute(&self, _request: HttpRequest) -> Result<HttpResponse> {
        Err(UbaaError::new(
            ErrorCode::Timeout,
            ErrorKind::Network,
            true,
            "fixture timeout",
        ))
    }
}
