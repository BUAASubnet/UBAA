use serde::{Deserialize, Serialize};

use super::ActionEligibility;

#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibBookLibrary {
    pub id: String,
    pub name: String,
    pub free_num: i32,
    pub total_num: i32,
    pub storeys: Vec<LibBookStorey>,
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibBookStorey {
    pub id: String,
    pub name: String,
    pub free_num: i32,
    pub total_num: i32,
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibBookArea {
    pub id: String,
    pub name: String,
    pub area_name: String,
    pub premises_id: String,
    pub storey_id: String,
    pub free_num: i32,
    pub total_num: i32,
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibBookAreaDetail {
    pub id: String,
    pub name: String,
    pub available_dates: Vec<String>,
    pub time_slots: Vec<LibBookTimeSlot>,
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibBookTimeSlot {
    pub id: String,
    pub start: String,
    pub end: String,
    pub label: String,
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibBookSeat {
    pub id: String,
    pub name: String,
    pub no: String,
    pub status: Option<i32>,
    pub status_name: String,
    pub reserve_eligibility: ActionEligibility,
    pub reserve_target: Option<String>,
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibBookBooking {
    pub id: String,
    pub name_merge: String,
    pub area_name: String,
    pub seat_no: String,
    pub day: String,
    pub begin_time: String,
    pub end_time: String,
    pub status: Option<i32>,
    pub status_name: String,
    pub cancel_eligibility: ActionEligibility,
    pub cancel_target: Option<String>,
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibBookBookingsPage {
    pub bookings: Vec<LibBookBooking>,
    pub page: i32,
    pub limit: i32,
    pub total: i32,
}
/// 图书馆座位预约请求。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibBookReserveRequest {
    pub area_id: String,
    pub seat_id: String,
    pub day: String,
    pub segment: String,
    pub start_time: String,
    pub end_time: String,
}
/// 图书馆座位预约的当前权威摘要。
///
/// 该值只包含稳定目标与脱敏展示字段，不包含业务令牌、Cookie 或原始上游响应。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibBookReservePreflight {
    pub area_id: String,
    pub seat_id: String,
    pub seat_name: String,
    pub seat_no: String,
    pub day: String,
    pub segment: String,
    pub start_time: String,
    pub end_time: String,
}
/// 图书馆预约结果。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibBookReserveResult {
    pub success: bool,
    pub message: String,
    pub booking: Option<LibBookBooking>,
}
/// 图书馆预约取消请求。
///
/// `page` 与 `limit` 固定 action 产生时所在分页，使 prepare/commit 都只在同一页 fresh 复核。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibBookCancelRequest {
    pub booking_id: String,
    pub page: i32,
    pub limit: i32,
}
/// 图书馆预约取消的当前权威摘要。
///
/// 该值不包含 bearer、Cookie、原始响应或调用方不能核验的隐藏状态。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibBookCancelPreflight {
    pub booking_id: String,
    pub booking_name: String,
    pub area_name: String,
    pub seat_no: String,
    pub day: String,
    pub begin_time: String,
    pub end_time: String,
}
/// 图书馆取消结果。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibBookCancelResult {
    pub success: bool,
    pub message: String,
}
