use serde::{Deserialize, Serialize};

/// 一门课程成绩。
#[derive(Clone, Debug, Default, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Grade {
    #[serde(default)]
    pub graduate: bool,
    pub term_name: Option<String>,
    pub average_score: Option<f64>,
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

/// Core 计算的研究生统计；无有效分母时为 None。
#[derive(Clone, Debug, Default, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GradeStatistics {
    pub gpa: Option<f64>,
    pub average_score: Option<f64>,
    pub gpa_credits: f64,
    pub average_credits: f64,
}

/// 成绩自身提供的历史学期及其统计。
#[derive(Clone, Debug, Default, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GradeTermStatistics {
    pub term_code: String,
    pub term_name: String,
    pub statistics: GradeStatistics,
}

/// 研究生完整成绩；本科返回 graduate=false，继续使用原本科学期入口。
#[derive(Clone, Debug, Default, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GradeOverview {
    pub graduate: bool,
    pub grades: Vec<Grade>,
    pub statistics: Option<GradeStatistics>,
    pub terms: Vec<GradeTermStatistics>,
}
