//! Judge parser、批量调度与日期边界的单元合同。

use super::calendar::{six_month_cutoff_from_shanghai, started_before_cutoff};
use super::parser::parse_assignment_list;
use super::{Course, parse_courses, parse_detail};
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

fn fixture_course() -> Course {
    Course {
        course_id: "12".into(),
        course_name: "Fixture Course".into(),
    }
}

#[test]
fn assignments_filter_internal_links_before_deduplication() {
    let parsed = parse_assignment_list(
        r#"
            <a href="problemContent.jsp?assignID=7">Internal problem</a>
            <a href="assignment/index.jsp?assignID=7">Fixture &amp; Review</a>
            <a href="judgeDetails.jsp?assignID=8">Internal details</a>
            <a href="assignment/index.jsp?assignID=8">Second task</a>
            <a href="assignment/index.jsp?ASSIGNid=9">Case insensitive task</a>
            <a href="assignment/index.jsp?assignID=not-a-number">Invalid task</a>
            "#,
        &fixture_course(),
    );

    assert_eq!(parsed.raw_anchor_count, 5);
    assert_eq!(parsed.filtered_unique_count(), 3);
    assert_eq!(
        parsed
            .assignments
            .iter()
            .map(|assignment| (assignment.assignment_id.as_str(), assignment.title.as_str()))
            .collect::<Vec<_>>(),
        vec![
            ("7", "Fixture & Review"),
            ("8", "Second task"),
            ("9", "Case insensitive task")
        ]
    );
}

#[test]
fn assignments_keep_raw_count_when_every_numeric_anchor_is_filtered() {
    let parsed = parse_assignment_list(
        r#"
            <a href="problemContent.jsp?assignID=7">Internal problem</a>
            <a href="judgeDetails.jsp?assignID=8">Internal details</a>
            <a href="assignment/index.jsp?assignID=9"><span> </span></a>
            "#,
        &fixture_course(),
    );

    assert_eq!(parsed.raw_anchor_count, 3);
    assert_eq!(parsed.filtered_unique_count(), 0);
    assert!(parsed.assignments.is_empty());
}

#[test]
fn detail_parses_four_cell_rows_without_nested_table_or_script_noise() {
    let detail = parse_detail(
        r#"
            <html>
              <head>
              </head>
              <body>
                <style>.score::after { content: "总分：999"; }</style>
                <script>const fake = "作业满分：999 总分：999";</script>
                作业时间：2026-04-20 19:00 至 2026-05-03 23:00
                作业满分：20.00，共 2 道题
                <table>
                  <thead><tr><th>#</th><th>题目</th><th>分值</th><th>状态</th></tr></thead>
                  <tbody>
                    <tr>
                      <th>1.</th><td>程序 &amp; 设计</td><td>10.00</td>
                      <td>最后一次提交时间：2026-04-17 12:00:00 得分：8.00
                        <table>
                          <tr><th>name</th><th>verdict</th></tr>
                          <tr><td>TestCase1</td><td>Accept</td></tr>
                        </table>
                      </td>
                    </tr>
                    <tr><th>2.</th><td>报告</td><td>10.00</td><td>未提交答案</td></tr>
                  </tbody>
                </table>
              </body>
            </html>
            "#,
        "12",
        "Fixture Course",
        "7",
        "Fixture Task",
    )
    .unwrap();

    assert_eq!(detail.start_time.as_deref(), Some("2026-04-20 19:00:00"));
    assert_eq!(detail.due_time.as_deref(), Some("2026-05-03 23:00:00"));
    assert_eq!(detail.max_score.as_deref(), Some("20"));
    assert_eq!(detail.my_score.as_deref(), Some("8"));
    assert_eq!(detail.total_problems, 2);
    assert_eq!(detail.submitted_count, 1);
    assert_eq!(detail.submission_status, JudgeSubmissionStatus::Partial);
    assert_eq!(detail.submission_status_text, "进行中(1/2)");
    assert_eq!(detail.problems.len(), 2);
    assert_eq!(detail.problems[0].name, "程序 & 设计");
    assert_eq!(detail.problems[0].score.as_deref(), Some("8"));
    assert_eq!(detail.problems[0].max_score.as_deref(), Some("10"));
    assert_eq!(detail.problems[0].status, JudgeSubmissionStatus::Submitted);
    assert_eq!(
        detail.problems[1].status,
        JudgeSubmissionStatus::Unsubmitted
    );
    let content = detail.content_plain_text.as_deref().unwrap();
    assert!(content.contains("程序 & 设计"));
    assert!(content.contains("TestCase1"));
    assert!(!content.contains("const fake"));
    assert!(!content.contains("content:"));
}

