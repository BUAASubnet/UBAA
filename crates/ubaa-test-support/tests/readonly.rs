use std::collections::{BTreeMap, HashMap, VecDeque};
use std::fmt::Write as _;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use async_trait::async_trait;
use ubaa_core::domain::{ConnectionMode, JudgeAssignmentKey, LoginInput, SecretValue};
use ubaa_core::error::{ErrorCode, ErrorKind, Result, UbaaError};
use ubaa_core::facade::RouteClient;
use ubaa_core::ports::{HttpMethod, HttpRequest, HttpResponse, HttpTransport};
use ubaa_core::session::{SessionSnapshot, SessionStore, StoredCookie};
use ubaa_test_support::{ExpectedRequest, MemorySessionStore, MockTransport, readonly_fixture};

const FROZEN_CLASSROOM_USER_AGENT: &str = "Mozilla/5.0 (Linux; Android 16; 24031PN0DC Build/BP2A.250605.031.A3; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/138.0.7204.180 Mobile Safari/537.36 XWEB/1380275 MMWEBSDK/20230806 MMWEBID/4102 wxworklocal/3.2.200 wwlocal/3.2.200 wxwork/4.0.0 appname/wxworklocal-customized wxworklocal-device-code/195ef5586d7d3c2808fcbea32d77c0d4 MicroMessenger/7.0.1 appScheme/wxworklocalcustomized Language/zh_CN ColorScheme/Light WXWorklocalClientType/Android Brand/xiaomi";

#[derive(Clone)]
struct SpocTransport {
    responses: Arc<Mutex<VecDeque<(String, HttpResponse)>>>,
    requests: Arc<Mutex<Vec<HttpRequest>>>,
}

impl SpocTransport {
    fn new(responses: impl IntoIterator<Item = (String, HttpResponse)>) -> Self {
        Self {
            responses: Arc::new(Mutex::new(responses.into_iter().collect())),
            requests: Arc::new(Mutex::new(Vec::new())),
        }
    }

    fn requests(&self) -> Vec<HttpRequest> {
        self.requests.lock().expect("request log lock").clone()
    }

    fn assert_exhausted(&self) {
        assert!(
            self.responses
                .lock()
                .expect("response script lock")
                .is_empty(),
            "SPOC response script has unused entries"
        );
    }
}

#[async_trait]
impl HttpTransport for SpocTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let (expected_url, response) = self
            .responses
            .lock()
            .expect("response script lock")
            .pop_front()
            .expect("SPOC request script exhausted");
        assert_eq!(request.url, expected_url);
        self.requests
            .lock()
            .expect("request log lock")
            .push(request);
        Ok(response)
    }
}

fn response(status: u16, final_url: &str, body: &str) -> HttpResponse {
    HttpResponse {
        status,
        final_url: final_url.into(),
        headers: BTreeMap::new(),
        body: body.as_bytes().to_vec(),
    }
}

fn redirect(location: &str) -> HttpResponse {
    redirect_from("https://spoc.buaa.edu.cn/spocnewht/cas", location)
}

fn redirect_from(current: &str, location: &str) -> HttpResponse {
    let mut headers = BTreeMap::new();
    headers.insert("Location".into(), vec![location.into()]);
    HttpResponse {
        status: 302,
        final_url: current.into(),
        headers,
        body: Vec::new(),
    }
}

fn session_store() -> MemorySessionStore {
    session_store_with("fixture")
}

fn session_store_with(cookie_value: &str) -> MemorySessionStore {
    session_store_for(ConnectionMode::Direct, cookie_value)
}

fn session_store_for(mode: ConnectionMode, cookie_value: &str) -> MemorySessionStore {
    let store = MemorySessionStore::new();
    store
        .save(&SessionSnapshot {
            mode,
            cookies: vec![StoredCookie::fixture("SID", cookie_value)],
            authenticated_at: 1,
            last_activity: 2,
        })
        .expect("seed session");
    store
}

