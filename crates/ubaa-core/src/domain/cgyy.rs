use std::fmt;

use serde::{Deserialize, Serialize};

use super::ActionEligibility;

#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CgyyVenueSite {
    pub id: i32,
    pub site_name: String,
    pub venue_name: String,
    pub campus_name: String,
    pub seat_count: Option<i32>,
    pub reservation_space_count: Option<i32>,
    pub site_telephone: Option<String>,
    pub open_start_date: Option<String>,
    pub open_end_date: Option<String>,
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CgyyPurposeType {
    pub key: i32,
    pub name: String,
}

/// 场馆用途来源，用于把上游读取和冻结静态回退区分开。
#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum CgyyPurposeSource {
    /// 成功解析上游用途接口。
    Upstream,
    /// 上游请求或响应不可用时使用冻结定义。
    #[default]
    StaticFallback,
}

/// 场馆用途及其安全来源诊断。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CgyyPurposeTypes {
    pub items: Vec<CgyyPurposeType>,
    pub source: CgyyPurposeSource,
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CgyyTimeSlot {
    pub id: i32,
    pub begin_time: String,
    pub end_time: String,
    pub label: String,
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CgyySlotStatus {
    pub time_id: i32,
    /// 上游 canonical 预约状态；缺失、越界或类型畸形时保持为空。
    pub reservation_status: Option<i32>,
    /// 当前槽位的 typed 预约资格；`Unknown` 必须按拒绝处理。
    pub reservation_eligibility: ActionEligibility,
    /// 仅在资格明确允许且全部身份字段完整唯一时提供。
    pub reservation_target: Option<CgyyReservationTarget>,
    pub start_date: Option<String>,
    pub end_date: Option<String>,
    pub trade_no: Option<String>,
    pub order_id: Option<i32>,
    pub use_num: Option<i32>,
    pub already_num: Option<i32>,
    pub take_up: Option<bool>,
    pub take_up_explain: Option<String>,
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CgyySpaceAvailability {
    pub space_id: i32,
    pub space_name: String,
    pub venue_site_id: i32,
    pub venue_space_group_id: Option<i32>,
    pub slots: Vec<CgyySlotStatus>,
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CgyyDayInfo {
    pub venue_site_id: i32,
    pub reservation_date: String,
    pub available_dates: Vec<String>,
    pub time_slots: Vec<CgyyTimeSlot>,
    pub spaces: Vec<CgyySpaceAvailability>,
    pub reservation_total_num: Option<i32>,
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CgyyOrder {
    pub id: i32,
    pub trade_no: Option<String>,
    pub venue_site_id: Option<i32>,
    pub reservation_date: Option<String>,
    pub reservation_date_detail: Option<String>,
    pub venue_space_name: Option<String>,
    pub campus_name: Option<String>,
    pub venue_name: Option<String>,
    pub site_name: Option<String>,
    pub reservation_start_date: Option<String>,
    pub reservation_end_date: Option<String>,
    pub phone: Option<String>,
    pub order_status: Option<i32>,
    pub pay_status: Option<i32>,
    pub check_status: Option<i32>,
    pub theme: Option<String>,
    pub purpose_type: Option<i32>,
    pub purpose_type_name: Option<String>,
    pub joiner_num: Option<i32>,
    pub activity_content: Option<String>,
    pub joiners: Option<String>,
    pub check_content: Option<String>,
    pub handle_reason: Option<String>,
    pub remark: Option<String>,
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CgyyOrdersPage {
    pub content: Vec<CgyyOrder>,
    pub total_elements: i32,
    pub total_pages: i32,
    pub size: i32,
    pub number: i32,
}

/// 场馆预约写操作结果。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CgyyActionResult {
    pub message: String,
    pub order: Option<CgyyOrder>,
}

/// 场馆预约提交结果。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CgyyReservationResult {
    pub success: bool,
    pub message: String,
    pub receipt: Option<CgyyReservationReceipt>,
}

/// 场馆门锁码的安全摘要。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CgyyLockCode {
    /// 上游是否返回了可用的锁码数据；具体锁码永不离开 Core。
    pub available: bool,
}

/// 场馆预约提交时选择的空间及时段。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CgyyReservationSelection {
    pub space_id: i32,
    pub time_id: i32,
    pub venue_space_group_id: Option<i32>,
}

/// 场馆预约槽位的稳定写目标。
///
/// `time_ordinal` 是该时段在上游完整 `spaceTimeInfo` 列表中的零基位置，
/// 只用于本地 fresh authority 与相邻性判断，不进入最终上游表单。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CgyyReservationTarget {
    pub venue_site_id: i32,
    pub reservation_date: String,
    pub space_id: i32,
    pub time_id: i32,
    pub venue_space_group_id: Option<i32>,
    pub time_ordinal: i32,
}

