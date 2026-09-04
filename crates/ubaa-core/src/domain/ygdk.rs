use std::fmt;

use serde::{Deserialize, Serialize};

use super::ActionEligibility;

/// 阳光打卡提交的稳定目标。
#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct YgdkSubmitTarget {
    pub classify_id: i32,
    pub item_id: i32,
}

/// 阳光打卡项目。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct YgdkItem {
    pub item_id: i32,
    pub name: String,
    pub kind: Option<i32>,
    pub sort: Option<i32>,
    pub submit_eligibility: ActionEligibility,
    pub submit_target: Option<YgdkSubmitTarget>,
}
/// 阳光打卡学期统计。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct YgdkTermSummary {
    pub term_id: Option<i32>,
    pub term_name: Option<String>,
    pub term_count: i32,
    pub term_target: Option<i32>,
    pub week_count: Option<i32>,
    pub week_target: Option<i32>,
    pub month_count: Option<i32>,
    pub month_target: Option<i32>,
    pub day_count: Option<i32>,
    pub good_count: Option<i32>,
}
/// 阳光打卡概览。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct YgdkOverview {
    pub summary: YgdkTermSummary,
    pub classify_id: i32,
    pub classify_name: String,
    pub default_item_id: i32,
    pub default_item_name: String,
    pub items: Vec<YgdkItem>,
}
/// 阳光打卡记录。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct YgdkRecord {
    pub record_id: i32,
    pub item_id: Option<i32>,
    pub item_name: Option<String>,
    pub start_time: Option<String>,
    pub end_time: Option<String>,
    pub place: Option<String>,
    pub images: Vec<String>,
    pub is_open: bool,
    pub state: Option<i32>,
    pub created_at: Option<String>,
    pub created_at_label: Option<String>,
}
/// 阳光打卡记录分页。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct YgdkRecordsPage {
    pub content: Vec<YgdkRecord>,
    pub total: i32,
    pub page: i32,
    pub size: i32,
    pub has_more: bool,
}
/// 阳光打卡图片上传。图片字节只在一次请求内存中存在，不写入会话或输出。
#[derive(Clone, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct YgdkPhotoUpload {
    #[serde(skip_serializing)]
    pub bytes: Vec<u8>,
    #[serde(skip_serializing)]
    pub file_name: String,
    #[serde(skip_serializing)]
    pub mime_type: String,
}
impl YgdkPhotoUpload {
    pub(crate) fn normalized_mime_type(&self) -> Option<&str> {
        let mime_type = self.mime_type.as_str();
        let subtype = mime_type.strip_prefix("image/")?;
        (mime_type == mime_type.trim()
            && !subtype.is_empty()
            && subtype.is_ascii()
            && subtype.bytes().all(is_http_token_character))
        .then_some(mime_type)
    }
}

fn is_http_token_character(value: u8) -> bool {
    value.is_ascii_alphanumeric()
        || matches!(
            value,
            b'!' | b'#'
                | b'$'
                | b'%'
                | b'&'
                | b'\''
                | b'*'
                | b'+'
                | b'-'
                | b'.'
                | b'^'
                | b'_'
                | b'`'
                | b'|'
                | b'~'
        )
}
impl fmt::Debug for YgdkPhotoUpload {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("YgdkPhotoUpload")
            .field("bytes", &format_args!("[{} bytes]", self.bytes.len()))
            .field("file_name", &"[REDACTED]")
            .field(
                "mime_type",
                &self.normalized_mime_type().unwrap_or("[INVALID]"),
            )
            .finish()
    }
}
/// 阳光打卡提交请求。
#[derive(Clone, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct YgdkClockinSubmitRequest {
    pub target: YgdkSubmitTarget,
    pub start_time: String,
    pub end_time: String,
    pub place: Option<String>,
    pub share_to_square: bool,
    pub photo: YgdkPhotoUpload,
}
impl fmt::Debug for YgdkClockinSubmitRequest {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("YgdkClockinSubmitRequest")
            .field("target", &self.target)
            .field("start_time", &"[已隐藏]")
            .field("end_time", &"[已隐藏]")
            .field("place", &self.place.as_ref().map(|_| "[已隐藏]"))
            .field("share_to_square", &self.share_to_square)
            .field("photo", &self.photo)
            .finish()
    }
}
/// 阳光打卡提交前由 Core fresh 复核形成的规范化结果。
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct YgdkSubmitPreflight {
    pub request: YgdkClockinSubmitRequest,
    pub item_name: String,
}
/// 阳光打卡提交结果。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct YgdkClockinSubmitResult {
    pub success: bool,
    pub message: String,
    pub record_id: Option<i32>,
}
