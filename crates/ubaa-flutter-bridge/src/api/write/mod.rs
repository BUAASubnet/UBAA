//! 一次性 typed 写入意图。

#![allow(
    clippy::missing_errors_doc,
    clippy::similar_names,
    clippy::too_many_lines
)]

mod commit;
mod lifecycle;
mod prepare;
mod support;

use super::client::BridgeConnectionMode;
use super::read::BridgeEvaluationCourse;
use ubaa_core::facade::ReadonlyFeature;

#[derive(Clone, Copy, Debug)]
pub enum BridgeWriteOperation {
    BykcSelectCourse,
    BykcDeselectCourse,
    BykcSignCourse,
    SigninPerform,
    LibbookReserve,
    LibbookCancelBooking,
    YgdkSubmit,
    CgyySubmitReservation,
    CgyyCancelOrder,
    EvaluationSubmitCourses,
}

#[derive(Clone, Debug)]
pub struct BridgeWriteIntent {
    pub intent_id: String,
    pub operation: BridgeWriteOperation,
    pub target_summary: String,
    pub resolved_route: BridgeConnectionMode,
    pub warnings: Vec<String>,
    pub expires_at: i64,
    pub request_digest: String,
}

#[derive(Clone, Debug)]
pub struct BridgeBykcCourseRequest {
    pub course_id: i64,
}
#[derive(Clone, Debug)]
pub struct BridgeBykcSignCourseRequest {
    pub course_id: i64,
    pub lat: Option<f64>,
    pub lng: Option<f64>,
    pub sign_type: i32,
}
#[derive(Clone, Debug)]
pub struct BridgeSigninPerformRequest {
    pub course_id: String,
}
#[derive(Clone, Debug)]
pub struct BridgeLibbookReserveRequest {
    pub area_id: String,
    pub seat_id: String,
    pub day: String,
    pub segment: String,
    pub start_time: String,
    pub end_time: String,
}
#[derive(Clone, Debug)]
pub struct BridgeLibbookCancelBookingRequest {
    pub id: String,
    pub page: i32,
    pub limit: i32,
}
#[derive(Clone, Debug)]
pub struct BridgePhotoUpload {
    pub bytes: Vec<u8>,
    pub file_name: String,
    pub mime_type: String,
}
#[derive(Clone, Debug)]
pub struct BridgeYgdkSubmitRequest {
    pub item_id: Option<i32>,
    pub start_time: Option<String>,
    pub end_time: Option<String>,
    pub place: Option<String>,
    pub share_to_square: Option<bool>,
    pub photo: Option<BridgePhotoUpload>,
}
#[derive(Clone, Debug)]
pub struct BridgeCgyyReservationSelection {
    pub space_id: i32,
    pub time_id: i32,
    pub venue_space_group_id: Option<i32>,
}
#[derive(Clone, Debug)]
pub struct BridgeCgyySubmitReservationRequest {
    pub venue_site_id: i32,
    pub reservation_date: String,
    pub selections: Vec<BridgeCgyyReservationSelection>,
    pub phone: String,
    pub theme: String,
    pub purpose_type: i32,
    pub joiner_num: i32,
    pub activity_content: String,
    pub joiners: String,
    pub is_philosophy_social_sciences: bool,
    pub is_off_school_joiner: bool,
}
#[derive(Clone, Debug)]
pub struct BridgeCgyyCancelOrderRequest {
    pub order_id: i32,
}
#[derive(Clone, Debug)]
pub struct BridgeCgyyReservationReceipt {
    pub order_id: i32,
    pub venue_site_id: Option<i32>,
    pub reservation_date: Option<String>,
    pub order_status: Option<i32>,
}
#[derive(Clone, Debug)]
pub struct BridgeEvaluationSubmitCoursesRequest {
    pub courses: Vec<BridgeEvaluationCourse>,
}

#[derive(Clone, Debug)]
pub struct BridgeWriteCommitResult {
    pub operation: BridgeWriteOperation,
    pub success: bool,
    pub message: String,
    pub outcome_unknown: bool,
    pub resolved_route: Option<BridgeConnectionMode>,
    pub cgyy_receipt: Option<BridgeCgyyReservationReceipt>,
}

