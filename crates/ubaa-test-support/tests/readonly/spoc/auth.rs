use std::time::Duration;

use ubaa_core::facade::testing::{
    DualSessionSnapshot, FileSessionStore, GatewayProbe, RouteConfig, RouteSessionSnapshot,
    SessionSnapshot, StoredCookie,
};
use ubaa_core::facade::{ConnectionMode, ErrorCode, NetworkState, RouteClient, UbaaClient};

use crate::common::{SpocTransport, redirect, redirect_from, response, session_store_with};

#[derive(Clone, Copy)]
struct UnknownGatewayProbe;

impl GatewayProbe for UnknownGatewayProbe {
    fn probe(&self, _budget: Duration) -> NetworkState {
        NetworkState::Unknown
    }
}

#[tokio::test]
async fn spoc_business_authentication_failure_refreshes_login_once() {
    let cas = "https://spoc.buaa.edu.cn/spocnewht/cas";
    let first_token_url = "https://spoc.buaa.edu.cn/spocnew/cas?token=expired-token";
    let fresh_token_url = "https://spoc.buaa.edu.cn/spocnew/cas?token=fresh-token";
    let login_url = "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin";
    let term_url = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne";
    let courses_url = "https://spoc.buaa.edu.cn/spocnewht/jxkj/queryKclb?kcmc=&xnxq=2025-20262";
    let assignments_url = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage";
    let transport = SpocTransport::new([
        (cas.into(), redirect(first_token_url)),
        (
            login_url.into(),
            response(200, login_url, r#"{"code":200,"content":{"jsdm":"01"}}"#),
        ),
        (
            term_url.into(),
            response(200, "https://sso.buaa.edu.cn/login?service=fixture", ""),
        ),
        (cas.into(), redirect(fresh_token_url)),
        (
            login_url.into(),
            response(200, login_url, r#"{"code":200,"content":{"jsdm":"01"}}"#),
        ),
        (
            term_url.into(),
            response(
                200,
                term_url,
                r#"{"code":200,"content":{"dqxq":"Spring","mrxq":"2025-20262"}}"#,
            ),
        ),
        (
            courses_url.into(),
            response(200, courses_url, r#"{"code":200,"content":[]}"#),
        ),
        (
            assignments_url.into(),
            response(
                200,
                assignments_url,
                r#"{"code":200,"content":{"pageNum":1,"pageSize":15,"pages":1,"hasNextPage":false,"list":[]}}"#,
            ),
        ),
    ]);
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("spoc-refresh-fixture"),
    )
    .unwrap();

    let result = client
        .spoc_assignments()
        .await
        .expect("one business authentication refresh must succeed");

    assert!(result.data.assignments.is_empty());
    assert_eq!(result.data.term_code, "2025-20262");
}

#[tokio::test]
async fn spoc_business_sso_location_refreshes_only_the_failed_call() {
    let cas = "https://spoc.buaa.edu.cn/spocnewht/cas";
    let first_token_url = "https://spoc.buaa.edu.cn/spocnew/cas?token=expired-token";
    let fresh_token_url = "https://spoc.buaa.edu.cn/spocnew/cas?token=fresh-token";
    let login_url = "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin";
    let term_url = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne";
    let courses_url = "https://spoc.buaa.edu.cn/spocnewht/jxkj/queryKclb?kcmc=&xnxq=2025-20262";
    let assignments_url = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage";
    let sso = "https://sso.buaa.edu.cn/login?service=fixture";
    let transport = SpocTransport::new([
        (cas.into(), redirect(first_token_url)),
        (
            login_url.into(),
            response(200, login_url, r#"{"code":200,"content":{"jsdm":"01"}}"#),
        ),
        (term_url.into(), redirect_from(term_url, sso)),
        (cas.into(), redirect(fresh_token_url)),
        (
            login_url.into(),
            response(200, login_url, r#"{"code":200,"content":{"jsdm":"01"}}"#),
        ),
        (
            term_url.into(),
            response(
                200,
                term_url,
                r#"{"code":200,"content":{"dqxq":"Spring","mrxq":"2025-20262"}}"#,
            ),
        ),
        (
            courses_url.into(),
            response(200, courses_url, r#"{"code":200,"content":[]}"#),
        ),
        (
            assignments_url.into(),
            response(
                200,
                assignments_url,
                r#"{"code":200,"content":{"pageNum":1,"pageSize":15,"pages":1,"hasNextPage":false,"list":[]}}"#,
            ),
        ),
    ]);
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("spoc-location-refresh-fixture"),
    )
    .unwrap();

    let result = client
        .spoc_assignments()
        .await
        .expect("a raw SSO Location must refresh the route credential once");

    assert!(result.data.assignments.is_empty());
    observed.assert_exhausted();
    assert_eq!(
        observed
            .requests()
            .iter()
            .filter(|request| request.url == term_url)
            .count(),
        2
    );
    assert_eq!(
        observed
            .requests()
            .iter()
            .filter(|request| request.url == courses_url)
            .count(),
        1
    );
}

#[tokio::test]
async fn spoc_permission_failure_is_not_retried_as_authentication() {
    let cas = "https://spoc.buaa.edu.cn/spocnewht/cas";
    let token_url = "https://spoc.buaa.edu.cn/spocnew/cas?token=test-token";
    let login_url = "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin";
    let term_url = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne";
    let transport = SpocTransport::new([
        (cas.into(), redirect(token_url)),
        (
            login_url.into(),
            response(200, login_url, r#"{"code":200,"content":{"jsdm":"01"}}"#),
        ),
        (
            term_url.into(),
            response(
                200,
                term_url,
                r#"{"code":403,"msg":"无权限查看该作业","content":null}"#,
            ),
        ),
    ]);
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("spoc-permission-fixture"),
    )
    .unwrap();

    let error = client
        .spoc_assignments()
        .await
        .expect_err("permission denial must be returned without replaying the request");

    assert_eq!(error.code, ErrorCode::UpstreamChanged);
    observed.assert_exhausted();
    assert_eq!(
        observed
            .requests()
            .iter()
            .filter(|request| request.url == cas)
            .count(),
        1
    );
}

#[tokio::test]
async fn spoc_page_auth_refresh_retries_only_the_failed_business_call() {
    let cas = "https://spoc.buaa.edu.cn/spocnewht/cas";
    let first_token_url = "https://spoc.buaa.edu.cn/spocnew/cas?token=expired-token";
    let fresh_token_url = "https://spoc.buaa.edu.cn/spocnew/cas?token=fresh-token";
    let login_url = "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin";
    let term_url = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne";
    let courses_url = "https://spoc.buaa.edu.cn/spocnewht/jxkj/queryKclb?kcmc=&xnxq=2025-20262";
    let assignments_url = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage";
    let transport = SpocTransport::new([
        (cas.into(), redirect(first_token_url)),
        (
            login_url.into(),
            response(200, login_url, r#"{"code":200,"content":{"jsdm":"01"}}"#),
        ),
        (
            term_url.into(),
            response(
                200,
                term_url,
                r#"{"code":200,"content":{"dqxq":"Spring","mrxq":"2025-20262"}}"#,
            ),
        ),
        (
            courses_url.into(),
            response(200, courses_url, r#"{"code":200,"content":[]}"#),
        ),
        (
            assignments_url.into(),
            response(
                200,
                assignments_url,
                r#"{"code":401,"msg":"token expired","content":null}"#,
            ),
        ),
        (cas.into(), redirect(fresh_token_url)),
        (
            login_url.into(),
            response(200, login_url, r#"{"code":200,"content":{"jsdm":"01"}}"#),
        ),
        (
            assignments_url.into(),
            response(
                200,
                assignments_url,
                r#"{"code":200,"content":{"pageNum":1,"pageSize":15,"pages":1,"hasNextPage":false,"list":[]}}"#,
            ),
        ),
    ]);
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("spoc-page-refresh-fixture"),
    )
    .unwrap();

    let result = client
        .spoc_assignments()
        .await
        .expect("the failed page should be retried after one credential refresh");

    assert!(result.data.assignments.is_empty());
    observed.assert_exhausted();
    let requests = observed.requests();
    assert_eq!(
        requests
            .iter()
            .filter(|request| request.url == term_url)
            .count(),
        1
    );
    assert_eq!(
        requests
            .iter()
            .filter(|request| request.url == courses_url)
            .count(),
        1
    );
}

#[tokio::test]
async fn spoc_second_business_authentication_failure_preserves_a_valid_primary_session() {
    let cas = "https://spoc.buaa.edu.cn/spocnewht/cas";
    let first_token_url = "https://spoc.buaa.edu.cn/spocnew/cas?token=expired-token";
    let fresh_token_url = "https://spoc.buaa.edu.cn/spocnew/cas?token=fresh-token";
    let login_url = "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin";
    let term_url = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne";
    let status_url = "https://uc.buaa.edu.cn/api/uc/status";
    let profile = r#"{"code":0,"data":{"name":"Fixture User","schoolid":"TEST-0001","username":"fixture-user"}}"#;
    let transport = SpocTransport::new([
        (cas.into(), redirect(first_token_url)),
        (
            login_url.into(),
            response(200, login_url, r#"{"code":200,"content":{"jsdm":"01"}}"#),
        ),
        (
            term_url.into(),
            response(
                200,
                term_url,
                r#"{"code":401,"msg":"token expired","content":null}"#,
            ),
        ),
        (cas.into(), redirect(fresh_token_url)),
        (
            login_url.into(),
            response(200, login_url, r#"{"code":200,"content":{"jsdm":"01"}}"#),
        ),
        (
            term_url.into(),
            response(
                200,
                term_url,
                r#"{"code":401,"msg":"token expired","content":null}"#,
            ),
        ),
        (status_url.into(), response(200, status_url, profile)),
    ]);
    let observed = transport.clone();
    let store = session_store_with("spoc-double-auth-valid-fixture");
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, transport, store.clone()).unwrap();

    let error = client
        .spoc_assignments()
        .await
        .expect_err("exhausted SPOC auth must remain a business failure when UC is valid");

    assert_eq!(error.code, ErrorCode::UpstreamUnavailable);
    assert!(error.retryable);
    assert!(store.snapshot().unwrap().is_some());
    observed.assert_exhausted();
    assert_eq!(
        observed
            .requests()
            .iter()
            .filter(|request| request.url == cas)
            .count(),
        2
    );
}

#[tokio::test]
async fn spoc_second_business_authentication_failure_clears_an_invalid_primary_session() {
    let cas = "https://spoc.buaa.edu.cn/spocnewht/cas";
    let login = "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin";
    let term = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne";
    let status = "https://uc.buaa.edu.cn/api/uc/status";
    let transport = SpocTransport::new([
        (
            cas.into(),
            redirect("https://spoc.buaa.edu.cn/spocnew/cas?token=expired"),
        ),
        (
            login.into(),
            response(200, login, r#"{"code":200,"content":{"jsdm":"01"}}"#),
        ),
        (
            term.into(),
            response(
                200,
                term,
                r#"{"code":401,"msg":"token expired","content":null}"#,
            ),
        ),
        (
            cas.into(),
            redirect("https://spoc.buaa.edu.cn/spocnew/cas?token=fresh"),
        ),
        (
            login.into(),
            response(200, login, r#"{"code":200,"content":{"jsdm":"01"}}"#),
        ),
        (
            term.into(),
            response(
                200,
                term,
                r#"{"code":401,"msg":"token expired","content":null}"#,
            ),
        ),
        (status.into(), response(401, status, "")),
    ]);
    let observed = transport.clone();
    let store = session_store_with("spoc-double-auth-invalid-fixture");
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, transport, store.clone()).unwrap();

    let error = client
        .spoc_assignments()
        .await
        .expect_err("UC rejected the primary session");

    assert_eq!(error.code, ErrorCode::AuthenticationRequired);
    assert!(store.snapshot().unwrap().is_none());
    observed.assert_exhausted();
}

#[tokio::test]
async fn spoc_invalid_primary_session_clears_only_the_selected_route_slot() {
    let cas = "https://spoc.buaa.edu.cn/spocnewht/cas";
    let login = "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin";
    let term = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne";
    let status = "https://uc.buaa.edu.cn/api/uc/status";
    let direct = SpocTransport::new([
        (
            cas.into(),
            redirect("https://spoc.buaa.edu.cn/spocnew/cas?token=expired"),
        ),
        (
            login.into(),
            response(200, login, r#"{"code":200,"content":{"jsdm":"01"}}"#),
        ),
        (
            term.into(),
            response(
                200,
                term,
                r#"{"code":401,"msg":"token expired","content":null}"#,
            ),
        ),
        (
            cas.into(),
            redirect("https://spoc.buaa.edu.cn/spocnew/cas?token=fresh"),
        ),
        (
            login.into(),
            response(200, login, r#"{"code":200,"content":{"jsdm":"01"}}"#),
        ),
        (
            term.into(),
            response(
                200,
                term,
                r#"{"code":401,"msg":"token expired","content":null}"#,
            ),
        ),
        (status.into(), response(401, status, "")),
    ]);
    let observed = direct.clone();
    let root = std::env::temp_dir().join(format!(
        "ubaa-spoc-selected-route-invalidation-{}",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
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
            Some(slot(ConnectionMode::Direct, "direct-fixture")),
            Some(slot(ConnectionMode::WebVpn, "webvpn-fixture")),
        ))
        .unwrap();
    let config = RouteConfig::parse("[route]\ndefault = 'direct'\n").unwrap();
    let mut client = UbaaClient::with_routing(
        direct,
        SpocTransport::new([]),
        store.clone(),
        config,
        UnknownGatewayProbe,
    )
    .unwrap();

    let error = client
        .spoc_assignments()
        .await
        .expect_err("UC rejected Direct");

    assert_eq!(error.error.code, ErrorCode::AuthenticationRequired);
    let persisted = store.load_dual().unwrap().expect("remaining WebVPN slot");
    assert!(persisted.direct().is_none());
    assert!(persisted.webvpn().is_some());
    observed.assert_exhausted();
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn spoc_second_business_authentication_failure_preserves_session_when_uc_is_unavailable() {
    let cas = "https://spoc.buaa.edu.cn/spocnewht/cas";
    let login = "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin";
    let term = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne";
    let status = "https://uc.buaa.edu.cn/api/uc/status";
    let transport = SpocTransport::new([
        (
            cas.into(),
            redirect("https://spoc.buaa.edu.cn/spocnew/cas?token=expired"),
        ),
        (
            login.into(),
            response(200, login, r#"{"code":200,"content":{"jsdm":"01"}}"#),
        ),
        (
            term.into(),
            response(
                200,
                term,
                r#"{"code":401,"msg":"token expired","content":null}"#,
            ),
        ),
        (
            cas.into(),
            redirect("https://spoc.buaa.edu.cn/spocnew/cas?token=fresh"),
        ),
        (
            login.into(),
            response(200, login, r#"{"code":200,"content":{"jsdm":"01"}}"#),
        ),
        (
            term.into(),
            response(
                200,
                term,
                r#"{"code":401,"msg":"token expired","content":null}"#,
            ),
        ),
        (status.into(), response(503, status, "")),
    ]);
    let observed = transport.clone();
    let store = session_store_with("spoc-double-auth-unavailable-fixture");
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, transport, store.clone()).unwrap();

    let error = client
        .spoc_assignments()
        .await
        .expect_err("UC availability is inconclusive");

    assert_eq!(error.code, ErrorCode::UpstreamUnavailable);
    assert!(error.retryable);
    assert!(store.snapshot().unwrap().is_some());
    observed.assert_exhausted();
}

#[tokio::test]
async fn spoc_malformed_json_with_token_text_is_not_retried_as_authentication() {
    let cas = "https://spoc.buaa.edu.cn/spocnewht/cas";
    let login = "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin";
    let term = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne";
    let transport = SpocTransport::new([
        (
            cas.into(),
            redirect("https://spoc.buaa.edu.cn/spocnew/cas?token=fixture"),
        ),
        (
            login.into(),
            response(200, login, r#"{"code":200,"content":{"jsdm":"01"}}"#),
        ),
        (
            term.into(),
            response(200, term, r#"{"code":200,"content":"token""#),
        ),
    ]);
    let observed = transport.clone();
    let store = session_store_with("spoc-malformed-token-fixture");
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, transport, store.clone()).unwrap();

    let error = client
        .spoc_assignments()
        .await
        .expect_err("malformed JSON must be a parse error");

    assert_eq!(error.code, ErrorCode::ParseError);
    assert!(store.snapshot().unwrap().is_some());
    observed.assert_exhausted();
    assert_eq!(
        observed.requests().len(),
        3,
        "parse failures must not trigger SPOC relogin"
    );
}

#[tokio::test]
async fn spoc_cas_login_auth_shapes_validate_the_primary_session_before_classification() {
    let cas = "https://spoc.buaa.edu.cn/spocnewht/cas";
    let login = "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin";
    let status = "https://uc.buaa.edu.cn/api/uc/status";
    let profile = r#"{"code":0,"data":{"name":"Fixture User","schoolid":"TEST-0001","username":"fixture-user"}}"#;
    let cases = [
        redirect_from(login, "https://sso.buaa.edu.cn/login?service=fixture"),
        response(200, login, r#"{"code":200,"content":null}"#),
        response(200, login, r#"{"code":200,"content":{}}"#),
    ];

    for (index, cas_login_response) in cases.into_iter().enumerate() {
        let transport = SpocTransport::new([
            (
                cas.into(),
                redirect("https://spoc.buaa.edu.cn/spocnew/cas?token=fixture"),
            ),
            (login.into(), cas_login_response),
            (status.into(), response(200, status, profile)),
        ]);
        let observed = transport.clone();
        let store = session_store_with(&format!("spoc-cas-shape-{index}"));
        let mut client =
            RouteClient::with_transport(ConnectionMode::Direct, transport, store.clone()).unwrap();

        let error = client
            .spoc_assignments()
            .await
            .expect_err("SPOC CAS login shape must fail");

        assert_eq!(error.code, ErrorCode::UpstreamUnavailable);
        assert!(store.snapshot().unwrap().is_some());
        observed.assert_exhausted();
    }
}
