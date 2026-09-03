use ubaa_core::facade::testing::{HttpMethod, HttpResponse, to_webvpn_url};
use ubaa_core::facade::{ConnectionMode, ErrorCode, RouteClient};
use ubaa_test_support::{ExpectedRequest, MockTransport, readonly_fixture};

use crate::common::{expected_get, redirect_from, response, session_store, session_store_for};

const CURRENT_USER_URL: &str = "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/currentUser.do";
const TERMS_URL: &str =
    "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/student/schoolCalendars.do";
const WEEKS_URL: &str = "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/getTermWeeks.do";
const WEEK_URL: &str =
    "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/student/getMyScheduleDetail.do";
const TODAY_URL: &str =
    "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/teachingSchedule/detail.do";
const EXAM_URL: &str = "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/student/exams.do";
const GRADES_URL: &str = "https://app.buaa.edu.cn/buaascore/wap/default/index";
const CLASSROOM_URL: &str = "https://app.buaa.edu.cn/buaafreeclass/wap/default/search1";
const CLASSROOM_SYNC_URL: &str = "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fapp.buaa.edu.cn%2Fa_buaa%2Fapi%2Fcas%2Findex%3Fredirect%3Dhttps%253A%252F%252Fapp.buaa.edu.cn%252Fsite%252FclassRoomQuery%252Findex%26from%3Dwap%26login_from%3D&noAutoRedirect=1";

#[tokio::test]
async fn schedule_and_exam_use_verified_requests_and_sanitized_fixtures() {
    let current_user = CURRENT_USER_URL;
    let terms_url = TERMS_URL;
    let weeks_url = format!("{WEEKS_URL}?termCode=2025-2026-1");
    let weekly_schedule_url = WEEK_URL;
    let today_url = format!("{TODAY_URL}?rq={}&lxdm=student", shanghai_date());
    let exam_url = format!("{EXAM_URL}?termCode=2025-2026-1");
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
    let current_user = CURRENT_USER_URL;
    let terms = TERMS_URL;
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
    let current_user = CURRENT_USER_URL;
    let terms = TERMS_URL;
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
    let direct_current_user = CURRENT_USER_URL;
    let direct_terms = TERMS_URL;
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
    let url = GRADES_URL;
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
async fn readonly_sso_final_url_is_classified_as_authentication_required() {
    let sync_url = CLASSROOM_SYNC_URL;
    let query_url = format!("{CLASSROOM_URL}?xqid=1&floorid=&date=2026-04-20");
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
    let current_user = to_webvpn_url(CURRENT_USER_URL).unwrap();
    let terms = to_webvpn_url(TERMS_URL).unwrap();
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

    let sync = to_webvpn_url(CLASSROOM_SYNC_URL).unwrap();
    let direct_query = format!("{CLASSROOM_URL}?xqid=1&floorid=&date=2026-04-20");
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

    let grades_url = to_webvpn_url(GRADES_URL).unwrap();
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
