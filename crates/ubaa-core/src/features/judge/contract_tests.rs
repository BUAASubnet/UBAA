use super::{parse_assignment_list, parse_courses, parse_detail};
use crate::domain::JudgeSubmissionStatus;

#[test]
fn judge_parser_uses_sanitized_complex_dom_fixtures() {
    let courses = parse_courses(r"<a href='courselist.jsp?courseID=12'>Fixture Course</a>");
    assert_eq!(courses.len(), 1);
    let assignments = parse_assignment_list(
        include_str!("../../../../../fixtures/readonly/judge-assignments.html"),
        &courses[0],
    )
    .assignments;
    assert_eq!(assignments.len(), 1);
    assert_eq!(assignments[0].assignment_id, "101");
    assert_eq!(assignments[0].title, "Lab & Review");

    let detail = parse_detail(
        include_str!("../../../../../fixtures/readonly/judge-detail.html"),
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
