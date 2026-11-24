//! SPOC 作业领域类型。

use serde::{Deserialize, Serialize};

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
    /// 纯文本描述。
    pub content_plain_text: Option<String>,
    /// 提交时间。
    pub submitted_at: Option<String>,
    #[serde(skip)]
    pub attachment: Option<SpocAttachment>,
    #[serde(skip)]
    pub submitted_file: Option<SpocSubmittedFile>,
    #[serde(skip)]
    pub submission_count: Option<u32>,
    #[serde(skip)]
    pub submit_modes: Vec<String>,
    #[serde(skip)]
    pub allowed_extensions: Vec<String>,
    #[serde(skip)]
    pub max_submissions: Option<u32>,
    #[serde(skip)]
    pub is_group_assignment: bool,
    #[serde(skip)]
    pub late_submission_deadline: Option<String>,
    #[serde(skip)]
    pub submit_action: Option<SpocSubmitAction>,
    #[serde(skip)]
    pub submit_unavailable_reason: Option<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SpocSubmitAction {
    pub assignment_id: String,
    pub course_id: String,
    pub allowed_extensions: Vec<String>,
    pub max_submissions: Option<u32>,
    pub due_time: Option<String>,
    pub late_submission_deadline: Option<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SpocSubmitSummary {
    pub title: String,
    pub course_name: String,
    pub file_name: String,
    pub byte_len: u64,
    pub due_time: Option<String>,
    pub past_due: Option<bool>,
    pub late_submission_deadline: Option<String>,
    pub submission_count: Option<u32>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SpocSubmitReceipt {
    pub submitted_at: Option<String>,
    pub file_name: String,
    pub file_id: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SpocAttachment {
    pub file_id: String,
    pub file_name: Option<String>,
    pub size_text: Option<String>,
    pub extension: Option<String>,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SpocSubmittedFile {
    pub file_id: String,
    pub file_name: Option<String>,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SpocCourse {
    pub course_id: String,
    pub name: String,
    pub teacher: Option<String>,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SpocCourseFile {
    pub id: String,
    pub name: String,
    pub is_folder: bool,
    pub size_text: Option<String>,
    pub extension: Option<String>,
    pub uploaded_at_text: Option<String>,
    pub download_allowed: bool,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum SpocDownloadTarget {
    AssignmentFile {
        file_id: String,
        file_name: Option<String>,
    },
    CourseFile {
        id: String,
        name: String,
    },
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SpocDownloadReceipt {
    pub file_name: String,
    pub byte_len: u64,
}
