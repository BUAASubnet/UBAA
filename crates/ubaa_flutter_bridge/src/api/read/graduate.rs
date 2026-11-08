//! 研究生完整成绩的稳定投影。
use super::{BridgeGrade, BridgeRouteDecision};
use ubaa_core::facade as domain;
#[derive(Clone, Debug)]
pub struct BridgeGradeStatistics {
    pub gpa: Option<f64>,
    pub average_score: Option<f64>,
    pub gpa_credits: f64,
    pub average_credits: f64,
}
#[derive(Clone, Debug)]
pub struct BridgeGradeTermStatistics {
    pub term_code: String,
    pub term_name: String,
    pub statistics: BridgeGradeStatistics,
}
#[derive(Clone, Debug)]
pub struct BridgeGradeOverview {
    pub graduate: bool,
    pub grades: Vec<BridgeGrade>,
    pub statistics: Option<BridgeGradeStatistics>,
    pub terms: Vec<BridgeGradeTermStatistics>,
}
#[derive(Clone, Debug)]
pub struct BridgeRoutedGradeOverview {
    pub data: BridgeGradeOverview,
    pub route: BridgeRouteDecision,
}
pub(super) fn stats(v: domain::GradeStatistics) -> BridgeGradeStatistics {
    BridgeGradeStatistics {
        gpa: v.gpa,
        average_score: v.average_score,
        gpa_credits: v.gpa_credits,
        average_credits: v.average_credits,
    }
}
pub(super) fn map_overview(v: domain::GradeOverview) -> BridgeGradeOverview {
    let grades = super::mappers::map_grade_data(domain::GradeData {
        statistics: None,
        term_code: String::new(),
        grades: v.grades,
    })
    .grades;
    BridgeGradeOverview {
        graduate: v.graduate,
        grades,
        statistics: v.statistics.map(stats),
        terms: v
            .terms
            .into_iter()
            .map(|t| BridgeGradeTermStatistics {
                term_code: t.term_code,
                term_name: t.term_name,
                statistics: stats(t.statistics),
            })
            .collect(),
    }
}