#[test]
fn detail_parses_two_cell_rows_and_normalizes_scores() {
    let detail = parse_detail(
            r"
            作业满分：2.00，共 2 道题
            <table><tbody>
              <tr><th>1.</th><td>已提交 最后一次提交时间：2026-04-14 19:38:39 题干 得分：1.00</td></tr>
              <tr><th>2.</th><td>未作答 题干</td></tr>
            </tbody></table>
            ",
            "12",
            "Fixture Course",
            "8",
            "Choice Task",
        )
        .unwrap();

    assert_eq!(detail.max_score.as_deref(), Some("2"));
    assert_eq!(detail.my_score.as_deref(), Some("1"));
    assert_eq!(detail.submission_status, JudgeSubmissionStatus::Partial);
    assert_eq!(
        detail
            .problems
            .iter()
            .map(|problem| problem.name.as_str())
            .collect::<Vec<_>>(),
        vec!["第1题", "第2题"]
    );
    assert_eq!(detail.problems[0].max_score.as_deref(), Some("1"));
    assert_eq!(detail.problems[1].max_score, None);
}

#[test]
fn detail_uses_frozen_fallback_and_status_rules() {
    let partial = parse_detail(
            "作业满分：4，共 4 道题 选择题 得分：1 填空题 得分：1 编程题 最后一次提交时间：2026-01-01 12:00:00",
            "12",
            "Fixture Course",
            "9",
            "Fallback Task",
        )
        .unwrap();
    assert_eq!(partial.submitted_count, 3);
    assert_eq!(partial.submission_status, JudgeSubmissionStatus::Partial);
    assert_eq!(partial.submission_status_text, "进行中(3/4)");

    let unknown = parse_detail(
        "<p>No verified assignment fields</p>",
        "12",
        "Fixture Course",
        "10",
        "Unknown",
    )
    .unwrap();
    assert_eq!(unknown.total_problems, 0);
    assert_eq!(unknown.submission_status, JudgeSubmissionStatus::Unknown);
    assert_eq!(unknown.submission_status_text, "未知状态");
}

#[test]
fn detail_prefers_explicit_score_and_resolves_terminal_statuses() {
    let submitted = parse_detail(
        r"
            作业满分：10.00，共 1 道题，总分：7.00
            <table><tbody>
              <tr><th>1.</th><td>Fixture</td><td>10.00</td><td>已提交 得分：8.00</td></tr>
            </tbody></table>
            ",
        "12",
        "Fixture Course",
        "11",
        "Submitted",
    )
    .unwrap();
    assert_eq!(submitted.my_score.as_deref(), Some("7"));
    assert_eq!(submitted.max_score.as_deref(), Some("10"));
    assert_eq!(submitted.submitted_count, 1);
    assert_eq!(
        submitted.submission_status,
        JudgeSubmissionStatus::Submitted
    );
    assert_eq!(submitted.submission_status_text, "已完成 7.00/10.00");

    let unsubmitted = parse_detail(
        "作业满分：10，共 1 道题 未提交",
        "12",
        "Fixture Course",
        "12",
        "Unsubmitted",
    )
    .unwrap();
    assert_eq!(unsubmitted.submitted_count, 0);
    assert_eq!(
        unsubmitted.submission_status,
        JudgeSubmissionStatus::Unsubmitted
    );
    assert_eq!(unsubmitted.submission_status_text, "未提交");
}

#[test]
fn six_month_cutoff_preserves_time_and_clamps_month_end() {
    assert_eq!(
        six_month_cutoff_from_shanghai("2024-08-31 12:34:56").as_deref(),
        Some("2024-02-29 12:34:56")
    );
    assert_eq!(
        six_month_cutoff_from_shanghai("2023-08-31 01:02:03").as_deref(),
        Some("2023-02-28 01:02:03")
    );
    assert_eq!(
        six_month_cutoff_from_shanghai("2026-03-31 23:59:58").as_deref(),
        Some("2025-09-30 23:59:58")
    );
    assert_eq!(six_month_cutoff_from_shanghai("invalid"), None);
}

#[test]
fn historical_start_requires_a_valid_datetime_and_full_time_ordering() {
    let cutoff = "2026-02-24 12:34:56";

    assert!(!started_before_cutoff("0000-00-00 00:00:00", cutoff));
    assert!(!started_before_cutoff("2026-02-30 12:34:55", cutoff));
    assert!(!started_before_cutoff("2026-02-24 24:00:00", cutoff));
    assert!(started_before_cutoff("2026-02-24 12:34:55", cutoff));
    assert!(!started_before_cutoff("2026-02-24 12:34:56", cutoff));
}
