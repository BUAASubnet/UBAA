use serde::{Deserialize, Serialize};

/// 一门课程成绩。
#[derive(Clone, Debug, Default, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Grade {
    pub course_name: Option<String>,
    pub course_code: Option<String>,
    pub credit: Option<f64>,
    pub score: Option<String>,
    pub grade_point: Option<String>,
    pub course_type: Option<String>,
    pub score_type: Option<String>,
    pub term_code: Option<String>,
}
/// 指定学期的成绩。
#[derive(Clone, Debug, Default, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GradeData {
    pub term_code: String,
    pub grades: Vec<Grade>,
}
