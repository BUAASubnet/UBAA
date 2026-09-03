//! 一次性 typed 写入意图。

#![allow(
    clippy::missing_errors_doc,
    clippy::similar_names,
    clippy::too_many_lines
)]

mod commit;
mod prepare;
mod support;

use super::client::BridgeConnectionMode;
use super::read::{BridgeCgyyOrder, BridgeEvaluationCourse};
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
    pub id: i32,
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
    pub order: Option<BridgeCgyyOrder>,
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
}

#[cfg(test)]
mod tests;
