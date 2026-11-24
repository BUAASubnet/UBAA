use ubaa_core::facade::{ConnectionMode, RouteClient, SpocSubmissionStatus};

use crate::common::{SpocTransport, redirect, response, session_store, session_store_with};

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
    let page_token_url = "https://spoc.buaa.edu.cn/spocnew/cas?token=global-page-token";
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
        // 课程补充已用完重试次数，后续独立的全局页使用新凭据。
        (cas.into(), redirect(page_token_url)),
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
        session_store_with("spoc-course-auth-fixture"),
    )
    .unwrap();

    let result = client
        .spoc_assignments()
        .await
        .expect("course metadata stays optional after its own auth retry is exhausted");

    assert_eq!(result.data.assignments.len(), 0);
    observed.assert_exhausted();
    let requests = observed.requests();
    assert_eq!(
        requests
            .iter()
            .filter(|request| request.url == courses_url)
            .count(),
        2
    );
    let page = requests
        .iter()
        .find(|request| request.url == assignments_url)
        .unwrap();
    assert_eq!(
        page.headers.get("Token").map(String::as_str),
        Some("Inco-global-page-token")
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
                ubaa_test_support::readonly_fixture("spoc-detail-files.json").unwrap(),
            ),
        ),
        (
            submission_url.into(),
            response(
                200,
                submission_url,
                r#"{"code":200,"content":{"tjzt":"已做","tjsj":"2026-03-30T10:00:00.000+00:00","scwjid":"fixture-answer","ytjcs":"1"}}"#,
            ),
        ),
        ("https://spoc.buaa.edu.cn/inco-filesystem/fileManagerSystem/queryFileById?wjid=fixture-attachment".into(),response(200,"https://spoc.buaa.edu.cn/",r#"{"wjysmc":"练习.zip","wjhzm":"zip","fileSize":"1MB"}"#)),
        ("https://spoc.buaa.edu.cn/inco-filesystem/fileManagerSystem/queryFileById?wjid=fixture-answer".into(),response(503,"https://spoc.buaa.edu.cn/","")),
    ]);
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, transport, session_store())
            .expect("client");

    let result = client.spoc_assignment("a1").await.expect("SPOC detail");
    let detail = serde_json::to_value(&result.data).unwrap();
    assert!(detail.get("attachment").is_none());
    let attachment = result.data.attachment.as_ref().unwrap();
    assert_eq!(attachment.file_id, "fixture-attachment");
    assert_eq!(attachment.file_name.as_deref(), Some("练习.zip"));
    assert_eq!(attachment.size_text.as_deref(), Some("1MB"));
    assert_eq!(attachment.extension.as_deref(), Some("zip"));
    let submitted = result.data.submitted_file.as_ref().unwrap();
    assert_eq!(submitted.file_id, "fixture-answer");
    assert!(submitted.file_name.is_none());
    assert_eq!(result.data.submission_count, Some(1));
    assert_eq!(result.data.submit_modes, ["5", "1"]);
    assert_eq!(result.data.allowed_extensions, [".pdf", ".zip"]);
    assert!(result.data.max_submissions.is_none());
    assert!(result.data.is_group_assignment);
    assert_eq!(
        result.data.late_submission_deadline.as_deref(),
        Some("2026-03-31 18:00:00")
    );
    for private in ["yhdm", "yhmc", "photo", "dqczr", "dqczrmc", "ccxdlj"] {
        assert!(!detail.to_string().contains(private));
    }
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
        SpocSubmissionStatus::Unsubmitted
    );
    observed.assert_exhausted();
}
