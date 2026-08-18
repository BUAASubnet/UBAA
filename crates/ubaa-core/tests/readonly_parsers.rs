use ubaa_core::domain::{JudgeSubmissionStatus, SpocSubmissionStatus};
use ubaa_core::features::{classroom, grades, judge, schedule, spoc};

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
fn judge_parser_handles_multiple_links_and_unsubmitted_details() {
    let courses = judge::parse_courses(r"<a href='courselist.jsp?courseID=12'>Fixture Course</a>");
    assert_eq!(courses.len(), 1);
    let assignments = judge::parse_assignments(
        r#"<a href="assignment/index.jsp?assignID=7">Fixture Task</a>"#,
        &courses[0],
    );
    assert_eq!(assignments[0].assignment_id, "7");
    let detail = judge::parse_detail("<p>作业满分：100</p><p>共 1 道</p><table><tr><td>1</td><td>Question</td><td>100</td><td>未提交</td></tr></table>", "12", "Fixture Course", "7", "Fixture Task").unwrap();
    assert_eq!(detail.submission_status, JudgeSubmissionStatus::Unsubmitted);
    assert_eq!(detail.total_problems, 1);
    let dated = judge::parse_detail(
        "作业时间：2026-04-20 19:00:00 至 2026-05-03 23:00:00",
        "12",
        "Fixture Course",
        "7",
        "Fixture Task",
    )
    .unwrap();
    assert_eq!(dated.start_time.as_deref(), Some("2026-04-20 19:00:00"));
    assert_eq!(dated.due_time.as_deref(), Some("2026-05-03 23:00:00"));
}
