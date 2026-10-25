//! iHome 公开业务数据；不保留上游用户对象及凭据。
#![allow(missing_docs)]
use serde::{Deserialize, Serialize};
#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum IhomeScope {
    #[default]
    Public,
    Mine,
    Followed,
    Appraised,
}
#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum IhomeFilter {
    #[default]
    All,
    Newest,
    Oldest,
    Replied,
    Unreplied,
    ReplyTime,
}
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct IhomeQuery {
    pub scope: IhomeScope,
    pub page: i32,
    pub limit: i32,
    pub keyword: String,
    pub filter: IhomeFilter,
    pub category_id: Option<i64>,
}
impl Default for IhomeQuery {
    fn default() -> Self {
        Self {
            scope: IhomeScope::Public,
            page: 1,
            limit: 15,
            keyword: String::new(),
            filter: IhomeFilter::All,
            category_id: None,
        }
    }
}
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct IhomePage {
    pub entries: Vec<IhomeEntry>,
    pub page: i32,
    pub last_page: i32,
    pub total: i32,
}
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct IhomeEntry {
    pub appeal: IhomeAppeal,
    pub evaluation: Option<IhomeEvaluation>,
}
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct IhomeAppeal {
    pub id: i64,
    pub content: String,
    pub status: String,
    pub category: String,
    pub published_at: String,
    pub departments: Vec<String>,
    pub is_mine: bool,
    pub is_followed: Option<bool>,
    pub is_supported: Option<bool>,
    pub follow_count: Option<i32>,
    pub support_count: Option<i32>,
    pub replies: Vec<IhomeReply>,
    pub evaluations: Vec<IhomeEvaluation>,
    pub history: Vec<IhomeHistory>,
}
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct IhomeReply {
    pub content: String,
    pub department: String,
    pub created_at: String,
}
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct IhomeHistory {
    pub content: String,
    pub created_at: String,
}
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct IhomeEvaluation {
    pub id: i64,
    pub department: String,
    pub speed: i32,
    pub satisfaction: i32,
    pub degree: i32,
    pub content: String,
    pub created_at: String,
}
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct IhomeCategory {
    pub id: i64,
    pub name: String,
}
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct IhomeConfig {
    pub support_enabled: bool,
    pub support_label: String,
    pub categories: Vec<IhomeCategory>,
}
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct IhomeNotice {
    pub id: i64,
    pub title: String,
    pub content: String,
    pub date: String,
}
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum IhomeReaction {
    Follow,
    Support,
}
