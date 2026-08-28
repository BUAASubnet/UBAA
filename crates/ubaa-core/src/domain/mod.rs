//! Core facade 与宿主绑定共享的稳定领域值。

use serde::{Deserialize, Serialize};

mod auth;
pub use auth::*;
mod route;
pub use route::*;
mod bykc;
pub use bykc::*;
mod libbook;
pub use libbook::*;
mod ygdk;
pub use ygdk::*;
mod evaluation;
pub use evaluation::*;
mod signin;
pub use signin::*;
mod schedule;
pub use schedule::*;
mod grades;
pub use grades::*;
mod classroom;
pub use classroom::*;
mod cgyy;
pub use cgyy::*;

/// SPOC 提交状态。
#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum SpocSubmissionStatus {
    /// 已提交。
    Submitted,
    /// 未提交。
    Unsubmitted,
    /// 未知的上游状态。
    #[default]
    Unknown,
}

/// SPOC 作业摘要。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SpocAssignmentSummary {
    /// 作业标识。
    pub assignment_id: String,
    /// 课程标识。
    pub course_id: String,
    /// 课程名称。
    pub course_name: String,
    /// 教师姓名。
    pub teacher_name: Option<String>,
    /// 作业标题。
    pub title: String,
    /// 开始时间。
    pub start_time: Option<String>,
    /// 截止时间。
    pub due_time: Option<String>,
    /// 成绩。
    pub score: Option<String>,
    /// 提交状态。
    pub submission_status: SpocSubmissionStatus,
    /// 可安全展示的状态文本。
    pub submission_status_text: String,
}

/// SPOC 作业列表。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SpocAssignments {
    /// 当前学期代码。
    pub term_code: String,
    /// 当前学期名称。
    pub term_name: Option<String>,
    /// 作业列表。
    pub assignments: Vec<SpocAssignmentSummary>,
}

/// 一次 SPOC 全局列表操作的安全完成证据。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SpocAssignmentsDiagnostics {
    /// 成功解析的权威全局作业页数量。
    pub global_page_count: u32,
    /// 普通稳定作业列表结果。
    pub result: SpocAssignments,
}

/// SPOC 作业详情。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SpocAssignmentDetail {
    /// Assignment ID.
    pub assignment_id: String,
    /// Course ID.
    pub course_id: String,
    /// Course name.
    pub course_name: String,
    /// Teacher name.
    pub teacher_name: Option<String>,
    /// Assignment title.
    pub title: String,
    /// Start time.
    pub start_time: Option<String>,
    /// Due time.
    pub due_time: Option<String>,
    /// Score.
    pub score: Option<String>,
    /// Submission status.
    pub submission_status: SpocSubmissionStatus,
    /// Safe status text.
    pub submission_status_text: String,
    /// 纯文本描述。
    pub content_plain_text: Option<String>,
    /// 提交时间。
    pub submitted_at: Option<String>,
}

/// 希冀提交状态。
#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum JudgeSubmissionStatus {
    /// 已全部提交。
    Submitted,
    /// 部分提交。
    Partial,
    /// 未提交。
    Unsubmitted,
    /// 未知状态。
    #[default]
    Unknown,
}

/// 希冀作业摘要。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JudgeAssignmentSummary {
    /// Course ID.
    pub course_id: String,
    /// Course name.
    pub course_name: String,
    /// Assignment ID.
    pub assignment_id: String,
    /// Assignment title.
    pub title: String,
    /// Start time.
    pub start_time: Option<String>,
    /// Due time.
    pub due_time: Option<String>,
    /// 最高分。
    pub max_score: Option<String>,
    /// 用户得分。
    pub my_score: Option<String>,
    /// 题目数量。
    pub total_problems: i32,
    /// 已提交数量。
    pub submitted_count: i32,
    /// 提交状态。
    pub submission_status: JudgeSubmissionStatus,
    /// 可安全展示的状态文本。
    pub submission_status_text: String,
}

/// 一次希冀列表操作的安全解析诊断。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JudgeAssignmentsDiagnostics {
    /// 跳过历史课程前解析出的课程数量。
    pub course_count: usize,
    /// 过滤和去重前发现的数字作业锚点数量。
    pub raw_anchor_count: usize,
    /// 解析器过滤后保留的非空唯一作业数量。
    pub filtered_unique_count: usize,
    /// 应用 `include_expired` 后的普通希冀摘要。
    pub summaries: Vec<JudgeAssignmentSummary>,
}

/// 希冀作业详情键。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JudgeAssignmentKey {
    /// Course ID.
    pub course_id: String,
    /// Assignment ID.
    pub assignment_id: String,
}

/// 希冀题目详情。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JudgeProblem {
    /// 题目名称。
    pub name: String,
    /// 获得分数。
    pub score: Option<String>,
    /// 最高分。
    pub max_score: Option<String>,
    /// 提交状态。
    pub status: JudgeSubmissionStatus,
    /// 可安全展示的状态文本。
    pub status_text: String,
}

/// 希冀作业详情。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JudgeAssignmentDetail {
    /// Course ID.
    pub course_id: String,
    /// Course name.
    pub course_name: String,
    /// Assignment ID.
    pub assignment_id: String,
    /// Assignment title.
    pub title: String,
    /// Start time.
    pub start_time: Option<String>,
    /// Due time.
    pub due_time: Option<String>,
    /// Maximum score.
    pub max_score: Option<String>,
    /// 用户得分。
    pub my_score: Option<String>,
    /// Number of problems.
    pub total_problems: i32,
    /// Number submitted.
    pub submitted_count: i32,
    /// Submission state.
    pub submission_status: JudgeSubmissionStatus,
    /// Safe status text.
    pub submission_status_text: String,
    /// 解析后的题目列表。
    pub problems: Vec<JudgeProblem>,
    /// HTML 内容转换后的纯文本。
    pub content_plain_text: Option<String>,
}
