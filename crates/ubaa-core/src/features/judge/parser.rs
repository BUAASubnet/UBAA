//! Judge 课程、作业与详情 HTML 解析。

use scraper::{ElementRef, Html, Selector};

use crate::domain::{
    Assignment, Course, JudgeAssignmentDetail, JudgeAssignmentSummary, JudgeProblem,
    JudgeSubmissionStatus,
};

use super::AssignmentList;

/// 提取课程链接，并排除虚构的课程 0 条目。
pub fn parse_courses(html: &str) -> Vec<Course> {
    let document = Html::parse_document(html);
    let anchors = selector("a[href]");
    let course_id = regex::Regex::new(r"(?i)courselist\.jsp\?courseID=(\d+)")
        .expect("static Judge course id regex");
    let mut courses = Vec::new();
    for anchor in document.select(&anchors) {
        let Some(id) = anchor
            .attr("href")
            .and_then(|href| course_id.captures(href))
            .and_then(|capture| capture.get(1).map(|value| value.as_str()))
        else {
            continue;
        };
        if id == "0" || courses.iter().any(|course: &Course| course.course_id == id) {
            continue;
        }
        let name = element_text(anchor, None);
        if !name.is_empty() {
            courses.push(Course {
                course_id: id.into(),
                course_name: name,
            });
        }
    }
    courses
}

pub(super) fn parse_assignment_list(html: &str, course: &Course) -> AssignmentList {
    let document = Html::parse_document(html);
    let anchors = selector("a[href]");
    let assignment_id =
        regex::Regex::new(r"(?i)assignID=(\d+)").expect("static Judge assignment id regex");
    let mut assignments = Vec::new();
    let mut raw_anchor_count = 0;
    for anchor in document.select(&anchors) {
        let Some(href) = anchor.attr("href") else {
            continue;
        };
        let Some(id) = assignment_id
            .captures(href)
            .and_then(|capture| capture.get(1).map(|value| value.as_str()))
        else {
            continue;
        };
        raw_anchor_count += 1;
        if href.contains("problemContent") || href.contains("judgeDetails") {
            continue;
        }
        if assignments
            .iter()
            .any(|assignment: &Assignment| assignment.assignment_id == id)
        {
            continue;
        }
        let title = element_text(anchor, None);
        if !title.is_empty() {
            assignments.push(Assignment {
                assignment_id: id.into(),
                course_id: course.course_id.clone(),
                course_name: course.course_name.clone(),
                title,
            });
        }
    }
    AssignmentList {
        assignments,
        raw_anchor_count,
    }
}

/// 从有证据支持的作业详情页面解析摘要字段。
// 冻结合同保留 Result 形状，目录收口不顺带改变调用方错误边界。
#[allow(clippy::unnecessary_wraps)]
pub fn parse_detail(
    html: &str,
    course_id: &str,
    course_name: &str,
    assignment_id: &str,
    title: &str,
) -> crate::error::Result<JudgeAssignmentDetail> {
    let document = Html::parse_document(html);
    let body_selector = selector("body");
    let root = document
        .select(&body_selector)
        .next()
        .unwrap_or_else(|| document.root_element());
    let plain = element_text(root, None);
    let max_score = capture_number(&plain, r"作业满分[：:]\s*([\d.]+)");
    let total = capture_number(&plain, r"共\s*(\d+)\s*道")
        .and_then(|value| value.parse().ok())
        .unwrap_or(0);
    let (start_time, due_time) = capture_window(&plain);
    let parsed_problems = parse_problems(&document);
    let earned_scores = parsed_problems
        .iter()
        .filter_map(|problem| problem.earned_score)
        .collect::<Vec<_>>();
    let problems = parsed_problems
        .into_iter()
        .map(|problem| problem.problem)
        .collect::<Vec<_>>();
    let submitted_count = if problems.is_empty() {
        estimate_submitted_count(&plain)
    } else {
        i32::try_from(
            problems
                .iter()
                .filter(|problem| problem.status != JudgeSubmissionStatus::Unsubmitted)
                .count(),
        )
        .unwrap_or(i32::MAX)
    };
    let total_problems = if total == 0 && !problems.is_empty() {
        i32::try_from(problems.len()).unwrap_or(i32::MAX)
    } else {
        total
    };
    let explicit_my_score = capture_number(&plain, r"总分[：:]\s*([\d.]+)");
    let my_score = explicit_my_score
        .or_else(|| (!earned_scores.is_empty()).then(|| format_score(earned_scores.iter().sum())));
    let status = resolve_status(total_problems, submitted_count);
    let normalized_max_score = normalize_score(max_score.as_deref());
    let normalized_my_score = normalize_score(my_score.as_deref());
    Ok(JudgeAssignmentDetail {
        course_id: course_id.into(),
        course_name: course_name.into(),
        assignment_id: assignment_id.into(),
        title: title.into(),
        start_time,
        due_time,
        max_score: normalized_max_score,
        my_score: normalized_my_score,
        total_problems,
        submitted_count,
        submission_status: status,
        submission_status_text: submission_status_text(
            status,
            submitted_count,
            total_problems,
            my_score.as_deref(),
            max_score.as_deref(),
        ),
        problems,
        content_plain_text: (!plain.is_empty()).then_some(plain),
    })
}

