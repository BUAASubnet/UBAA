//! 阳光记录只保留已公开展示字段，图片仅保存数量。
use crate::domain::{YgdkRecord, YgdkRecordsPage};
use serde::{Deserialize, Serialize};
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct CachedYgdkRecordsSelection {
    pub classify_id: i32,
    pub classify_name: String,
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct CachedYgdkRecord {
    pub record_id: i32,
    pub item_id: Option<i32>,
    pub item_name: Option<String>,
    pub start_time: Option<String>,
    pub end_time: Option<String>,
    pub place: Option<String>,
    pub image_count: i32,
    pub is_open: bool,
    pub state: Option<i32>,
    pub created_at: Option<String>,
    pub created_at_label: Option<String>,
}
impl From<YgdkRecord> for CachedYgdkRecord {
    fn from(v: YgdkRecord) -> Self {
        Self {
            record_id: v.record_id,
            item_id: v.item_id,
            item_name: v.item_name,
            start_time: v.start_time,
            end_time: v.end_time,
            place: v.place,
            image_count: i32::try_from(v.images.len()).unwrap_or(i32::MAX),
            is_open: v.is_open,
            state: v.state,
            created_at: v.created_at,
            created_at_label: v.created_at_label,
        }
    }
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct CachedYgdkRecordsPage {
    pub classify_id: i32,
    pub content: Vec<CachedYgdkRecord>,
    pub total: i32,
    pub page: i32,
    pub size: i32,
    pub has_more: bool,
}
impl CachedYgdkRecordsPage {
    pub(crate) fn from_page(classify_id: i32, v: YgdkRecordsPage) -> Self {
        Self {
            classify_id,
            content: v.content.into_iter().map(Into::into).collect(),
            total: v.total,
            page: v.page,
            size: v.size,
            has_more: v.has_more,
        }
    }
}