#[tokio::test]
async fn schedule_and_exam_use_verified_requests_and_sanitized_fixtures() {
    let current_user = ubaa_core::features::schedule::CURRENT_USER_URL;
    let terms_url = ubaa_core::features::schedule::TERMS_URL;
    let weeks_url = format!(
        "{}?termCode=2025-2026-1",
        ubaa_core::features::schedule::WEEKS_URL
    );
    let weekly_schedule_url = ubaa_core::features::schedule::WEEK_URL;
    let today_url = format!(
        "{}?rq={}&lxdm=student",
        ubaa_core::features::schedule::TODAY_URL,
        shanghai_date()
    );
    let exam_url = format!(
        "{}?termCode=2025-2026-1",
        ubaa_core::features::schedule::EXAM_URL
    );
    let transport = MockTransport::new([
        expected_get(current_user, r#"{"user":"ok"}"#),
        expected_get(terms_url, readonly_fixture("schedule-terms.json").unwrap()),
        expected_get(current_user, r#"{"user":"ok"}"#),
        expected_get(&weeks_url, readonly_fixture("schedule-weeks.json").unwrap()),
        expected_get(current_user, r#"{"user":"ok"}"#),
        ExpectedRequest::new(
            HttpMethod::Post,
            weekly_schedule_url,
            response(
                200,
                weekly_schedule_url,
                readonly_fixture("schedule-week.json").unwrap(),
            ),
        ),
        expected_get(current_user, r#"{"user":"ok"}"#),
        expected_get(&today_url, readonly_fixture("schedule-today.json").unwrap()),
        expected_get(current_user, r#"{"user":"ok"}"#),
        expected_get(&exam_url, readonly_fixture("exam.json").unwrap()),
    ]);
    let observed = transport.clone();
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, transport, session_store()).unwrap();

    assert_eq!(client.schedule_terms().await.unwrap().data.len(), 1);
    assert_eq!(
        client
            .schedule_weeks("2025-2026-1")
            .await
            .unwrap()
            .data
            .len(),
        1
    );
    assert_eq!(
        client
            .schedule_week("2025-2026-1", 1)
            .await
            .unwrap()
            .data
            .arranged_list
            .len(),
        1
    );
    assert_eq!(client.schedule_today().await.unwrap().data.len(), 1);
    assert_eq!(
        client
            .exam_arrangement("2025-2026-1")
            .await
            .unwrap()
            .data
            .arranged
            .len(),
        1
    );

    observed.assert_exhausted().unwrap();
    let requests = observed.requests().unwrap();
    for index in [1, 3, 5, 7] {
        assert_eq!(
            requests[index].headers.get("Referer").map(String::as_str),
            Some("https://byxt.buaa.edu.cn/jwapp/sys/homeapp/index.html")
        );
        assert_eq!(
            requests[index]
                .headers
                .get("X-Requested-With")
                .map(String::as_str),
            Some("XMLHttpRequest")
        );
    }
    assert_eq!(
        requests[9].headers.get("Referer").map(String::as_str),
        Some("https://byxt.buaa.edu.cn/jwapp/sys/homeapp/home/index.html")
    );
    assert_eq!(
        String::from_utf8(requests[5].body.clone()).unwrap(),
        "termCode=2025-2026-1&type=week&week=1"
    );
    assert_eq!(
        requests[5].headers.get("Content-Type").map(String::as_str),
        Some("application/x-www-form-urlencoded")
    );
}

#[tokio::test]
async fn route_client_readonly_authentication_required_clears_the_selected_session() {
    let current_user = ubaa_core::features::schedule::CURRENT_USER_URL;
    let terms = ubaa_core::features::schedule::TERMS_URL;
    let transport = MockTransport::new([
        expected_get(current_user, r#"{"user":"ok"}"#),
        ExpectedRequest::new(HttpMethod::Get, terms, response(401, terms, "")),
    ]);
    let observed = transport.clone();
    let store = session_store();
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, transport, store.clone()).unwrap();

    let error = client
        .schedule_terms()
        .await
        .expect_err("an explicit read-only auth failure must invalidate this route");

    assert_eq!(error.code, ErrorCode::AuthenticationRequired);
    observed.assert_exhausted().unwrap();
    assert!(store.snapshot().unwrap().is_none());
}

#[tokio::test]
async fn schedule_activates_aas_after_the_portal_probe_requires_sso() {
    let current_user = ubaa_core::features::schedule::CURRENT_USER_URL;
    let terms = ubaa_core::features::schedule::TERMS_URL;
    let aas_login = "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fbyxt.buaa.edu.cn%2Fjwapp%2Fsys%2Fhomeapp%2Findex.do%3FcontextPath%3D%2Fjwapp";
    let aas_verify = "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/index.do?contextPath=/jwapp";
    let transport = MockTransport::new([
        ExpectedRequest::new(
            HttpMethod::Get,
            current_user,
            response(
                200,
                "https://sso.buaa.edu.cn/login?service=fixture",
                r#"<form><input name="execution" value="e1s1"></form>"#,
            ),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            aas_login,
            redirect_from(aas_login, aas_verify),
        ),
        expected_get(aas_verify, "AAS ready"),
        expected_get(current_user, r#"{"user":"ok"}"#),
        expected_get(terms, readonly_fixture("schedule-terms.json").unwrap()),
    ]);
    let observed = transport.clone();
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, transport, session_store()).unwrap();

    let result = client.schedule_terms().await.expect("AAS recovery");

    assert_eq!(result.data.len(), 1);
    observed.assert_exhausted().unwrap();
}

#[tokio::test]
async fn schedule_aas_recovery_stays_on_the_webvpn_gateway() {
    use ubaa_core::connection::to_webvpn_url;

    let direct_current_user = ubaa_core::features::schedule::CURRENT_USER_URL;
    let direct_terms = ubaa_core::features::schedule::TERMS_URL;
    let direct_aas_login = "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fbyxt.buaa.edu.cn%2Fjwapp%2Fsys%2Fhomeapp%2Findex.do%3FcontextPath%3D%2Fjwapp";
    let direct_aas_verify =
        "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/index.do?contextPath=/jwapp";
    let current_user = to_webvpn_url(direct_current_user).unwrap();
    let terms = to_webvpn_url(direct_terms).unwrap();
    let aas_login = to_webvpn_url(direct_aas_login).unwrap();
    let aas_verify = to_webvpn_url(direct_aas_verify).unwrap();
    let transport = MockTransport::new([
        ExpectedRequest::new(
            HttpMethod::Get,
            &current_user,
            response(
                200,
                &to_webvpn_url("https://sso.buaa.edu.cn/login?service=fixture").unwrap(),
                r#"<form><input name="execution" value="e1s1"></form>"#,
            ),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            &aas_login,
            redirect_from(&aas_login, direct_aas_verify),
        ),
        expected_get(&aas_verify, "AAS ready"),
        expected_get(&current_user, r#"{"user":"ok"}"#),
        expected_get(&terms, readonly_fixture("schedule-terms.json").unwrap()),
    ]);
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::WebVpn,
        transport,
        session_store_for(ConnectionMode::WebVpn, "webvpn-aas-recovery-fixture"),
    )
    .unwrap();

    let result = client.schedule_terms().await.expect("WebVPN AAS recovery");

    assert_eq!(result.data.len(), 1);
    observed.assert_exhausted().unwrap();
    assert!(
        observed
            .requests()
            .unwrap()
            .iter()
            .all(|request| request.url.starts_with("https://d.buaa.edu.cn/"))
    );
}

#[tokio::test]
async fn grades_use_verified_activation_form_and_sanitized_fixture() {
    let url = ubaa_core::features::grades::GRADES_URL;
    let transport = MockTransport::new([
        expected_get(url, readonly_fixture("grades-page.html").unwrap()),
        ExpectedRequest::new(
            HttpMethod::Post,
            url,
            response(200, url, readonly_fixture("grades.json").unwrap()),
        ),
    ]);
    let observed = transport.clone();
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, transport, session_store()).unwrap();

    let result = client.grades("2025-2026-1").await.unwrap();

    assert_eq!(result.data.grades.len(), 1);
    assert_eq!(
        result.data.grades[0].course_name.as_deref(),
        Some("Fixture Course")
    );
    assert_eq!(result.data.grades[0].score.as_deref(), Some("95"));
    observed.assert_exhausted().unwrap();
    let requests = observed.requests().unwrap();
    assert_eq!(requests[0].method, HttpMethod::Get);
    assert_eq!(requests[1].method, HttpMethod::Post);
    assert_eq!(
        String::from_utf8(requests[1].body.clone()).unwrap(),
        "xq=1&year=2025-2026"
    );
    assert_eq!(
        requests[1]
            .headers
            .get("X-Requested-With")
            .map(String::as_str),
        Some("XMLHttpRequest")
    );
    assert_eq!(
        requests[1].headers.get("Referer").map(String::as_str),
        Some(url)
    );
}

#[tokio::test]
async fn direct_and_webvpn_classroom_sync_state_is_route_local() {
    use ubaa_core::connection::to_webvpn_url;

    let direct_sync = ubaa_core::features::classroom::CLASSROOM_SYNC_URL;
    let direct_query = format!(
        "{}?xqid=1&floorid=&date=2026-04-20",
        ubaa_core::features::classroom::CLASSROOM_URL
    );
    let webvpn_sync = to_webvpn_url(direct_sync).unwrap();
    let webvpn_query = to_webvpn_url(&direct_query).unwrap();
    let direct_transport = MockTransport::new([
        expected_get(direct_sync, ""),
        expected_get(&direct_query, readonly_fixture("classroom.json").unwrap()),
        expected_get(&direct_query, readonly_fixture("classroom.json").unwrap()),
    ]);
    let webvpn_transport = MockTransport::new([
        expected_get(&webvpn_sync, ""),
        expected_get(&webvpn_query, readonly_fixture("classroom.json").unwrap()),
        expected_get(&webvpn_query, readonly_fixture("classroom.json").unwrap()),
    ]);
    let direct_observed = direct_transport.clone();
    let webvpn_observed = webvpn_transport.clone();
    let mut direct = RouteClient::with_transport(
        ConnectionMode::Direct,
        direct_transport,
        session_store_for(ConnectionMode::Direct, "direct-route-state"),
    )
    .unwrap();
    let mut webvpn = RouteClient::with_transport(
        ConnectionMode::WebVpn,
        webvpn_transport,
        session_store_for(ConnectionMode::WebVpn, "webvpn-route-state"),
    )
    .unwrap();

    direct.classroom_search(1, "2026-04-20").await.unwrap();
    webvpn.classroom_search(1, "2026-04-20").await.unwrap();
    direct.classroom_search(1, "2026-04-20").await.unwrap();
    webvpn.classroom_search(1, "2026-04-20").await.unwrap();

    direct_observed.assert_exhausted().unwrap();
    webvpn_observed.assert_exhausted().unwrap();
    assert_eq!(
        direct_observed
            .requests()
            .unwrap()
            .iter()
            .filter(|request| request.url == direct_sync)
            .count(),
        1
    );
    assert_eq!(
        webvpn_observed
            .requests()
            .unwrap()
            .iter()
            .filter(|request| request.url == webvpn_sync)
            .count(),
        1
    );
}

#[tokio::test]
async fn successful_login_replacement_clears_classroom_sync_state() {
    let sync = ubaa_core::features::classroom::CLASSROOM_SYNC_URL;
    let query = format!(
        "{}?xqid=1&floorid=&date=2026-04-20",
        ubaa_core::features::classroom::CLASSROOM_URL
    );
    let login = "https://sso.buaa.edu.cn/login";
    let activate =
        "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin";
    let status = "https://uc.buaa.edu.cn/api/uc/status";
    let userinfo = "https://uc.buaa.edu.cn/api/uc/userinfo";
    let profile = r#"{"code":0,"data":{"name":"Fixture User","schoolid":"TEST-0001","username":"fixture-user"}}"#;
    let transport = MockTransport::new([
        expected_get(sync, ""),
        expected_get(&query, readonly_fixture("classroom.json").unwrap()),
        ExpectedRequest::new(
            HttpMethod::Get,
            login,
            redirect_from(login, "/already-authenticated"),
        ),
        expected_get(activate, ""),
        ExpectedRequest::new(HttpMethod::Get, status, response(200, status, profile)),
        ExpectedRequest::new(HttpMethod::Get, userinfo, response(200, userinfo, profile)),
        expected_get(sync, ""),
        expected_get(&query, readonly_fixture("classroom.json").unwrap()),
    ]);
    let observed = transport.clone();
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, transport, session_store()).unwrap();

    client.classroom_search(1, "2026-04-20").await.unwrap();
    assert!(client.prepare_login().await.unwrap().is_none());
    client
        .login(LoginInput {
            username: "fixture-user".into(),
            password: SecretValue::new("fixture-password"),
            captcha: None,
        })
        .await
        .unwrap();
    client.classroom_search(1, "2026-04-20").await.unwrap();

    observed.assert_exhausted().unwrap();
    assert_eq!(
        observed
            .requests()
            .unwrap()
            .iter()
            .filter(|request| request.url == sync)
            .count(),
        2,
        "a successful session replacement must force a new Classroom sync"
    );
}

#[tokio::test]
async fn classroom_uses_verified_sync_headers_and_sanitized_fixture() {
    let sync_url = ubaa_core::features::classroom::CLASSROOM_SYNC_URL;
    let query_url = format!(
        "{}?xqid=1&floorid=&date=2026-04-20",
        ubaa_core::features::classroom::CLASSROOM_URL
    );
    let transport = MockTransport::new([
        expected_get(sync_url, ""),
        expected_get(&query_url, readonly_fixture("classroom.json").unwrap()),
        expected_get(&query_url, readonly_fixture("classroom.json").unwrap()),
    ]);
    let observed = transport.clone();
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, transport, session_store()).unwrap();

    let result = client.classroom_search(1, "2026-04-20").await.unwrap();
    let repeated = client.classroom_search(1, "2026-04-20").await.unwrap();

    assert_eq!(result.data.floors["Main"][0].name, "Fixture Room");
    assert_eq!(repeated.data.floors["Main"][0].name, "Fixture Room");
    observed.assert_exhausted().unwrap();
    let requests = observed.requests().unwrap();
    assert_eq!(requests.len(), 3, "one client synchronizes its route once");
    assert_eq!(
        requests[0].headers.get("User-Agent").map(String::as_str),
        Some(FROZEN_CLASSROOM_USER_AGENT)
    );
    assert_eq!(
        requests[1].headers.get("User-Agent").map(String::as_str),
        Some(FROZEN_CLASSROOM_USER_AGENT)
    );
    assert_eq!(
        requests[1]
            .headers
            .get("X-Requested-With")
            .map(String::as_str),
        Some("XMLHttpRequest")
    );
    assert_eq!(
        requests[1].headers.get("Accept").map(String::as_str),
        Some("application/json, text/javascript, */*; q=0.01")
    );
    assert_eq!(
        requests[1].headers.get("Referer").map(String::as_str),
        Some("https://app.buaa.edu.cn/site/classRoomQuery/index")
    );
}

#[tokio::test]
async fn classroom_sync_failure_is_best_effort_and_retried_later() {
    let sync_url = ubaa_core::features::classroom::CLASSROOM_SYNC_URL;
    let query_url = format!(
        "{}?xqid=1&floorid=&date=2026-04-20",
        ubaa_core::features::classroom::CLASSROOM_URL
    );
    let transport = MockTransport::new([
        ExpectedRequest::new(HttpMethod::Get, sync_url, response(503, sync_url, "")),
        expected_get(&query_url, readonly_fixture("classroom.json").unwrap()),
        expected_get(sync_url, ""),
        expected_get(&query_url, readonly_fixture("classroom.json").unwrap()),
    ]);
    let observed = transport.clone();
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, transport, session_store()).unwrap();

    client.classroom_search(1, "2026-04-20").await.unwrap();
    client.classroom_search(1, "2026-04-20").await.unwrap();

    observed.assert_exhausted().unwrap();
    assert_eq!(
        observed
            .requests()
            .unwrap()
            .iter()
            .filter(|request| request.url == sync_url)
            .count(),
        2,
        "a failed synchronization must remain retryable"
    );
}

