use std::collections::{BTreeMap, VecDeque};
use std::fmt::Write as _;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use async_trait::async_trait;
use ubaa_core::domain::{ConnectionMode, JudgeAssignmentKey};
use ubaa_core::error::{ErrorCode, ErrorKind, Result, UbaaError};
use ubaa_core::facade::UbaaClient;
use ubaa_core::ports::{HttpMethod, HttpRequest, HttpResponse, HttpTransport};
use ubaa_core::session::{SessionSnapshot, SessionStore, StoredCookie};
use ubaa_test_support::{ExpectedRequest, MemorySessionStore, MockTransport, readonly_fixture};

#[derive(Clone)]
struct SpocTransport {
    responses: Arc<Mutex<VecDeque<(String, HttpResponse)>>>,
}

impl SpocTransport {
    fn new(responses: impl IntoIterator<Item = (String, HttpResponse)>) -> Self {
        Self {
            responses: Arc::new(Mutex::new(responses.into_iter().collect())),
        }
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
        UbaaClient::with_transport(ConnectionMode::Direct, transport, session_store()).unwrap();

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
        UbaaClient::with_transport(ConnectionMode::Direct, transport, session_store()).unwrap();

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
async fn classroom_uses_verified_sync_headers_and_sanitized_fixture() {
    let sync_url = ubaa_core::features::classroom::CLASSROOM_SYNC_URL;
    let query_url = format!(
        "{}?xqid=1&floorid=&date=2026-04-20",
        ubaa_core::features::classroom::CLASSROOM_URL
    );
    let transport = MockTransport::new([
        expected_get(sync_url, ""),
        expected_get(&query_url, readonly_fixture("classroom.json").unwrap()),
    ]);
    let observed = transport.clone();
    let mut client =
        UbaaClient::with_transport(ConnectionMode::Direct, transport, session_store()).unwrap();

    let result = client.classroom_search(1, "2026-04-20").await.unwrap();

    assert_eq!(result.data.floors["Main"][0].name, "Fixture Room");
    observed.assert_exhausted().unwrap();
    let requests = observed.requests().unwrap();
    assert_eq!(
        requests[0].headers.get("User-Agent").map(String::as_str),
        Some("Mozilla/5.0")
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
        Some("https://app.buaa.edu.cn/site/classRoomQuery/index")
    );
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
        UbaaClient::with_transport(ConnectionMode::Direct, transport, session_store()).unwrap();

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
        UbaaClient::with_transport(ConnectionMode::Direct, transport, session_store()).unwrap();

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
    let mut schedule_client = UbaaClient::with_transport(
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
    let mut classroom_client = UbaaClient::with_transport(
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
    let mut grades_client = UbaaClient::with_transport(
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
        (token_url.into(), response(200, token_url, "token landing")),
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
                r#"{"code":200,"content":[{"kcid":"course-1","kcmc":"Systems","skjs":"Teacher"}]}"#,
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
    let mut client = UbaaClient::with_transport(ConnectionMode::Direct, transport, session_store())
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
}

#[tokio::test]
async fn spoc_business_authentication_failure_refreshes_login_once() {
    let cas = "https://spoc.buaa.edu.cn/spocnewht/cas";
    let first_token_url = "https://spoc.buaa.edu.cn/spocnew/cas?token=expired-token";
    let fresh_token_url = "https://spoc.buaa.edu.cn/spocnew/cas?token=fresh-token";
    let login_url = "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin";
    let term_url = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne";
    let courses_url = "https://spoc.buaa.edu.cn/spocnewht/jxkj/queryKclb?kcmc=&xnxq=2025-20262";
    let transport = SpocTransport::new([
        (cas.into(), redirect(first_token_url)),
        (
            first_token_url.into(),
            response(200, first_token_url, "token landing"),
        ),
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
            fresh_token_url.into(),
            response(200, fresh_token_url, "token landing"),
        ),
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
    ]);
    let mut client = UbaaClient::with_transport(
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
        (token_url.into(), response(200, token_url, "token landing")),
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
        (cas.into(), redirect(token_url)),
        (token_url.into(), response(200, token_url, "token landing")),
        (
            "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin".into(),
            response(
                200,
                "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin",
                r#"{"code":200,"content":{"jsdm":"01"}}"#,
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
    let mut client = UbaaClient::with_transport(ConnectionMode::Direct, transport, session_store())
        .expect("client");

    let result = client.spoc_assignment("a1").await.expect("SPOC detail");
    assert_eq!(result.data.course_name, "Systems");
    assert_eq!(result.data.teacher_name.as_deref(), Some("Teacher"));
    assert_eq!(result.data.submission_status_text, "已提交");
    assert_eq!(result.data.content_plain_text.as_deref(), Some("Read only"));
    assert_eq!(
        result.data.submitted_at.as_deref(),
        Some("2026-03-30 18:00:00")
    );
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
    let mut client = UbaaClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("judge-fixture"),
    )
    .expect("client");

    let result = client.judge_assignments(false).await.expect("Judge list");
    assert_eq!(result.data.len(), 1);
    assert_eq!(result.data[0].course_name, "Algorithms");
    assert_eq!(result.data[0].submission_status_text, "未提交");
    assert_eq!(result.data[0].total_problems, 2);
}

#[tokio::test]
async fn judge_webvpn_batch_details_keep_every_request_on_gateway_host() {
    use ubaa_core::connection::to_webvpn_url;

    let direct_urls = [
        ubaa_core::features::judge::LOGIN_URL.to_string(),
        "https://judge.buaa.edu.cn/".into(),
        "https://judge.buaa.edu.cn/courselist.jsp?courseID=0".into(),
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
        expected_get(&urls[3], "selected"),
        expected_get(
            &urls[4],
            readonly_fixture("judge-assignments.html").unwrap(),
        ),
        expected_get(&urls[5], "selected"),
        expected_get(&urls[6], readonly_fixture("judge-detail.html").unwrap()),
    ]);
    let observed = transport.clone();
    let mut client = UbaaClient::with_transport(
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
    let mut client = UbaaClient::with_transport(
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
    let mut client = UbaaClient::with_transport(
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