/// 将一项详情转换为稳定列表摘要。
#[must_use]
pub fn to_summary(detail: &JudgeAssignmentDetail) -> JudgeAssignmentSummary {
    JudgeAssignmentSummary {
        course_id: detail.course_id.clone(),
        course_name: detail.course_name.clone(),
        assignment_id: detail.assignment_id.clone(),
        title: detail.title.clone(),
        start_time: detail.start_time.clone(),
        due_time: detail.due_time.clone(),
        max_score: detail.max_score.clone(),
        my_score: detail.my_score.clone(),
        total_problems: detail.total_problems,
        submitted_count: detail.submitted_count,
        submission_status: detail.submission_status,
        submission_status_text: detail.submission_status_text.clone(),
    }
}

fn capture_number(text: &str, pattern: &str) -> Option<String> {
    regex::Regex::new(pattern)
        .expect("static Judge number regex")
        .captures(text)
        .and_then(|capture| capture.get(1).map(|value| value.as_str().to_string()))
}

fn capture_window(text: &str) -> (Option<String>, Option<String>) {
    let regex = regex::Regex::new(
        r"作业时间[：:]\s*(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}(?::\d{2})?)\s*至\s*(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}(?::\d{2})?)",
    )
    .expect("static Judge date regex");
    let Some(capture) = regex.captures(text) else {
        return (None, None);
    };
    (
        capture
            .get(1)
            .map(|value| normalize_datetime(value.as_str())),
        capture
            .get(2)
            .map(|value| normalize_datetime(value.as_str())),
    )
}

fn normalize_datetime(value: &str) -> String {
    if value.matches(':').count() == 1 {
        format!("{value}:00")
    } else {
        value.to_string()
    }
}

struct ParsedProblem {
    problem: JudgeProblem,
    earned_score: Option<f64>,
}

fn parse_problems(document: &Html) -> Vec<ParsedProblem> {
    let table_selector = selector("table");
    let row_selector = selector("tr");
    let mut problems = Vec::new();
    for table in document.select(&table_selector).filter(|table| {
        !table
            .ancestors()
            .filter_map(ElementRef::wrap)
            .any(|ancestor| ancestor.value().name() == "table")
    }) {
        for row in table
            .select(&row_selector)
            .filter(|row| nearest_ancestor_table(*row).is_some_and(|owner| owner == table))
        {
            let cells = row
                .child_elements()
                .filter(|cell| matches!(cell.value().name(), "th" | "td"))
                .map(|cell| element_text(cell, Some(table)))
                .collect::<Vec<_>>();
            if let Some(problem) = parse_problem_from_cells(&cells) {
                problems.push(problem);
            }
        }
    }
    problems
}