#[tokio::test]
async fn classroom_query_does_not_follow_sso_redirect_and_clears_the_route_session() {
    let sync_url = ubaa_core::features::classroom::CLASSROOM_SYNC_URL;
    let query_url = format!(
        "{}?xqid=1&floorid=&date=2026-04-20",
        ubaa_core::features::classroom::CLASSROOM_URL
    );
    let transport = MockTransport::new([
        expected_get(sync_url, ""),
        ExpectedRequest::new(
            HttpMethod::Get,
            &query_url,
            redirect_from(
                &query_url,
                "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fapp.buaa.edu.cn",
            ),
        ),
    ]);
    let observed = transport.clone();
    let store = session_store();
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, transport, store.clone()).unwrap();

    let error = client
        .classroom_search(1, "2026-04-20")
        .await
        .expect_err("raw SSO Location must invalidate the selected route");

    assert_eq!(error.code, ErrorCode::AuthenticationRequired);
    assert_eq!(observed.requests().unwrap().len(), 2, "query is sent once");
    observed.assert_exhausted().unwrap();
    assert!(store.snapshot().unwrap().is_none());
}

#[tokio::test]
async fn classroom_unauthorized_and_login_html_clear_the_route_session() {
    let sync_url = ubaa_core::features::classroom::CLASSROOM_SYNC_URL;
    let query_url = format!(
        "{}?xqid=1&floorid=&date=2026-04-20",
        ubaa_core::features::classroom::CLASSROOM_URL
    );
    for query_response in [
        response(401, &query_url, ""),
        response(
            200,
            &query_url,
            "<!DOCTYPE html><html><input name=\"execution\"><title>fixture</title></html>",
        ),
    ] {
        let transport = MockTransport::new([
            expected_get(sync_url, ""),
            ExpectedRequest::new(HttpMethod::Get, &query_url, query_response),
        ]);
        let store = session_store();
        let mut client =
            RouteClient::with_transport(ConnectionMode::Direct, transport, store.clone()).unwrap();

        let error = client
            .classroom_search(1, "2026-04-20")
            .await
            .expect_err("explicit classroom expiry must invalidate the selected route");

        assert_eq!(error.code, ErrorCode::AuthenticationRequired);
        assert!(store.snapshot().unwrap().is_none());
    }
}

#[tokio::test]
async fn readonly_sso_final_url_is_classified_as_authentication_required() {
    let sync_url = ubaa_core::features::classroom::CLASSROOM_SYNC_URL;
    let query_url = format!(
        "{}?xqid=1&floorid=&date=2026-04-20",
        ubaa_core::features::classroom::CLASSROOM_URL
    );
    let transport = MockTransport::new([
        expected_get(sync_url, ""),
        ExpectedRequest::new(
            HttpMethod::Get,
            &query_url,
            HttpResponse::new(
                200,
                "https://sso.buaa.edu.cn/login?service=fixture",
                Vec::new(),
            ),
        ),
    ]);
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, transport, session_store()).unwrap();

    let error = client
        .classroom_search(1, "2026-04-20")
        .await
        .expect_err("SSO final URL must not be parsed as a business response");

    assert_eq!(error.code, ErrorCode::AuthenticationRequired);
}

#[tokio::test]
async fn readonly_input_validation_rejects_blank_terms_and_invalid_dates_before_network() {
    let transport = MockTransport::new([]);
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, transport, session_store()).unwrap();

    let term_error = client
        .schedule_weeks("  ")
        .await
        .expect_err("blank term must be rejected locally");
    assert_eq!(term_error.code, ErrorCode::InvalidInput);

    let date_error = client
        .classroom_search(1, "2026-ab-31")
        .await
        .expect_err("non-numeric date must be rejected locally");
    assert_eq!(date_error.code, ErrorCode::InvalidInput);

    let impossible_date = client
        .classroom_search(1, "2026-02-30")
        .await
        .expect_err("impossible calendar date must be rejected locally");
    assert_eq!(impossible_date.code, ErrorCode::InvalidInput);
}

#[tokio::test]
async fn webvpn_readonly_requests_and_referers_stay_on_gateway_route() {
    use ubaa_core::connection::to_webvpn_url;

    let current_user = to_webvpn_url(ubaa_core::features::schedule::CURRENT_USER_URL).unwrap();
    let terms = to_webvpn_url(ubaa_core::features::schedule::TERMS_URL).unwrap();
    let schedule_referer =
        to_webvpn_url("https://byxt.buaa.edu.cn/jwapp/sys/homeapp/index.html").unwrap();
    let schedule_transport = MockTransport::new([
        expected_get(&current_user, r#"{"user":"ok"}"#),
        expected_get(&terms, readonly_fixture("schedule-terms.json").unwrap()),
    ]);
    let schedule_observed = schedule_transport.clone();
    let mut schedule_client = RouteClient::with_transport(
        ConnectionMode::WebVpn,
        schedule_transport,
        session_store_for(ConnectionMode::WebVpn, "webvpn-schedule-fixture"),
    )
    .unwrap();
    schedule_client.schedule_terms().await.unwrap();
    schedule_observed.assert_exhausted().unwrap();
    for request in schedule_observed.requests().unwrap() {
        assert!(request.url.starts_with("https://d.buaa.edu.cn/"));
    }
    assert_eq!(
        schedule_observed.requests().unwrap()[0]
            .headers
            .get("Referer")
            .map(String::as_str),
        Some(schedule_referer.as_str())
    );
    assert_eq!(
        schedule_observed.requests().unwrap()[1]
            .headers
            .get("Referer")
            .map(String::as_str),
        Some(schedule_referer.as_str())
    );

    let sync = to_webvpn_url(ubaa_core::features::classroom::CLASSROOM_SYNC_URL).unwrap();
    let direct_query = format!(
        "{}?xqid=1&floorid=&date=2026-04-20",
        ubaa_core::features::classroom::CLASSROOM_URL
    );
    let query = to_webvpn_url(&direct_query).unwrap();
    let classroom_referer =
        to_webvpn_url("https://app.buaa.edu.cn/site/classRoomQuery/index").unwrap();
    let classroom_transport = MockTransport::new([
        expected_get(&sync, ""),
        expected_get(&query, readonly_fixture("classroom.json").unwrap()),
    ]);
    let classroom_observed = classroom_transport.clone();
    let mut classroom_client = RouteClient::with_transport(
        ConnectionMode::WebVpn,
        classroom_transport,
        session_store_for(ConnectionMode::WebVpn, "webvpn-classroom-fixture"),
    )
    .unwrap();
    classroom_client
        .classroom_search(1, "2026-04-20")
        .await
        .unwrap();
    classroom_observed.assert_exhausted().unwrap();
    for request in classroom_observed.requests().unwrap() {
        assert!(request.url.starts_with("https://d.buaa.edu.cn/"));
    }
    assert_eq!(
        classroom_observed.requests().unwrap()[1]
            .headers
            .get("Referer")
            .map(String::as_str),
        Some(classroom_referer.as_str())
    );

    let grades_url = to_webvpn_url(ubaa_core::features::grades::GRADES_URL).unwrap();
    let grades_transport = MockTransport::new([
        expected_get(&grades_url, readonly_fixture("grades-page.html").unwrap()),
        ExpectedRequest::new(
            HttpMethod::Post,
            &grades_url,
            response(200, &grades_url, readonly_fixture("grades.json").unwrap()),
        ),
    ]);
    let grades_observed = grades_transport.clone();
    let mut grades_client = RouteClient::with_transport(
        ConnectionMode::WebVpn,
        grades_transport,
        session_store_for(ConnectionMode::WebVpn, "webvpn-grades-fixture"),
    )
    .unwrap();
    grades_client.grades("2025-2026-1").await.unwrap();
    grades_observed.assert_exhausted().unwrap();
    for request in grades_observed.requests().unwrap() {
        assert!(request.url.starts_with("https://d.buaa.edu.cn/"));
    }
    assert_eq!(
        grades_observed.requests().unwrap()[1]
            .headers
            .get("Referer")
            .map(String::as_str),
        Some(grades_url.as_str())
    );
}

fn expected_get(url: &str, body: &str) -> ExpectedRequest {
    ExpectedRequest::new(HttpMethod::Get, url, response(200, url, body))
}

fn shanghai_date() -> String {
    let seconds = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 8 * 60 * 60;
    let z = i64::try_from(seconds / 86_400).unwrap() + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let mut year = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = mp + if mp < 10 { 3 } else { -9 };
    year += i64::from(month <= 2);
    format!("{year:04}-{month:02}-{day:02}")
}

#[tokio::test]
async fn spoc_list_follows_cas_and_maps_all_pages() {
    let cas = "https://spoc.buaa.edu.cn/spocnewht/cas";
    let token_url = "https://spoc.buaa.edu.cn/spocnew/cas?token=test-token";
    let transport = SpocTransport::new([
        (cas.into(), redirect(token_url)),
        (
            "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin".into(),
            response(
                200,
                "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin",
                r#"{"code":200,"content":{"jsdm":"01"}}"#,
            ),
        ),
        (
            "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne".into(),
            response(
                200,
                "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne",
                r#"{"code":200,"content":{"dqxq":"Spring","mrxq":"2025-20262"}}"#,
            ),
        ),
        (
            "https://spoc.buaa.edu.cn/spocnewht/jxkj/queryKclb?kcmc=&xnxq=2025-20262".into(),
            response(
                200,
                "https://spoc.buaa.edu.cn/spocnewht/jxkj/queryKclb?kcmc=&xnxq=2025-20262",
                r#"{"code":200,"content":[{"kcid":"course-1","kcmc":"Systems","skjs":"Teacher"},{"kcid":"course-2","kcmc":"Networks","skjs":"Another Teacher"}]}"#,
            ),
        ),
        (
            "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage".into(),
            response(
                200,
                "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage",
                readonly_fixture("spoc-page.json").unwrap(),
            ),
        ),
        (
            "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage".into(),
            response(
                200,
                "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage",
                r#"{"code":200,"content":{"pageNum":2,"pageSize":15,"pages":2,"hasNextPage":false,"list":[{"zyid":"a2","tjzt":"已做","zyjzsj":"2026-03-19T16:00:00.000+00:00","zymc":"Lab","zykssj":"2026-03-16T08:00:00.000+00:00","sskcid":"course-1","kcmc":"Systems","mf":"满分:100"}]}}"#,
            ),
        ),
    ]);
    let observed = transport.clone();
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, transport, session_store())
            .expect("client");

    let result = client.spoc_assignments().await.expect("SPOC list");
    assert_eq!(result.data.term_code, "2025-20262");
    assert_eq!(result.data.assignments.len(), 2);
    assert_eq!(result.data.assignments[0].assignment_id, "a2");
    assert_eq!(result.data.assignments[0].submission_status_text, "已提交");
    assert_eq!(result.data.assignments[1].course_name, "Systems");
    assert_eq!(
        result.data.assignments[1].teacher_name.as_deref(),
        Some("Teacher")
    );
    assert_eq!(
        result.data.assignments[1].due_time.as_deref(),
        Some("2026-03-31 23:59:59")
    );
    observed.assert_exhausted();
    let requests = observed.requests();
    assert_eq!(
        requests
            .iter()
            .filter(|request| {
                request.url == "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage"
            })
            .count(),
        2,
        "global pagination must not repeat for each course"
    );
    assert!(!requests[0].headers.contains_key("Accept"));
    assert_eq!(
        String::from_utf8(requests[1].body.clone()).unwrap(),
        r#"{"token":"test-token"}"#
    );
}

