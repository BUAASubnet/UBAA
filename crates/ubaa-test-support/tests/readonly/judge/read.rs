use ubaa_core::facade::testing::{HttpMethod, to_webvpn_url};
use ubaa_core::facade::{ConnectionMode, ErrorCode, JudgeAssignmentKey, RouteClient};
use ubaa_test_support::{ExpectedRequest, MemorySessionStore, MockTransport, readonly_fixture};

use super::JUDGE_LOGIN_URL;
use crate::common::{
    SpocTransport, expected_get, redirect_from, response, session_store_for, session_store_with,
};

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
async fn judge_diagnostics_reuse_the_list_chain_and_report_safe_parser_counts() {
    let login_url = JUDGE_LOGIN_URL;
    let judge_home = "https://judge.buaa.edu.cn/";
    let courses_url = "https://judge.buaa.edu.cn/courselist.jsp?courseID=0";
    let select_url = "https://judge.buaa.edu.cn/courselist.jsp?courseID=1";
    let assignments_url = "https://judge.buaa.edu.cn/assignment/index.jsp";
    let detail_url = "https://judge.buaa.edu.cn/assignment/index.jsp?assignID=101";
    let assignments = r#"
        <a href="problemContent.jsp?assignID=101">internal</a>
        <a href="judgeDetails.jsp?assignID=101">internal result</a>
        <a href="assignment/index.jsp?assignID=999"><span> </span></a>
        <a href="assignment/index.jsp?assignID=101">Fixture</a>
        <a href="assignment/index.jsp?assignID=101">duplicate</a>
    "#;
    let transport = MockTransport::new([
        ExpectedRequest::new(
            HttpMethod::Get,
            login_url,
            redirect_from(login_url, judge_home),
        ),
        expected_get(judge_home, "judge ready"),
        expected_get(
            courses_url,
            r#"<a href="courselist.jsp?courseID=1">Course 1</a>"#,
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            login_url,
            redirect_from(login_url, judge_home),
        ),
        expected_get(judge_home, "judge ready"),
        expected_get(select_url, "selected"),
        expected_get(assignments_url, assignments),
        expected_get(select_url, "selected"),
        expected_get(
            detail_url,
            "作业满分: 10 共 1 道 作业时间: 2026-08-01 08:00 至 2026-08-31 23:00 未提交",
        ),
    ]);
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("judge-diagnostic-counts-fixture"),
    )
    .unwrap();

    let ordinary = client.judge_assignments(false).await.unwrap();
    let diagnostic = client.judge_assignments_diagnostics(false).await.unwrap();

    assert_eq!(ordinary.data, diagnostic.data.summaries);
    assert_eq!(diagnostic.data.course_count, 1);
    assert_eq!(diagnostic.data.raw_anchor_count, 5);
    assert_eq!(diagnostic.data.filtered_unique_count, 1);
    observed.assert_exhausted().unwrap();
    assert_eq!(
        observed
            .requests()
            .unwrap()
            .iter()
            .filter(|request| request.url == assignments_url)
            .count(),
        1,
        "ordinary and diagnostic reads must share one parsed assignment-list cache entry"
    );
}

#[tokio::test]
async fn judge_reactivates_once_when_a_business_page_returns_login_html() {
    let login_url = JUDGE_LOGIN_URL;
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
    let login_url = JUDGE_LOGIN_URL;
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

    let login_url = JUDGE_LOGIN_URL;
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
    let login_url = JUDGE_LOGIN_URL;
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
    let direct_urls = [
        JUDGE_LOGIN_URL.to_string(),
        "https://judge.buaa.edu.cn/".into(),
        "https://judge.buaa.edu.cn/courselist.jsp?courseID=0".into(),
        JUDGE_LOGIN_URL.to_string(),
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
