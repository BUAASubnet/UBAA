use serde::{Deserialize, Serialize};

/// 空闲教室查询响应。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClassroomQuery {
    pub code: i32,
    pub message: String,
    pub floors: std::collections::BTreeMap<String, Vec<ClassroomInfo>>,
}
/// 一间可用教室。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClassroomInfo {
    pub id: String,
    pub floor_id: String,
    pub name: String,
    pub available_sections: String,
}