#[tokio::test]
async fn spoc_sequential_reads_reuse_one_route_owned_login() {
    let cas = "https://spoc.buaa.edu.cn/spocnewht/cas";
    let token_url = "https://spoc.buaa.edu.cn/spocnew/cas?token=reused-token";
    let login_url = "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin";
    let term_url = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne";
    let courses_url = "https://spoc.buaa.edu.cn/spocnewht/jxkj/queryKclb?kcmc=&xnxq=2025-20262";
    let assignments_url = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage";
    let term = r#"{"code":200,"content":{"dqxq":"Spring","mrxq":"2025-20262"}}"#;
    let empty_courses = r#"{"code":200,"content":[]}"#;
    let empty_page = r#"{"code":200,"content":{"pageNum":1,"pageSize":15,"pages":1,"hasNextPage":false,"list":[]}}"#;
    let transport = SpocTransport::new([
        (cas.into(), redirect(token_url)),
        (
            login_url.into(),
            response(200, login_url, r#"{"code":200,"content":{"jsdm":"01"}}"#),
        ),
        (term_url.into(), response(200, term_url, term)),
        (
            courses_url.into(),
            response(200, courses_url, empty_courses),
        ),
        (
            assignments_url.into(),
            response(200, assignments_url, empty_page),
        ),
        (term_url.into(), response(200, term_url, term)),
        (
            courses_url.into(),
            response(200, courses_url, empty_courses),
        ),
        (
            assignments_url.into(),
            response(200, assignments_url, empty_page),
        ),
    ]);
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("spoc-reuse-fixture"),
    )
    .unwrap();

    client.spoc_assignments().await.unwrap();
    client.spoc_assignments().await.unwrap();

    observed.assert_exhausted();
    assert_eq!(
        observed
            .requests()
            .iter()
            .filter(|request| request.url == login_url)
            .count(),
        1,
        "one route must reuse its established SPOC token and role"
    );
}