pub(crate) enum PendingWrite {
    BykcSelect(BridgeBykcCourseRequest),
    BykcDeselect(BridgeBykcCourseRequest),
    BykcSign(BridgeBykcSignCourseRequest),
    Signin(BridgeSigninPerformRequest),
    LibbookReserve(BridgeLibbookReserveRequest),
    LibbookCancel(BridgeLibbookCancelBookingRequest),
    Ygdk(BridgeYgdkSubmitRequest),
    CgyyReserve(BridgeCgyySubmitReservationRequest),
    CgyyCancel(BridgeCgyyCancelOrderRequest),
    Evaluation(BridgeEvaluationSubmitCoursesRequest),
}

pub(crate) struct PendingEntry {
    pub request: PendingWrite,
    pub expires_at: i64,
    pub resolved_route: BridgeConnectionMode,
    pub conflict_key: String,
}

impl PendingWrite {
    fn operation(&self) -> BridgeWriteOperation {
        match self {
            Self::BykcSelect(_) => BridgeWriteOperation::BykcSelectCourse,
            Self::BykcDeselect(_) => BridgeWriteOperation::BykcDeselectCourse,
            Self::BykcSign(_) => BridgeWriteOperation::BykcSignCourse,
            Self::Signin(_) => BridgeWriteOperation::SigninPerform,
            Self::LibbookReserve(_) => BridgeWriteOperation::LibbookReserve,
            Self::LibbookCancel(_) => BridgeWriteOperation::LibbookCancelBooking,
            Self::Ygdk(_) => BridgeWriteOperation::YgdkSubmit,
            Self::CgyyReserve(_) => BridgeWriteOperation::CgyySubmitReservation,
            Self::CgyyCancel(_) => BridgeWriteOperation::CgyyCancelOrder,
            Self::Evaluation(_) => BridgeWriteOperation::EvaluationSubmitCourses,
        }
    }

    fn feature(&self) -> ReadonlyFeature {
        match self {
            Self::BykcSelect(_) | Self::BykcDeselect(_) | Self::BykcSign(_) => {
                ReadonlyFeature::Bykc
            }
            Self::Signin(_) => ReadonlyFeature::Signin,
            Self::LibbookReserve(_) | Self::LibbookCancel(_) => ReadonlyFeature::LibBook,
            Self::Ygdk(_) => ReadonlyFeature::Ygdk,
            Self::CgyyReserve(_) | Self::CgyyCancel(_) => ReadonlyFeature::Cgyy,
            Self::Evaluation(_) => ReadonlyFeature::Evaluation,
        }
    }

    fn conflict_key(&self) -> String {
        match self {
            Self::BykcSelect(request) => format!("bykc-select:{}", request.course_id),
            Self::BykcDeselect(request) => format!("bykc-deselect:{}", request.course_id),
            Self::BykcSign(request) => {
                format!("bykc-sign:{}:{}", request.course_id, request.sign_type)
            }
            Self::Signin(request) => format!("signin:{}", request.course_id.trim()),
            Self::LibbookReserve(request) => format!(
                "libbook-reserve:{}:{}:{}:{}:{}:{}",
                request.area_id,
                request.seat_id,
                request.day,
                request.segment,
                request.start_time,
                request.end_time,
            ),
            Self::LibbookCancel(request) => format!("libbook-cancel:{}", request.id.trim()),
            Self::Ygdk(request) => format!(
                "ygdk:{:?}:{}:{}",
                request.item_id,
                request.start_time.as_deref().unwrap_or_default(),
                request.end_time.as_deref().unwrap_or_default(),
            ),
            Self::CgyyReserve(request) => {
                let first = request
                    .selections
                    .first()
                    .expect("场馆预约意图只保存已验证的非空时段");
                format!(
                    "cgyy-reserve:{}:{}:{}:{:?}",
                    request.venue_site_id,
                    request.reservation_date,
                    first.space_id,
                    first.venue_space_group_id,
                )
            }
            Self::CgyyCancel(request) => format!("cgyy-cancel:{}", request.order_id),
            Self::Evaluation(request) => {
                let mut ids = request
                    .courses
                    .iter()
                    .map(|course| course.id.trim())
                    .collect::<Vec<_>>();
                ids.sort_unstable();
                ids.dedup();
                format!("evaluation:{}", ids.join("|"))
            }
        }
    }
}

#[cfg(test)]
mod tests;
