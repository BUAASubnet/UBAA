//! 健康云成绩页的最小读取投影。
use serde::{Deserialize, Serialize};

/// 站点提供的年份和不透明的查询键。
#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
pub struct HealthCloudYear {
    pub year: u16,
    pub key: String,
}

/// 单项原始表现、分数和等级。空白项与零分分开。
#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
pub struct HealthCloudEvent {
    pub name: String,
    pub result: Option<String>,
    pub score: Option<f64>,
    pub grade: Option<String>,
}

/// 某年度体测成绩。
#[derive(Clone, Debug, Default, Deserialize, PartialEq, Serialize)]
pub struct HealthCloudReport {
    pub height_cm: Option<f64>,
    pub weight_kg: Option<f64>,
    pub lung_ml: Option<f64>,
    pub reach_cm: Option<f64>,
    pub events: Vec<HealthCloudEvent>,
}

/// 页面每次返回最新的年份列表。
#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
pub struct HealthCloudPage {
    pub years: Vec<HealthCloudYear>,
    pub selected_year: Option<String>,
    pub report: Option<HealthCloudReport>,
}