#[tokio::test]
async fn successful_primary_login_invalidates_the_cached_spoc_credential() {
    let cas = "https://spoc.buaa.edu.cn/spocnewht/cas";
    let spoc_login = "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin";
    let term = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne";
    let courses = "https://spoc.buaa.edu.cn/spocnewht/jxkj/queryKclb?kcmc=&xnxq=2025-20262";
    let assignments = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage";
    let primary_login = "https://sso.buaa.edu.cn/login";
    let activate =
        "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin";
    let status = "https://uc.buaa.edu.cn/api/uc/status";
    let userinfo = "https://uc.buaa.edu.cn/api/uc/userinfo";
    let profile = r#"{"code":0,"data":{"name":"Fixture User","schoolid":"TEST-0001","username":"fixture-user"}}"#;
    let term_body = r#"{"code":200,"content":{"dqxq":"Spring","mrxq":"2025-20262"}}"#;
    let empty_courses = r#"{"code":200,"content":[]}"#;
    let empty_page = r#"{"code":200,"content":{"pageNum":1,"pageSize":15,"pages":1,"hasNextPage":false,"list":[]}}"#;
    let transport = SpocTransport::new([
        (
            cas.into(),
            redirect("https://spoc.buaa.edu.cn/spocnew/cas?token=first-token"),
        ),
        (
            spoc_login.into(),
            response(200, spoc_login, r#"{"code":200,"content":{"jsdm":"01"}}"#),
        ),
        (term.into(), response(200, term, term_body)),
        (courses.into(), response(200, courses, empty_courses)),
        (assignments.into(), response(200, assignments, empty_page)),
        (
            primary_login.into(),
            redirect_from(primary_login, "/already-authenticated"),
        ),
        (activate.into(), response(200, activate, "")),
        (status.into(), response(200, status, profile)),
        (userinfo.into(), response(200, userinfo, profile)),
        (
            cas.into(),
            redirect("https://spoc.buaa.edu.cn/spocnew/cas?token=second-token"),
        ),
        (
            spoc_login.into(),
            response(200, spoc_login, r#"{"code":200,"content":{"jsdm":"02"}}"#),
        ),
        (term.into(), response(200, term, term_body)),
        (courses.into(), response(200, courses, empty_courses)),
        (assignments.into(), response(200, assignments, empty_page)),
    ]);
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("spoc-primary-relogin-fixture"),
    )
    .unwrap();

    client.spoc_assignments().await.unwrap();
    assert!(client.prepare_login().await.unwrap().is_none());
    client
        .login(LoginInput {
            username: "fixture-user".into(),
            password: SecretValue::new("fixture-password"),
            captcha: None,
        })
        .await
        .unwrap();
    client.spoc_assignments().await.unwrap();

    observed.assert_exhausted();
    assert_eq!(
        observed
            .requests()
            .iter()
            .filter(|request| request.url == spoc_login)
            .count(),
        2
    );
}

#[tokio::test]
async fn spoc_login_follows_the_bounded_direct_cas_chain() {
    let cas = "https://spoc.buaa.edu.cn/spocnewht/cas";
    let sso = "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fspoc.buaa.edu.cn";
    let service = "https://spoc.buaa.edu.cn/spocnewht/casLogin?ticket=fixture-ticket";
    let token = "https://spoc.buaa.edu.cn/spocnew/cas?token=chain-token";
    let login = "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin";
    let term = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne";
    let courses = "https://spoc.buaa.edu.cn/spocnewht/jxkj/queryKclb?kcmc=&xnxq=2025-20262";
    let assignments = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage";
    let transport = SpocTransport::new([
        (cas.into(), redirect_from(cas, sso)),
        (sso.into(), redirect_from(sso, service)),
        (service.into(), redirect_from(service, token)),
        (
            login.into(),
            response(200, login, r#"{"code":200,"content":{"jsdm":"01"}}"#),
        ),
        (
            term.into(),
            response(
                200,
                term,
                r#"{"code":200,"content":{"dqxq":"Spring","mrxq":"2025-20262"}}"#,
            ),
        ),
        (
            courses.into(),
            response(200, courses, r#"{"code":200,"content":[]}"#),
        ),
        (
            assignments.into(),
            response(
                200,
                assignments,
                r#"{"code":200,"content":{"pageNum":1,"pageSize":15,"pages":1,"hasNextPage":false,"list":[]}}"#,
            ),
        ),
    ]);
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("spoc-chain-fixture"),
    )
    .unwrap();

    client.spoc_assignments().await.unwrap();

    observed.assert_exhausted();
    assert_eq!(observed.requests().len(), 7);
}

#[tokio::test]
async fn spoc_webvpn_login_resolves_gateway_relative_redirects_without_double_encoding() {
    use ubaa_core::connection::to_webvpn_url;

    let cas = "https://spoc.buaa.edu.cn/spocnewht/cas";
    let sso = "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fspoc.buaa.edu.cn";
    let token = "https://spoc.buaa.edu.cn/spocnew/cas?token=webvpn-chain-token";
    let login = "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin";
    let term = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne";
    let courses = "https://spoc.buaa.edu.cn/spocnewht/jxkj/queryKclb?kcmc=&xnxq=2025-20262";
    let assignments = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage";
    let webvpn_cas = to_webvpn_url(cas).unwrap();
    let webvpn_sso = to_webvpn_url(sso).unwrap();
    let webvpn_token = to_webvpn_url(token).unwrap();
    let webvpn_login = to_webvpn_url(login).unwrap();
    let webvpn_term = to_webvpn_url(term).unwrap();
    let webvpn_courses = to_webvpn_url(courses).unwrap();
    let webvpn_assignments = to_webvpn_url(assignments).unwrap();
    let relative_sso = webvpn_sso
        .strip_prefix("https://d.buaa.edu.cn")
        .unwrap()
        .to_owned();
    let relative_token = webvpn_token
        .strip_prefix("https://d.buaa.edu.cn")
        .unwrap()
        .to_owned();
    let transport = SpocTransport::new([
        (
            webvpn_cas.clone(),
            redirect_from(&webvpn_cas, &relative_sso),
        ),
        (
            webvpn_sso.clone(),
            redirect_from(&webvpn_sso, &relative_token),
        ),
        (
            webvpn_login.clone(),
            response(
                200,
                &webvpn_login,
                r#"{"code":200,"content":{"jsdm":"01"}}"#,
            ),
        ),
        (
            webvpn_term.clone(),
            response(
                200,
                &webvpn_term,
                r#"{"code":200,"content":{"dqxq":"Spring","mrxq":"2025-20262"}}"#,
            ),
        ),
        (
            webvpn_courses.clone(),
            response(200, &webvpn_courses, r#"{"code":200,"content":[]}"#),
        ),
        (
            webvpn_assignments.clone(),
            response(
                200,
                &webvpn_assignments,
                r#"{"code":200,"content":{"pageNum":1,"pageSize":15,"pages":1,"hasNextPage":false,"list":[]}}"#,
            ),
        ),
    ]);
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::WebVpn,
        transport,
        session_store_for(ConnectionMode::WebVpn, "spoc-webvpn-chain-fixture"),
    )
    .unwrap();

    client.spoc_assignments().await.unwrap();

    observed.assert_exhausted();
    assert_eq!(observed.requests()[1].url, webvpn_sso);
}

#[tokio::test]
async fn direct_and_webvpn_clients_do_not_share_spoc_credentials() {
    use ubaa_core::connection::to_webvpn_url;

    let cas = "https://spoc.buaa.edu.cn/spocnewht/cas";
    let login_url = "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin";
    let term_url = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne";
    let courses_url = "https://spoc.buaa.edu.cn/spocnewht/jxkj/queryKclb?kcmc=&xnxq=2025-20262";
    let assignments_url = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage";
    let term = r#"{"code":200,"content":{"dqxq":"Spring","mrxq":"2025-20262"}}"#;
    let empty_courses = r#"{"code":200,"content":[]}"#;
    let empty_page = r#"{"code":200,"content":{"pageNum":1,"pageSize":15,"pages":1,"hasNextPage":false,"list":[]}}"#;
    let first_transport = SpocTransport::new([
        (
            cas.into(),
            redirect("https://spoc.buaa.edu.cn/spocnew/cas?token=first-token"),
        ),
        (
            login_url.into(),
            response(200, login_url, r#"{"code":200,"content":{"jsdm":"01"}}"#),
        ),
        (term_url.into(), response(200, term_url, term)),
        (
            courses_url.into(),
            response(200, courses_url, empty_courses),
        ),
        (
            assignments_url.into(),
            response(200, assignments_url, empty_page),
        ),
    ]);
    let webvpn_cas = to_webvpn_url(cas).unwrap();
    let webvpn_token =
        to_webvpn_url("https://spoc.buaa.edu.cn/spocnew/cas?token=second-token").unwrap();
    let webvpn_login = to_webvpn_url(login_url).unwrap();
    let webvpn_term = to_webvpn_url(term_url).unwrap();
    let webvpn_courses = to_webvpn_url(courses_url).unwrap();
    let webvpn_assignments = to_webvpn_url(assignments_url).unwrap();
    let second_transport = SpocTransport::new([
        (
            webvpn_cas.clone(),
            redirect_from(&webvpn_cas, &webvpn_token),
        ),
        (
            webvpn_login.clone(),
            response(
                200,
                &webvpn_login,
                r#"{"code":200,"content":{"jsdm":"02"}}"#,
            ),
        ),
        (webvpn_term.clone(), response(200, &webvpn_term, term)),
        (
            webvpn_courses.clone(),
            response(200, &webvpn_courses, empty_courses),
        ),
        (
            webvpn_assignments.clone(),
            response(200, &webvpn_assignments, empty_page),
        ),
    ]);
    let first_observed = first_transport.clone();
    let second_observed = second_transport.clone();
    let mut first = RouteClient::with_transport(
        ConnectionMode::Direct,
        first_transport,
        session_store_with("spoc-first-route-fixture"),
    )
    .unwrap();
    let mut second = RouteClient::with_transport(
        ConnectionMode::WebVpn,
        second_transport,
        session_store_for(ConnectionMode::WebVpn, "spoc-second-route-fixture"),
    )
    .unwrap();

    first.spoc_assignments().await.unwrap();
    second.spoc_assignments().await.unwrap();

    first_observed.assert_exhausted();
    second_observed.assert_exhausted();
    assert_eq!(
        first_observed.requests()[1]
            .headers
            .get("Token")
            .map(String::as_str),
        Some("Inco-first-token")
    );
    assert_eq!(
        second_observed.requests()[1]
            .headers
            .get("Token")
            .map(String::as_str),
        Some("Inco-second-token")
    );
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
async fn spoc_second_business_authentication_failure_stops_after_one_refresh() {
    let cas = "https://spoc.buaa.edu.cn/spocnewht/cas";
    let first_token_url = "https://spoc.buaa.edu.cn/spocnew/cas?token=expired-token";
    let fresh_token_url = "https://spoc.buaa.edu.cn/spocnew/cas?token=fresh-token";
    let login_url = "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin";
    let term_url = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne";
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
    ]);
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("spoc-double-auth-fixture"),
    )
    .unwrap();

    let error = client
        .spoc_assignments()
        .await
        .expect_err("a second recognized auth error must be returned unchanged");

    assert_eq!(error.code, ErrorCode::AuthenticationRequired);
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
async fn spoc_course_metadata_failure_still_reads_the_global_page() {
    let cas = "https://spoc.buaa.edu.cn/spocnewht/cas";
    let token_url = "https://spoc.buaa.edu.cn/spocnew/cas?token=test-token";
    let login_url = "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin";
    let term_url = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne";
    let courses_url = "https://spoc.buaa.edu.cn/spocnewht/jxkj/queryKclb?kcmc=&xnxq=2025-20262";
    let assignments_url = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage";
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
                r#"{"code":200,"content":{"dqxq":"Spring","mrxq":"2025-20262"}}"#,
            ),
        ),
        (
            courses_url.into(),
            response(503, courses_url, "temporarily unavailable"),
        ),
        (
            assignments_url.into(),
            response(
                200,
                assignments_url,
                r#"{"code":200,"content":{"pageNum":1,"pageSize":15,"pages":1,"hasNextPage":false,"list":[{"zyid":"a1","zymc":"Practice","sskcid":"course-1","mf":"满分:80"}]}}"#,
            ),
        ),
    ]);
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("spoc-metadata-failure-fixture"),
    )
    .unwrap();

    let result = client
        .spoc_assignments()
        .await
        .expect("metadata is optional enrichment");

    assert_eq!(result.data.assignments.len(), 1);
    assert_eq!(result.data.assignments[0].assignment_id, "a1");
    assert_eq!(result.data.assignments[0].course_name, "");
    observed.assert_exhausted();
    assert!(
        observed
            .requests()
            .iter()
            .any(|request| request.url == assignments_url),
        "the authoritative global page must still be requested"
    );
}

#[tokio::test]
async fn spoc_course_authentication_exhaustion_still_reads_the_global_page() {
    let cas = "https://spoc.buaa.edu.cn/spocnewht/cas";
    let first_token_url = "https://spoc.buaa.edu.cn/spocnew/cas?token=first-token";
    let fresh_token_url = "https://spoc.buaa.edu.cn/spocnew/cas?token=fresh-token";
    let login_url = "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin";
    let term_url = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne";
    let courses_url = "https://spoc.buaa.edu.cn/spocnewht/jxkj/queryKclb?kcmc=&xnxq=2025-20262";
    let assignments_url = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage";
    let auth_error = r#"{"code":401,"msg":"token expired","content":null}"#;
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
        (courses_url.into(), response(200, courses_url, auth_error)),
        (cas.into(), redirect(fresh_token_url)),
        (
            login_url.into(),
            response(200, login_url, r#"{"code":200,"content":{"jsdm":"01"}}"#),
        ),
        (courses_url.into(), response(200, courses_url, auth_error)),
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
        session_store_with("spoc-course-auth-fixture"),
    )
    .unwrap();

    let result = client
        .spoc_assignments()
        .await
        .expect("course metadata stays optional after its own auth retry is exhausted");

    assert!(result.data.assignments.is_empty());
    observed.assert_exhausted();
    assert!(
        observed
            .requests()
            .iter()
            .any(|request| request.url == assignments_url)
    );
}