fn nearest_ancestor_table(element: ElementRef<'_>) -> Option<ElementRef<'_>> {
    element
        .ancestors()
        .filter_map(ElementRef::wrap)
        .find(|ancestor| ancestor.value().name() == "table")
}

fn parse_problem_from_cells(cells: &[String]) -> Option<ParsedProblem> {
    if cells.len() >= 4 {
        let max_score = parse_number(&cells[2])?;
        let status_text = cells[3..].join(" ");
        let status = detect_problem_status(&status_text)?;
        let earned_score = parse_earned_score(&status_text);
        let score = earned_score
            .or((status == JudgeSubmissionStatus::Submitted).then_some(max_score))
            .map(format_score);
        return Some(ParsedProblem {
            problem: JudgeProblem {
                name: cells[1].clone(),
                score,
                max_score: Some(format_score(max_score)),
                status,
                status_text: problem_status_text(status).into(),
            },
            earned_score,
        });
    }

    if cells.len() == 2 {
        let status = detect_problem_status(&cells[1])?;
        let earned_score = parse_earned_score(&cells[1]);
        let index = cells[0].trim().trim_end_matches('.');
        return Some(ParsedProblem {
            problem: JudgeProblem {
                name: if index.is_empty() {
                    "题目".into()
                } else {
                    format!("第{index}题")
                },
                score: earned_score.map(format_score),
                max_score: earned_score.map(format_score),
                status,
                status_text: problem_status_text(status).into(),
            },
            earned_score,
        });
    }

    None
}

fn estimate_submitted_count(text: &str) -> i32 {
    let first_section = ["填空题", "编程题", "文件上传题"]
        .iter()
        .filter_map(|section| text.find(section))
        .min()
        .unwrap_or(text.len());
    let choice_count = count_matches(&text[..first_section], r"得分[：:]\s*[\d.]+");

    let fill_answer_count = text.find("填空题").map_or(0, |start| {
        let after_heading = start + "填空题".len();
        let next_section = ["编程题", "文件上传题"]
            .iter()
            .filter_map(|section| {
                text[after_heading..]
                    .find(section)
                    .map(|offset| after_heading + offset)
            })
            .min()
            .unwrap_or(text.len());
        count_matches(&text[start..next_section], r"得分[：:]\s*[\d.]+")
    });
    let programming_count = text.find("编程题").map_or(0, |start| {
        count_matches(&text[start..], r"最后一次提交时间")
    });
    let file_upload_count = text
        .find("文件上传题")
        .map_or(0, |start| count_matches(&text[start..], r"初次提交时间"));
    i32::try_from(choice_count + fill_answer_count + programming_count + file_upload_count)
        .unwrap_or(i32::MAX)
}

fn count_matches(text: &str, pattern: &str) -> usize {
    regex::Regex::new(pattern)
        .expect("static Judge fallback regex")
        .find_iter(text)
        .count()
}

fn detect_problem_status(text: &str) -> Option<JudgeSubmissionStatus> {
    const UNSUBMITTED: &[&str] = &[
        "还未提交代码",
        "未提交文件",
        "未提交答案",
        "未作答",
        "未提交",
    ];
    const SUBMITTED: &[&str] = &[
        "初次提交时间",
        "首次提交时间",
        "最近一次提交时间",
        "最后一次提交时间",
        "最后一次修改时间",
        "已提交",
        "得分",
        "Accepted",
        "Accept",
    ];
    let normalized = normalize_text(text);
    if UNSUBMITTED.iter().any(|marker| normalized.contains(marker)) {
        return Some(JudgeSubmissionStatus::Unsubmitted);
    }
    let lowercase = normalized.to_lowercase();
    SUBMITTED
        .iter()
        .any(|marker| lowercase.contains(&marker.to_lowercase()))
        .then_some(JudgeSubmissionStatus::Submitted)
}

fn resolve_status(total_problems: i32, submitted_count: i32) -> JudgeSubmissionStatus {
    if total_problems <= 0 {
        JudgeSubmissionStatus::Unknown
    } else if submitted_count <= 0 {
        JudgeSubmissionStatus::Unsubmitted
    } else if submitted_count < total_problems {
        JudgeSubmissionStatus::Partial
    } else {
        JudgeSubmissionStatus::Submitted
    }
}

fn submission_status_text(
    status: JudgeSubmissionStatus,
    submitted_count: i32,
    total_problems: i32,
    my_score: Option<&str>,
    max_score: Option<&str>,
) -> String {
    match status {
        JudgeSubmissionStatus::Submitted => match (my_score, max_score) {
            (Some(my_score), Some(max_score)) if !my_score.is_empty() && !max_score.is_empty() => {
                format!("已完成 {my_score}/{max_score}")
            }
            _ => "已完成".into(),
        },
        JudgeSubmissionStatus::Partial => {
            format!("进行中({submitted_count}/{total_problems})")
        }
        JudgeSubmissionStatus::Unsubmitted => "未提交".into(),
        JudgeSubmissionStatus::Unknown => "未知状态".into(),
    }
}

fn problem_status_text(status: JudgeSubmissionStatus) -> &'static str {
    match status {
        JudgeSubmissionStatus::Submitted => "已提交",
        JudgeSubmissionStatus::Partial => "部分提交",
        JudgeSubmissionStatus::Unsubmitted => "未提交",
        JudgeSubmissionStatus::Unknown => "未知状态",
    }
}

fn parse_number(value: &str) -> Option<f64> {
    let value = normalize_text(value);
    regex::Regex::new(r"^\d+(?:\.\d+)?$")
        .expect("static Judge numeric regex")
        .is_match(&value)
        .then(|| value.parse().ok())
        .flatten()
}

fn parse_earned_score(value: &str) -> Option<f64> {
    capture_number(&normalize_text(value), r"得分[：:]\s*([\d.]+)")?
        .parse()
        .ok()
}

fn normalize_score(value: Option<&str>) -> Option<String> {
    value.map(|value| {
        value
            .parse::<f64>()
            .map_or_else(|_| value.to_string(), format_score)
    })
}

fn format_score(value: f64) -> String {
    if value.fract() == 0.0 {
        format!("{value:.0}")
    } else {
        value.to_string()
    }
}

fn selector(query: &str) -> Selector {
    Selector::parse(query).expect("static Judge selector")
}

fn element_text(element: ElementRef<'_>, owning_table: Option<ElementRef<'_>>) -> String {
    let mut pieces = Vec::new();
    for node in element.descendants() {
        let Some(text) = node.value().as_text() else {
            continue;
        };
        let allowed = node
            .ancestors()
            .take_while(|ancestor| ancestor.id() != element.id())
            .filter_map(ElementRef::wrap)
            .all(|ancestor| match ancestor.value().name() {
                "script" | "style" => false,
                "table" => owning_table.is_none() || owning_table == Some(ancestor),
                _ => true,
            });
        if allowed {
            pieces.push(text.to_string());
        }
    }
    normalize_text(&pieces.join(" "))
}

fn normalize_text(value: &str) -> String {
    value
        .replace('\u{00a0}', " ")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}
