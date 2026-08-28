use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EvaluationTask {
    pub rwid: String,
    pub rwmc: String,
    pub questionnaires: Vec<EvaluationQuestionnaire>,
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EvaluationQuestionnaire {
    pub wjid: String,
    pub wjmc: String,
    pub msid: String,
    pub courses: Vec<EvaluationCourse>,
}
/// 一门待评教课程及调用上游所需的稳定字段。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EvaluationCourse {
    pub id: String,
    pub kcmc: String,
    pub bpmc: String,
    pub is_evaluated: bool,
    pub rwid: String,
    pub wjid: String,
    pub kcdm: String,
    pub bpdm: Option<String>,
    pub pjrdm: Option<String>,
    pub pjrmc: Option<String>,
    pub xnxq: Option<String>,
    pub msid: String,
    pub zdmc: Option<String>,
    pub ypjcs: Option<i32>,
    pub xypjcs: Option<i32>,
    pub sxz: Option<String>,
    pub rwh: Option<String>,
    pub xn: Option<String>,
    pub xq: Option<String>,
    pub pjlxid: Option<String>,
    pub sfksqbpj: Option<String>,
    pub yxsfktjst: Option<String>,
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
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EvaluationResult {
    pub success: bool,
    pub message: String,
    pub course_name: String,
}