#[tokio::test]
async fn spoc_detail_reads_submission_without_writing() {
    let cas = "https://spoc.buaa.edu.cn/spocnewht/cas";
    let token_url = "https://spoc.buaa.edu.cn/spocnew/cas?token=test-token";
    let detail_url = "https://spoc.buaa.edu.cn/spocnewht/kczy/queryKczyInfoByid?id=a1";
    let submission_url = "https://spoc.buaa.edu.cn/spocnewht/kczy/queryXsSubmitKczyInfo?kczyid=a1";
    let term_url = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne";
    let courses_url = "https://spoc.buaa.edu.cn/spocnewht/jxkj/queryKclb?kcmc=&xnxq=2025-20262";
    let assignments_url = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage";
    let transport = SpocTransport::new([
        (cas.into(), redirect(token_url)),
        (
            "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin".into(),
            response(
                200,
                "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin",
                r#"{"code":200,"content":{"jsdm":"01"}}"#,
            ),
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
            response(
                200,
                courses_url,
                r#"{"code":200,"content":[{"kcid":"course-1","kcmc":"Systems","skjs":"Teacher"}]}"#,
            ),
        ),
        (
            assignments_url.into(),
            response(
                200,
                assignments_url,
                r#"{"code":200,"content":{"pageNum":1,"pageSize":15,"pages":1,"hasNextPage":false,"list":[{"zyid":"a1","tjzt":"未做","zymc":"Practice","sskcid":"course-1","kcmc":"Systems","mf":"满分:0"}]}}"#,
            ),
        ),
        (
            detail_url.into(),
            response(
                200,
                detail_url,
                readonly_fixture("spoc-detail.json").unwrap(),
            ),
        ),
        (
            submission_url.into(),
            response(
                200,
                submission_url,
                r#"{"code":200,"content":{"tjzt":"已做","tjsj":"2026-03-30T10:00:00.000+00:00"}}"#,
            ),
        ),
    ]);
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, transport, session_store())
            .expect("client");

    let result = client.spoc_assignment("a1").await.expect("SPOC detail");
    assert_eq!(result.data.course_name, "Systems");
    assert_eq!(result.data.teacher_name.as_deref(), Some("Teacher"));
    assert_eq!(result.data.submission_status_text, "已提交");
    assert_eq!(
        result.data.content_plain_text.as_deref(),
        Some("Read only & safe")
    );
    assert_eq!(
        result.data.submitted_at.as_deref(),
        Some("2026-03-30 18:00:00")
    );
}

#[tokio::test]
async fn spoc_optional_submission_failure_preserves_summary_fallbacks() {
    let cas = "https://spoc.buaa.edu.cn/spocnewht/cas";
    let token_url = "https://spoc.buaa.edu.cn/spocnew/cas?token=test-token";
    let login_url = "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin";
    let term_url = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne";
    let courses_url = "https://spoc.buaa.edu.cn/spocnewht/jxkj/queryKclb?kcmc=&xnxq=2025-20262";
    let assignments_url = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage";
    let detail_url = "https://spoc.buaa.edu.cn/spocnewht/kczy/queryKczyInfoByid?id=a1";
    let submission_url = "https://spoc.buaa.edu.cn/spocnewht/kczy/queryXsSubmitKczyInfo?kczyid=a1";
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
                r#"{"code":200,"content":{"pageNum":1,"pageSize":15,"pages":1,"hasNextPage":false,"list":[{"zyid":"a1","tjzt":"未做","zymc":"Summary title","zykssj":"2026-03-01 08:00:00","zyjzsj":"2026-03-31 23:59:59","sskcid":"course-1","mf":"满分:80"}]}}"#,
            ),
        ),
        (
            detail_url.into(),
            response(
                200,
                detail_url,
                r#"{"code":200,"content":{"id":"a1","zymc":"","zynr":"<p>Safe</p>","sskcid":"course-1"}}"#,
            ),
        ),
        (
            submission_url.into(),
            response(503, submission_url, "temporarily unavailable"),
        ),
    ]);
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("spoc-optional-submission-fixture"),
    )
    .unwrap();

    let result = client
        .spoc_assignment("a1")
        .await
        .expect("submission is optional enrichment");

    assert_eq!(result.data.title, "Summary title");
    assert_eq!(result.data.score.as_deref(), Some("80"));
    assert_eq!(
        result.data.start_time.as_deref(),
        Some("2026-03-01 08:00:00")
    );
    assert_eq!(result.data.due_time.as_deref(), Some("2026-03-31 23:59:59"));
    assert_eq!(
        result.data.submission_status,
        ubaa_core::domain::SpocSubmissionStatus::Unsubmitted
    );
    observed.assert_exhausted();
}

#[tokio::test]
async fn judge_selects_courses_before_reading_assignment_details() {
    let login_url = "https://sso.buaa.edu.cn/login?service=http%3A%2F%2Fjudge.buaa.edu.cn%2F";
    let judge_home = "https://judge.buaa.edu.cn/";
    let courses_url = "https://judge.buaa.edu.cn/courselist.jsp?courseID=0";
    let select_url = "https://judge.buaa.edu.cn/courselist.jsp?courseID=1";
    let assignments_url = "https://judge.buaa.edu.cn/assignment/index.jsp";
    let detail_url = "https://judge.buaa.edu.cn/assignment/index.jsp?assignID=101";
    let transport = SpocTransport::new([
        (login_url.into(), redirect_from(login_url, judge_home)),
        (judge_home.into(), response(200, judge_home, "judge home")),
        (
            courses_url.into(),
            response(
                200,
                courses_url,
                readonly_fixture("judge-courses.html").unwrap(),
            ),
        ),
        (login_url.into(), redirect_from(login_url, judge_home)),
        (judge_home.into(), response(200, judge_home, "judge home")),
        (select_url.into(), response(200, select_url, "selected")),
        (
            assignments_url.into(),
            response(
                200,
                assignments_url,
                readonly_fixture("judge-assignments.html").unwrap(),
            ),
        ),
        (select_url.into(), response(200, select_url, "selected")),
        (
            detail_url.into(),
            response(
                200,
                detail_url,
                readonly_fixture("judge-detail.html").unwrap(),
            ),
        ),
    ]);
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("judge-fixture"),
    )
    .expect("client");

    let result = client.judge_assignments(false).await.expect("Judge list");
    assert_eq!(result.data.len(), 1);
    assert_eq!(result.data[0].course_name, "Algorithms");
    assert_eq!(result.data[0].submission_status_text, "进行中(2/3)");
    assert_eq!(result.data[0].my_score.as_deref(), Some("11"));
    assert_eq!(result.data[0].total_problems, 3);
}

#[tokio::test]
async fn judge_reactivates_once_when_a_business_page_returns_login_html() {
    let login_url = ubaa_core::features::judge::LOGIN_URL;
    let judge_home = "https://judge.buaa.edu.cn/";
    let courses_url = "https://judge.buaa.edu.cn/courselist.jsp?courseID=0";
    let select_url = "https://judge.buaa.edu.cn/courselist.jsp?courseID=1";
    let assignments_url = "https://judge.buaa.edu.cn/assignment/index.jsp";
    let detail_url = "https://judge.buaa.edu.cn/assignment/index.jsp?assignID=101";
    let transport = SpocTransport::new([
        (login_url.into(), redirect_from(login_url, judge_home)),
        (judge_home.into(), response(200, judge_home, "judge home")),
        (
            courses_url.into(),
            response(
                200,
                courses_url,
                r#"<form><input name="execution" value="fixture"></form>统一身份认证"#,
            ),
        ),
        (login_url.into(), redirect_from(login_url, judge_home)),
        (judge_home.into(), response(200, judge_home, "judge home")),
        (
            courses_url.into(),
            response(
                200,
                courses_url,
                readonly_fixture("judge-courses.html").unwrap(),
            ),
        ),
        (login_url.into(), redirect_from(login_url, judge_home)),
        (judge_home.into(), response(200, judge_home, "judge home")),
        (select_url.into(), response(200, select_url, "selected")),
        (
            assignments_url.into(),
            response(
                200,
                assignments_url,
                readonly_fixture("judge-assignments.html").unwrap(),
            ),
        ),
        (select_url.into(), response(200, select_url, "selected")),
        (
            detail_url.into(),
            response(
                200,
                detail_url,
                readonly_fixture("judge-detail.html").unwrap(),
            ),
        ),
    ]);
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("judge-reactivation-fixture"),
    )
    .unwrap();

    let result = client
        .judge_assignments(false)
        .await
        .expect("one Judge reactivation must succeed");

    assert_eq!(result.data.len(), 1);
    assert_eq!(result.data[0].assignment_id, "101");
}

