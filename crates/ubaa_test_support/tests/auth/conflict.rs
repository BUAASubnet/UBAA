use ubaa_core::facade::testing::{
    DualSessionSnapshot, FileSessionStore, HttpMethod, RouteSessionSnapshot, SessionMutation,
    SessionSnapshot, SessionStore, StoredCookie, VersionedSession, to_webvpn_url,
};
use ubaa_core::facade::{
    ConnectionMode, DualLoginInput, ErrorCode, LoginReadiness, Result, RouteClient,
    RouteLoginState, SecretValue, UbaaClient,
};
use ubaa_test_support::{ExpectedRequest, MemorySessionStore, MockTransport, auth_fixture};

use crate::common::{
    basic_direct_transport, login_input, login_page, persisted_store, redirect, response,
    set_cookie,
};

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

    let result = RouteClient::with_transport(ConnectionMode::Direct, MockTransport::new([]), store);
    let Err(error) = result else {
        panic!("a stale mode-mismatch clear unexpectedly succeeded");
    };

    assert_eq!(error.code, ErrorCode::InternalError);
    assert!(error.retryable);
    assert_eq!(inner.snapshot().unwrap(), Some(newer));
}

#[tokio::test]
async fn dual_login_keeps_direct_slot_when_webvpn_route_fails() {
    let (direct_transport, _unused_memory_store) = basic_direct_transport();
    let root = std::env::temp_dir().join(format!("ubaa-dual-login-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let file_store = FileSessionStore::new(&root).unwrap();
    let mut client =
        UbaaClient::with_transports(direct_transport, MockTransport::new([]), file_store.clone())
            .unwrap();

    let outcome = client
        .login(DualLoginInput {
            username: "fixture-user".into(),
            password: SecretValue::new("fixture-password"),
        })
        .await
        .unwrap();

    assert_eq!(outcome.readiness, LoginReadiness::Partial);
    assert_eq!(outcome.routes.len(), 2);
    assert_eq!(outcome.routes[0].route, ConnectionMode::Direct);
    assert_eq!(outcome.routes[0].state, RouteLoginState::Ready);
    assert_eq!(outcome.routes[1].route, ConnectionMode::WebVpn);
    assert_eq!(outcome.routes[1].state, RouteLoginState::Failed);
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
    let mut client = UbaaClient::with_transports(
        direct_transport,
        basic_webvpn_transport(),
        file_store.clone(),
    )
    .unwrap();

    let outcome = client
        .login(DualLoginInput {
            username: "fixture-user".into(),
            password: SecretValue::new("fixture-password"),
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
async fn stale_aggregate_logout_preserves_both_newer_slots() {
    let root = std::env::temp_dir().join(format!("ubaa-dual-stale-logout-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store.save_dual(&dual_snapshot("initial")).unwrap();
    let mut client = UbaaClient::with_transports(
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
    let mut client = UbaaClient::with_transports(
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
        UbaaClient::with_transports(direct, webvpn, FileSessionStore::new(&root).unwrap()).unwrap();

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
    let mut client = UbaaClient::with_transports(
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
        UbaaClient::with_transports(direct_transport, webvpn_transport, store.clone()).unwrap();
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
            .all(|route| route.state == RouteLoginState::Failed)
    );
    let repeated_login = client
        .login(DualLoginInput {
            username: "fixture-user".into(),
            password: SecretValue::new("fixture-password"),
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
async fn persistence_conflict_clears_pending_login_workflow_state() {
    let login = "https://sso.buaa.edu.cn/login";
    let page = r#"<form id="fm1"><input type="hidden" name="execution" value="e-cap"><input name="username"><input name="password"></form>"#;
    let transport = MockTransport::new([
        ExpectedRequest::new(HttpMethod::Get, login, response(200, login, page)),
        ExpectedRequest::new(HttpMethod::Get, login, response(503, login, Vec::new())),
    ]);
    let observer = transport.clone();
    let store = MemorySessionStore::new();
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, transport, store.clone()).unwrap();

    client.prepare_login().await.unwrap();
    store.clear().unwrap();
    let conflict = client.login(login_input()).await.unwrap_err();
    assert_eq!(conflict.code, ErrorCode::InternalError);
    assert!(conflict.retryable);
    assert_eq!(observer.requests().unwrap().len(), 1);

    let next = client.login(login_input()).await.unwrap_err();
    assert_eq!(next.code, ErrorCode::UpstreamUnavailable);
    observer.assert_exhausted().unwrap();
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
        RouteClient::with_transport(ConnectionMode::Direct, transport, store.clone()).unwrap();
    store.clear().unwrap();

    let error = stale_client.auth_status().await.unwrap_err();

    assert_eq!(error.code, ErrorCode::InternalError);
    assert!(error.retryable);
    assert_eq!(error.message, "local session changed in another process");
    assert!(!error.message.contains("fixture-cookie"));
    assert!(store.snapshot().unwrap().is_none());
    let next = stale_client.auth_status().await.unwrap_err();
    assert_eq!(next.code, ErrorCode::AuthenticationRequired);
    // 会话修订在请求前已被发现，后续无会话状态也不得再产生网络请求。
    assert_eq!(observer.requests().unwrap().len(), 0);
}

#[tokio::test]
async fn stale_logout_cannot_clear_a_newer_persisted_session() {
    let store = persisted_store();
    let mut stale_client = RouteClient::with_transport(
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

struct ReplaceAfterLoadStore {
    inner: MemorySessionStore,
    replacement: SessionSnapshot,
}

impl SessionStore for ReplaceAfterLoadStore {
    fn load_versioned(&self) -> Result<VersionedSession> {
        let loaded = self.inner.load_versioned()?;
        self.inner.save(&self.replacement)?;
        Ok(loaded)
    }

    fn compare_exchange(
        &self,
        expected_revision: u64,
        replacement: Option<&SessionSnapshot>,
    ) -> Result<SessionMutation> {
        self.inner.compare_exchange(expected_revision, replacement)
    }
}
