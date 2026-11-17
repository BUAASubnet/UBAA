//! 首页持久载荷只保留可再次阅读的字段，不包含学校操作资格。
use crate::domain::{SigninClass, YgdkItem, YgdkOverview, YgdkTermSummary};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CachedSigninClass {
    pub course_id: String,
    pub course_name: String,
    pub class_begin_time: String,
    pub class_end_time: String,
    pub sign_status: Option<i32>,
}
impl From<SigninClass> for CachedSigninClass {
    fn from(value: SigninClass) -> Self {
        Self {
            course_id: value.course_id,
            course_name: value.course_name,
            class_begin_time: value.class_begin_time,
            class_end_time: value.class_end_time,
            sign_status: value.sign_status,
        }
    }
}
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CachedYgdkItem {
    pub item_id: i32,
    pub name: String,
    pub kind: Option<i32>,
    pub sort: Option<i32>,
}
impl From<YgdkItem> for CachedYgdkItem {
    fn from(value: YgdkItem) -> Self {
        Self {
            item_id: value.item_id,
            name: value.name,
            kind: value.kind,
            sort: value.sort,
        }
    }
}
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CachedYgdkOverview {
    pub summary: YgdkTermSummary,
    pub classify_id: i32,
    pub classify_name: String,
    pub default_item_id: i32,
    pub default_item_name: String,
    pub items: Vec<CachedYgdkItem>,
}
impl From<YgdkOverview> for CachedYgdkOverview {
    fn from(value: YgdkOverview) -> Self {
        Self {
            summary: value.summary,
            classify_id: value.classify_id,
            classify_name: value.classify_name,
            default_item_id: value.default_item_id,
            default_item_name: value.default_item_name,
            items: value.items.into_iter().map(Into::into).collect(),
        }
    }
}

impl CachedYgdkOverview {
    pub(crate) fn trim_to_source_date(
        &mut self,
        fetched_at: i64,
        now: i64,
    ) -> super::CacheResult<()> {
        use chrono::Datelike;
        let offset = chrono::FixedOffset::east_opt(8 * 3600).expect("固定校园时区");
        let day = |timestamp| {
            chrono::DateTime::from_timestamp(timestamp, 0)
                .map(|value| value.with_timezone(&offset).date_naive())
                .ok_or(super::CacheError::InvalidInput)
        };
        let source = day(fetched_at)?;
        let today = day(now)?;
        if source != today {
            self.summary.day_count = None;
        }
        if (source.year(), source.month()) != (today.year(), today.month()) {
            self.summary.month_count = None;
        }
        Ok(())
    }
}