#[tokio::test]
async fn judge_follows_business_redirects_before_parsing() {
    let login_url = ubaa_core::features::judge::LOGIN_URL;
    let judge_home = "https://judge.buaa.edu.cn/";
    let courses_url = "https://judge.buaa.edu.cn/courselist.jsp?courseID=0";
    let courses_redirect_target = "https://judge.buaa.edu.cn/courselist.jsp?courseID=0&from=home";
    let select_url = "https://judge.buaa.edu.cn/courselist.jsp?courseID=1";
    let assignments_url = "https://judge.buaa.edu.cn/assignment/index.jsp";
    let transport = SpocTransport::new([
        (login_url.into(), redirect_from(login_url, judge_home)),
        (judge_home.into(), response(200, judge_home, "judge home")),
        (
            courses_url.into(),
            redirect_from(courses_url, courses_redirect_target),
        ),
        (
            courses_redirect_target.into(),
            response(
                200,
                courses_redirect_target,
                readonly_fixture("judge-courses.html").unwrap(),
            ),
        ),
        (login_url.into(), redirect_from(login_url, judge_home)),
        (judge_home.into(), response(200, judge_home, "judge home")),
        (select_url.into(), response(200, select_url, "selected")),
        (
            assignments_url.into(),
            response(200, assignments_url, "no assignments"),
        ),
    ]);
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("judge-business-redirect-fixture"),
    )
    .unwrap();

    let result = client
        .judge_assignments(false)
        .await
        .expect("Judge business redirect must be followed");

    assert!(result.data.is_empty());
}

#[tokio::test]
async fn judge_empty_batch_and_missing_course_have_stable_semantics() {
    let transport = MockTransport::new([]);
    let mut empty_client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport.clone(),
        session_store_with("judge-empty-batch-fixture"),
    )
    .unwrap();

    let empty = empty_client.judge_assignment_details(&[]).await.unwrap();

    assert!(empty.data.is_empty());
    transport.assert_exhausted().unwrap();
    assert!(transport.requests().unwrap().is_empty());

    let login_url = ubaa_core::features::judge::LOGIN_URL;
    let judge_home = "https://judge.buaa.edu.cn/";
    let courses_url = "https://judge.buaa.edu.cn/courselist.jsp?courseID=0";
    let transport = MockTransport::new([
        ExpectedRequest::new(
            HttpMethod::Get,
            login_url,
            redirect_from(login_url, judge_home),
        ),
        expected_get(judge_home, "judge home"),
        expected_get(courses_url, readonly_fixture("judge-courses.html").unwrap()),
    ]);
    let mut missing_client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport.clone(),
        session_store_with("judge-missing-course-fixture"),
    )
    .unwrap();

    let error = missing_client
        .judge_assignment("missing", "101")
        .await
        .expect_err("unknown Judge course must fail safely");

    assert_eq!(error.code, ErrorCode::UpstreamChanged);
    transport.assert_exhausted().unwrap();
}

#[tokio::test]
async fn judge_empty_batches_require_a_local_session_before_zero_network_short_circuit() {
    let transport = MockTransport::new([]);
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport.clone(),
        MemorySessionStore::new(),
    )
    .unwrap();

    let empty_error = client
        .judge_assignment_details(&[])
        .await
        .expect_err("an unauthenticated empty batch must fail");
    assert_eq!(empty_error.code, ErrorCode::AuthenticationRequired);

    let blank_error = client
        .judge_assignment_details(&[JudgeAssignmentKey {
            course_id: " ".into(),
            assignment_id: String::new(),
        }])
        .await
        .expect_err("an unauthenticated all-blank batch must fail");
    assert_eq!(blank_error.code, ErrorCode::AuthenticationRequired);
    assert!(transport.requests().unwrap().is_empty());
}

#[tokio::test]
async fn judge_historical_courses_are_skipped_by_default_but_includable() {
    let login_url = ubaa_core::features::judge::LOGIN_URL;
    let judge_home = "https://judge.buaa.edu.cn/";
    let courses_url = "https://judge.buaa.edu.cn/courselist.jsp?courseID=0";
    let select_url = "https://judge.buaa.edu.cn/courselist.jsp?courseID=1";
    let assignments_url = "https://judge.buaa.edu.cn/assignment/index.jsp";
    let detail_url = "https://judge.buaa.edu.cn/assignment/index.jsp?assignID=101";
    let transport = MockTransport::new([
        ExpectedRequest::new(
            HttpMethod::Get,
            login_url,
            redirect_from(login_url, judge_home),
        ),
        expected_get(judge_home, "judge home"),
        expected_get(courses_url, readonly_fixture("judge-courses.html").unwrap()),
        ExpectedRequest::new(
            HttpMethod::Get,
            login_url,
            redirect_from(login_url, judge_home),
        ),
        expected_get(judge_home, "judge home"),
        expected_get(select_url, "selected"),
        expected_get(
            assignments_url,
            readonly_fixture("judge-assignments.html").unwrap(),
        ),
        expected_get(select_url, "selected"),
        expected_get(
            detail_url,
            "作业时间: 2020-01-01 08:00:00 至 2020-01-31 23:00:00 未提交",
        ),
    ]);
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport.clone(),
        session_store_with("judge-historical-fixture"),
    )
    .unwrap();

    let first = client.judge_assignments(false).await.unwrap();
    let skipped = client.judge_assignments(false).await.unwrap();
    let included = client.judge_assignments(true).await.unwrap();

    assert!(first.data.is_empty());
    assert!(skipped.data.is_empty());
    assert_eq!(included.data.len(), 1);
    assert_eq!(included.data[0].assignment_id, "101");
    transport.assert_exhausted().unwrap();
}

#[tokio::test]
async fn judge_webvpn_batch_details_keep_every_request_on_gateway_host() {
    use ubaa_core::connection::to_webvpn_url;

    let direct_urls = [
        ubaa_core::features::judge::LOGIN_URL.to_string(),
        "https://judge.buaa.edu.cn/".into(),
        "https://judge.buaa.edu.cn/courselist.jsp?courseID=0".into(),
        ubaa_core::features::judge::LOGIN_URL.to_string(),
        "https://judge.buaa.edu.cn/".into(),
        "https://judge.buaa.edu.cn/courselist.jsp?courseID=1".into(),
        "https://judge.buaa.edu.cn/assignment/index.jsp".into(),
        "https://judge.buaa.edu.cn/courselist.jsp?courseID=1".into(),
        "https://judge.buaa.edu.cn/assignment/index.jsp?assignID=101".into(),
    ];
    let urls = direct_urls
        .iter()
        .map(|url| to_webvpn_url(url).unwrap())
        .collect::<Vec<_>>();
    let transport = MockTransport::new([
        ExpectedRequest::new(HttpMethod::Get, &urls[0], redirect_from(&urls[0], &urls[1])),
        expected_get(&urls[1], "judge home"),
        expected_get(&urls[2], readonly_fixture("judge-courses.html").unwrap()),
        ExpectedRequest::new(HttpMethod::Get, &urls[3], redirect_from(&urls[3], &urls[4])),
        expected_get(&urls[4], "judge home"),
        expected_get(&urls[5], "selected"),
        expected_get(
            &urls[6],
            readonly_fixture("judge-assignments.html").unwrap(),
        ),
        expected_get(&urls[7], "selected"),
        expected_get(&urls[8], readonly_fixture("judge-detail.html").unwrap()),
    ]);
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::WebVpn,
        transport,
        session_store_for(ConnectionMode::WebVpn, "judge-webvpn-fixture"),
    )
    .unwrap();

    let result = client
        .judge_assignment_details(&[JudgeAssignmentKey {
            course_id: "1".into(),
            assignment_id: "101".into(),
        }])
        .await
        .unwrap();

    assert_eq!(result.data[0].assignment_id, "101");
    observed.assert_exhausted().unwrap();
    for request in observed.requests().unwrap() {
        assert!(request.url.starts_with("https://d.buaa.edu.cn/"));
    }
}

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
            ConnectionMode::WebVpn => ubaa_core::connection::from_webvpn_url(url).unwrap(),
        }
    }

    fn routed_url(&self, url: &str) -> String {
        match self.mode {
            ConnectionMode::Direct => url.into(),
            ConnectionMode::WebVpn => ubaa_core::connection::to_webvpn_url(url).unwrap(),
        }
    }
}

#[async_trait]
impl HttpTransport for IsolatedJudgeSessionTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let login_url = ubaa_core::features::judge::LOGIN_URL;
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

#[derive(Clone)]
struct JudgeConcurrencyTransport {
    inflight: Arc<AtomicUsize>,
    max_inflight: Arc<AtomicUsize>,
}

impl JudgeConcurrencyTransport {
    fn new() -> Self {
        Self {
            inflight: Arc::new(AtomicUsize::new(0)),
            max_inflight: Arc::new(AtomicUsize::new(0)),
        }
    }

    fn max_inflight(&self) -> usize {
        self.max_inflight.load(Ordering::SeqCst)
    }
}

#[async_trait]
impl HttpTransport for JudgeConcurrencyTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let current = self.inflight.fetch_add(1, Ordering::SeqCst) + 1;
        self.max_inflight.fetch_max(current, Ordering::SeqCst);
        tokio::time::sleep(Duration::from_millis(5)).await;
        let result = if request.url
            == "https://sso.buaa.edu.cn/login?service=http%3A%2F%2Fjudge.buaa.edu.cn%2F"
        {
            Ok(redirect_from(&request.url, "https://judge.buaa.edu.cn/"))
        } else if request.url == "https://judge.buaa.edu.cn/" {
            Ok(response(200, &request.url, "judge home"))
        } else if request.url == "https://judge.buaa.edu.cn/courselist.jsp?courseID=0" {
            let mut courses = String::new();
            for id in 1..=8 {
                let _ = write!(
                    courses,
                    r#"<a href="courselist.jsp?courseID={id}">Course {id}</a>"#
                );
            }
            Ok(response(200, &request.url, &courses))
        } else if request
            .url
            .starts_with("https://judge.buaa.edu.cn/courselist.jsp?courseID=")
        {
            Ok(response(200, &request.url, "selected"))
        } else if request.url == "https://judge.buaa.edu.cn/assignment/index.jsp" {
            Ok(response(
                200,
                &request.url,
                r#"<a href="assignment/index.jsp?assignID=1">Lab</a>"#,
            ))
        } else if request.url == "https://judge.buaa.edu.cn/assignment/index.jsp?assignID=1" {
            Ok(response(
                200,
                &request.url,
                "作业满分:100 共 2 道 作业时间: 2026-08-01 08:00:00 至 2026-08-31 23:00:00 未提交",
            ))
        } else {
            Err(UbaaError::new(
                ErrorCode::InternalError,
                ErrorKind::Internal,
                false,
                "unexpected Judge concurrency request",
            ))
        };
        self.inflight.fetch_sub(1, Ordering::SeqCst);
        result
    }
}

