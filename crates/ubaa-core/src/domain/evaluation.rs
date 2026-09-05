use serde::{Deserialize, Serialize};

use super::ActionEligibility;

/// 一门评教课程的安全公开投影。
///
/// 上游题目查询和提交所需字段只保留在 Core 的单次 fresh authority 中；宿主只能
/// 回传 `submit_target`，不得构造或覆盖这些内部字段。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EvaluationCourse {
    pub id: String,
    pub kcmc: String,
    pub bpmc: String,
    pub is_evaluated: bool,
    pub submit_eligibility: ActionEligibility,
    pub submit_target: Option<EvaluationSubmitTarget>,
}

/// 由 Core 从 fresh 课程 authority 派生的稳定评教目标。
///
/// `bpdm=None` 与空字符串在冻结协议 identity 中同属空末段，但 DTO 保留缺失语义。
#[derive(Clone, Debug, Default, Deserialize, Eq, Hash, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EvaluationSubmitTarget {
    pub rwid: String,
    pub wjid: String,
    pub kcdm: String,
    pub bpdm: Option<String>,
}

/// 评教 typed 批量提交请求。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EvaluationSubmitCoursesRequest {
    pub targets: Vec<EvaluationSubmitTarget>,
}

/// Core 在 prepare 阶段 fresh 复核形成的安全摘要。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EvaluationSubmitPreflight {
    pub targets: Vec<EvaluationSubmitTarget>,
    pub courses: Vec<EvaluationCourse>,
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EvaluationProgress {
    pub total_courses: i32,
    pub evaluated_courses: i32,
    pub pending_courses: i32,
}
impl EvaluationProgress {
    #[must_use]
    pub fn progress_percent(&self) -> i32 {
        if self.total_courses > 0 {
            self.evaluated_courses.saturating_mul(100) / self.total_courses
        } else {
            0
        }
    }
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EvaluationCoursesResponse {
    pub courses: Vec<EvaluationCourse>,
    pub progress: EvaluationProgress,
}
/// 单门课程评教的封闭结果。
#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum EvaluationCourseOutcome {
    Success,
    Failure,
    OutcomeUnknown,
    #[default]
    Unattempted,
}

/// 单门课程评教的固定安全结果。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EvaluationCourseResult {
    pub target: EvaluationSubmitTarget,
    pub course_name: String,
    pub outcome: EvaluationCourseOutcome,
    pub message: String,
}

/// 按请求顺序返回的评教批量结果。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EvaluationBatchResult {
    pub items: Vec<EvaluationCourseResult>,
    pub success: bool,
    pub outcome_unknown: bool,
}
