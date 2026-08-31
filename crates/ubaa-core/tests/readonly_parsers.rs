use ubaa_core::domain::{JudgeSubmissionStatus, SpocSubmissionStatus};
use ubaa_core::features::{cgyy, classroom, evaluation, grades, judge, schedule, spoc};

#[test]
fn cgyy_lock_code_parser_returns_safe_availability_summary() {
    let result =
        cgyy::parse_lock_code(r#"{"code":200,"data":{"orderId":7,"lockCode":"1234"}}"#).unwrap();
    assert!(result.available);
}

#[test]
fn evaluation_success_envelope_preserves_pending_progress() {
    let body = r#"{"code":"200","result":{"list":[{"rwid":"task-1","rwmc":"课程评教","wjid":"form-1","kcdm":"course-1","kcmc":"课程","bpmc":"教师","ypjcs":0}]}}"#;
    let response = evaluation::parse_courses(body).expect("evaluation fixture should parse");
    assert_eq!(response.courses.len(), 1);
    assert_eq!(response.progress.pending_courses, 1);
}

#[test]
fn schedule_and_exam_parsers_map_verified_wrappers_and_reject_nonzero_codes() {
    let terms = schedule::parse_terms(r#"{"code":"0","datas":[{"itemCode":"2025-2026-1","itemName":"Fixture Term","selected":true,"itemIndex":1}]}"#).unwrap();
    assert_eq!(terms[0].item_code, "2025-2026-1");
    let error = schedule::parse_terms(r#"{"code":"1","datas":[]}"#).unwrap_err();
    assert_eq!(error.code, ubaa_core::error::ErrorCode::UpstreamChanged);

    let exam = schedule::parse_exam(
        r#"{"code":"0","datas":[{"courseName":"Fixture Course","examDate":"2026-01-01"}]}"#,
    )
    .unwrap();
    assert_eq!(exam.arranged.len(), 1);
}

#[test]
fn schedule_week_and_today_wrappers_preserve_frozen_nonzero_code_tolerance() {
    // LocalScheduleApi.kt 只对学期和考试检查 code；另外三个本地解析器
    // 直接返回解码后的 datas 载荷。
    let weeks = schedule::parse_weeks(
        r#"{"code":"7","datas":[{"startDate":"2026-01-01","endDate":"2026-01-07","term":"fixture","curWeek":false,"serialNumber":1,"name":"第1周"}]}"#,
    )
    .expect("frozen weeks parser does not gate on code");
    assert_eq!(weeks.len(), 1);

    let weekly = schedule::parse_weekly_schedule(
        r#"{"code":"7","datas":{"arrangedList":[],"code":"fixture","name":"Fixture"}}"#,
    )
    .expect("frozen weekly parser does not gate on code");
    assert_eq!(weekly.code, "fixture");

    let today = schedule::parse_today(
        r#"{"code":"7","datas":[{"bizName":"Fixture","place":null,"time":null,"shortName":null}]}"#,
    )
    .expect("frozen today parser does not gate on code");
    assert_eq!(today.len(), 1);
}

#[test]
fn grades_require_verified_term_shape_and_map_e_m_d_payload() {
    let term = grades::parse_term_code("2025-2026-1").unwrap();
    assert_eq!(term.year, "2025-2026");
    assert_eq!(term.semester, 1);
    assert!(grades::parse_term_code("2025/2026/1").is_err());
    let data = grades::parse_scores("2025-2026-1", r#"{"e":0,"m":"ok","d":{"a":{"kcmc":"Fixture","kch":"C-1","xf":"2.0","kccj":95,"fslx":"normal","kclx":"required"}}}"#).unwrap();
    assert_eq!(data.grades[0].course_name.as_deref(), Some("Fixture"));
    assert_eq!(data.grades[0].score.as_deref(), Some("95"));
}

#[test]
fn classroom_parser_preserves_empty_results_and_spoc_status_mapping() {
    let classroom = classroom::parse_response(r#"{"e":0,"m":"ok","d":{"list":{}}}"#).unwrap();
    assert!(classroom.floors.is_empty());
    assert_eq!(
        spoc::map_submission_status(Some("已提交"), true),
        SpocSubmissionStatus::Submitted
    );
    assert_eq!(
        spoc::map_submission_status(Some("未提交"), true),
        SpocSubmissionStatus::Unsubmitted
    );
}

#[test]
fn classroom_parser_preserves_nonzero_legacy_code_in_decoded_response() {
    let classroom =
        classroom::parse_response(r#"{"e":1,"m":"legacy status","d":{"list":{"Main":[]}}}"#)
            .expect("frozen classroom parser decodes e without gating its value");
    assert_eq!(classroom.code, 1);
    assert_eq!(classroom.message, "legacy status");
}

#[test]
fn classroom_parser_requires_the_complete_frozen_envelope_and_room_strings() {
    for incomplete in [
        r#"{"m":"ok","d":{"list":{}}}"#,
        r#"{"e":0,"d":{"list":{}}}"#,
        r#"{"e":0,"m":"ok"}"#,
        r#"{"e":0,"m":"ok","d":{}}"#,
        r#"{"e":0,"m":"ok","d":{"list":{"Main":[{"id":"1","floorid":"101","name":"Room"}]}}}"#,
        r#"{"e":0,"m":"ok","d":{"list":{"Main":[{"id":1,"floorid":"101","name":"Room","kxsds":"1,2"}]}}}"#,
    ] {
        let error = classroom::parse_response(incomplete)
            .expect_err("missing or non-string frozen fields must not become empty success");
        assert_eq!(error.code, ubaa_core::error::ErrorCode::ParseError);
    }
}

#[test]
fn judge_parser_uses_sanitized_complex_dom_fixtures() {
    let courses = judge::parse_courses(r"<a href='courselist.jsp?courseID=12'>Fixture Course</a>");
    assert_eq!(courses.len(), 1);
    let assignments = judge::parse_assignments(
        include_str!("../../../fixtures/readonly/judge-assignments.html"),
        &courses[0],
    );
    assert_eq!(assignments.len(), 1);
    assert_eq!(assignments[0].assignment_id, "101");
    assert_eq!(assignments[0].title, "Lab & Review");

    let detail = judge::parse_detail(
        include_str!("../../../fixtures/readonly/judge-detail.html"),
        "12",
        "Fixture Course",
        "101",
        "Lab & Review",
    )
    .unwrap();
    assert_eq!(detail.start_time.as_deref(), Some("2026-08-01 08:00:00"));
    assert_eq!(detail.due_time.as_deref(), Some("2026-08-31 23:00:00"));
    assert_eq!(detail.max_score.as_deref(), Some("30"));
    assert_eq!(detail.my_score.as_deref(), Some("11"));
    assert_eq!(detail.total_problems, 3);
    assert_eq!(detail.submitted_count, 2);
    assert_eq!(detail.submission_status, JudgeSubmissionStatus::Partial);
    assert_eq!(detail.submission_status_text, "进行中(2/3)");
    assert_eq!(detail.problems.len(), 3);
    assert_eq!(detail.problems[0].name, "程序 & 设计");
    assert_eq!(detail.problems[0].score.as_deref(), Some("8"));
    assert_eq!(
        detail.problems[1].status,
        JudgeSubmissionStatus::Unsubmitted
    );
    assert_eq!(detail.problems[2].name, "第3题");
    assert_eq!(detail.problems[2].score.as_deref(), Some("3"));
    let plain = detail.content_plain_text.as_deref().unwrap();
    assert!(!plain.contains("作业满分：999"));
    assert!(!plain.contains("总分：999"));
}