#[tokio::test]
async fn judge_limits_course_queries_to_four_workers() {
    let transport = JudgeConcurrencyTransport::new();
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("judge-concurrency-fixture"),
    )
    .expect("client");

    let result = client.judge_assignments(false).await.expect("Judge list");
    assert_eq!(result.data.len(), 8);
    assert!(
        observed.max_inflight() >= 2,
        "Judge course queries must run concurrently"
    );
    assert!(
        observed.max_inflight() <= 4,
        "Judge course query concurrency must stay bounded at four"
    );
}

#[tokio::test]
async fn judge_batch_details_preserve_input_order_with_four_workers() {
    let transport = JudgeConcurrencyTransport::new();
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("judge-batch-concurrency-fixture"),
    )
    .expect("client");
    let keys = (1..=8)
        .map(|course_id| JudgeAssignmentKey {
            course_id: course_id.to_string(),
            assignment_id: "1".into(),
        })
        .collect::<Vec<_>>();

    let result = client
        .judge_assignment_details(&keys)
        .await
        .expect("Judge details");
    assert_eq!(result.data.len(), keys.len());
    for (detail, key) in result.data.iter().zip(&keys) {
        assert_eq!(detail.course_id, key.course_id);
        assert_eq!(detail.assignment_id, key.assignment_id);
    }
    assert!(
        observed.max_inflight() >= 2,
        "Judge detail queries must run concurrently"
    );
    assert!(
        observed.max_inflight() <= 4,
        "Judge detail query concurrency must stay bounded at four"
    );
}

#[derive(Clone, Default)]
struct JudgeGroupedBatchTransport {
    requests: Arc<Mutex<Vec<String>>>,
}

impl JudgeGroupedBatchTransport {
    fn request_count(&self, url: &str) -> usize {
        self.requests
            .lock()
            .expect("Judge grouped request log")
            .iter()
            .filter(|request| request.as_str() == url)
            .count()
    }
}

#[async_trait]
impl HttpTransport for JudgeGroupedBatchTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.requests
            .lock()
            .expect("Judge grouped request log")
            .push(request.url.clone());
        let body = match request.url.as_str() {
            url if url == ubaa_core::features::judge::LOGIN_URL => {
                return Ok(redirect_from(url, "https://judge.buaa.edu.cn/"));
            }
            "https://judge.buaa.edu.cn/" => "judge ready",
            "https://judge.buaa.edu.cn/courselist.jsp?courseID=0" => {
                r#"<a href="courselist.jsp?courseID=1">Course 1</a>"#
            }
            "https://judge.buaa.edu.cn/courselist.jsp?courseID=1" => {
                // Give independent per-key workers time to observe the same missing cache entry.
                tokio::time::sleep(Duration::from_millis(10)).await;
                "selected"
            }
            "https://judge.buaa.edu.cn/assignment/index.jsp" => {
                r#"<a href="assignment/index.jsp?assignID=101">First</a>
                   <a href="assignment/index.jsp?assignID=102">Second</a>"#
            }
            "https://judge.buaa.edu.cn/assignment/index.jsp?assignID=101" => {
                "作业满分: 10 共 1 道 作业时间: 2026-08-01 08:00 至 2026-08-31 23:00 未提交"
            }
            "https://judge.buaa.edu.cn/assignment/index.jsp?assignID=102" => {
                "作业满分: 20 共 1 道 作业时间: 2026-08-02 08:00 至 2026-08-31 23:00 未提交"
            }
            _ => {
                return Err(UbaaError::new(
                    ErrorCode::InternalError,
                    ErrorKind::Internal,
                    false,
                    "unexpected grouped Judge request",
                ));
            }
        };
        Ok(response(200, &request.url, body))
    }
}

#[tokio::test]
async fn judge_same_course_batch_fetches_one_list_and_preserves_input_order() {
    let transport = JudgeGroupedBatchTransport::default();
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("judge-grouped-batch-fixture"),
    )
    .expect("client");
    let keys = [
        JudgeAssignmentKey {
            course_id: "1".into(),
            assignment_id: "102".into(),
        },
        JudgeAssignmentKey {
            course_id: "1".into(),
            assignment_id: "101".into(),
        },
    ];

    let result = client
        .judge_assignment_details(&keys)
        .await
        .expect("grouped Judge details");

    assert_eq!(
        result
            .data
            .iter()
            .map(|detail| detail.assignment_id.as_str())
            .collect::<Vec<_>>(),
        ["102", "101"]
    );
    assert_eq!(
        observed.request_count("https://judge.buaa.edu.cn/assignment/index.jsp"),
        1,
        "one course worker must fetch and select the assignment list once"
    );
}

#[tokio::test]
async fn judge_batch_filters_blank_and_deduplicates_keys_in_first_seen_order() {
    let transport = JudgeGroupedBatchTransport::default();
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("judge-normalized-batch-fixture"),
    )
    .expect("client");
    let keys = [
        JudgeAssignmentKey {
            course_id: "1".into(),
            assignment_id: "102".into(),
        },
        JudgeAssignmentKey {
            course_id: " ".into(),
            assignment_id: "101".into(),
        },
        JudgeAssignmentKey {
            course_id: "1".into(),
            assignment_id: "102".into(),
        },
        JudgeAssignmentKey {
            course_id: "1".into(),
            assignment_id: "101".into(),
        },
    ];

    let result = client
        .judge_assignment_details(&keys)
        .await
        .expect("normalized Judge details");

    assert_eq!(
        result
            .data
            .iter()
            .map(|detail| detail.assignment_id.as_str())
            .collect::<Vec<_>>(),
        ["102", "101"],
        "the frozen normalization filters blank keys and keeps the first duplicate only"
    );
    assert_eq!(
        observed.request_count("https://judge.buaa.edu.cn/assignment/index.jsp"),
        1
    );
    assert_eq!(
        observed.request_count("https://judge.buaa.edu.cn/assignment/index.jsp?assignID=102"),
        1
    );
}

#[tokio::test]
async fn judge_clients_with_the_same_route_and_cookie_do_not_share_cache() {
    let first_transport = JudgeGroupedBatchTransport::default();
    let mut first = RouteClient::with_transport(
        ConnectionMode::Direct,
        first_transport,
        session_store_with("judge-client-isolation-fixture"),
    )
    .expect("first client");
    first
        .judge_assignment("1", "101")
        .await
        .expect("first Judge detail");

    let second_transport = JudgeGroupedBatchTransport::default();
    let observed_second = second_transport.clone();
    let mut second = RouteClient::with_transport(
        ConnectionMode::Direct,
        second_transport,
        session_store_with("judge-client-isolation-fixture"),
    )
    .expect("second client");
    second
        .judge_assignment("1", "101")
        .await
        .expect("second Judge detail");

    assert_eq!(
        observed_second.request_count("https://judge.buaa.edu.cn/courselist.jsp?courseID=0"),
        1,
        "a separately constructed client must fetch its own course cache"
    );
    assert_eq!(
        observed_second
            .request_count("https://judge.buaa.edu.cn/assignment/index.jsp?assignID=101"),
        1,
        "a separately constructed client must fetch its own detail cache"
    );
}

#[derive(Clone)]
struct JudgeRetryTransport {
    course_requests: Arc<AtomicUsize>,
    activation_requests: Arc<AtomicUsize>,
    successful_attempt: Option<usize>,
}

impl JudgeRetryTransport {
    fn new(successful_attempt: Option<usize>) -> Self {
        Self {
            course_requests: Arc::new(AtomicUsize::new(0)),
            activation_requests: Arc::new(AtomicUsize::new(0)),
            successful_attempt,
        }
    }
}

#[async_trait]
impl HttpTransport for JudgeRetryTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        if request.url == ubaa_core::features::judge::LOGIN_URL {
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
        Err(UbaaError::new(
            ErrorCode::InternalError,
            ErrorKind::Internal,
            false,
            "unexpected Judge retry request",
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
    let transport = JudgeRetryTransport::new(None);
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

    assert_eq!(error.code, ErrorCode::AuthenticationRequired);
    assert_eq!(observed.course_requests.load(Ordering::SeqCst), 4);
    assert_eq!(observed.activation_requests.load(Ordering::SeqCst), 4);
}

#[tokio::test]
async fn successful_primary_login_invalidates_route_owned_judge_caches() {
    let judge_login = ubaa_core::features::judge::LOGIN_URL;
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
    assert!(client.prepare_login().await.unwrap().is_none());
    client
        .login(LoginInput {
            username: "fixture-user".into(),
            password: SecretValue::new("fixture-password"),
            captcha: None,
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