/// 场馆预约 prepare 阶段的安全权威摘要。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CgyyReservationPreflight {
    pub venue_site_id: i32,
    pub reservation_date: String,
    pub targets: Vec<CgyyReservationTarget>,
}

/// 场馆预约成功后的安全收据。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CgyyReservationReceipt {
    pub order_id: i32,
    pub venue_site_id: Option<i32>,
    pub reservation_date: Option<String>,
    pub order_status: Option<i32>,
}

/// 场馆预约提交请求。
#[derive(Clone, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CgyyReservationSubmitRequest {
    pub venue_site_id: i32,
    pub reservation_date: String,
    pub selections: Vec<CgyyReservationSelection>,
    pub phone: String,
    pub theme: String,
    pub purpose_type: i32,
    pub joiner_num: i32,
    pub activity_content: String,
    pub joiners: String,
    pub is_philosophy_social_sciences: bool,
    pub is_off_school_joiner: bool,
    #[serde(default, skip_serializing)]
    pub(crate) captcha_verification: String,
    #[serde(default, skip_serializing)]
    pub(crate) captcha_point_json: String,
    #[serde(default, skip_serializing)]
    pub(crate) captcha_token: String,
    #[serde(default, skip_serializing)]
    pub(crate) captcha_secret_key: Option<String>,
    #[serde(default, skip_serializing)]
    pub(crate) captcha_original_image_base64: Option<String>,
    #[serde(default, skip_serializing)]
    pub(crate) captcha_jigsaw_image_base64: Option<String>,
}

impl CgyyReservationSubmitRequest {
    /// 注入调用方已经完成的验证码三元组；具体字段不会暴露给宿主读取。
    #[must_use]
    pub fn with_captcha_material(
        mut self,
        verification: impl Into<String>,
        point_json: impl Into<String>,
        token: impl Into<String>,
    ) -> Self {
        self.captcha_verification = verification.into();
        self.captcha_point_json = point_json.into();
        self.captcha_token = token.into();
        self
    }

    /// 返回是否提供了完整的外部验证码材料，不返回材料本身。
    #[must_use]
    pub fn has_captcha_material(&self) -> bool {
        !self.captcha_verification.is_empty()
            && !self.captcha_point_json.is_empty()
            && !self.captcha_token.is_empty()
    }
}

impl fmt::Debug for CgyyReservationSubmitRequest {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("CgyyReservationSubmitRequest")
            .field("venue_site_id", &self.venue_site_id)
            .field("reservation_date", &self.reservation_date)
            .field("selections", &self.selections)
            .field("phone", &"<redacted>")
            .field("theme", &"<redacted>")
            .field("purpose_type", &self.purpose_type)
            .field("joiner_num", &self.joiner_num)
            .field("activity_content", &"<redacted>")
            .field("joiners", &"<redacted>")
            .field(
                "is_philosophy_social_sciences",
                &self.is_philosophy_social_sciences,
            )
            .field("is_off_school_joiner", &self.is_off_school_joiner)
            .field("captcha_verification", &"<redacted>")
            .field("captcha_point_json", &"<redacted>")
            .field("captcha_token", &"<redacted>")
            .field("captcha_secret_key", &"<redacted>")
            .field("captcha_original_image_base64", &"<redacted>")
            .field("captcha_jigsaw_image_base64", &"<redacted>")
            .finish()
    }
}
