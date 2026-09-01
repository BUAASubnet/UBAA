//! 一次性 typed 写入意图。

#![allow(
    clippy::missing_errors_doc,
    clippy::similar_names,
    clippy::too_many_lines
)]

use std::fmt::Write as _;
use std::time::{SystemTime, UNIX_EPOCH};

use super::client::{
    BridgeClient, BridgeConnectionMode, BridgeError, BridgeErrorCode, BridgeErrorKind,
};
use super::read::{BridgeCgyyOrder, BridgeEvaluationCourse};
use rand::random;
use sha2::{Digest, Sha256};
use ubaa_core::domain::{self, ReadonlyFeature};

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

impl BridgeClient {
    async fn prepare_write(
        &self,
        feature: ReadonlyFeature,
        operation: BridgeWriteOperation,
        canonical: String,
        target_summary: String,
        warnings: Vec<String>,
        pending: PendingWrite,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        let mut guard = self.inner.lock().await;
        let client = guard.as_mut().ok_or_else(super::client::disposed_error)?;
        let resolution = client
            .resolve_route_for_feature(feature)
            .map_err(|error| BridgeError::from_core(error, None))?;
        let intent_id = random_id();
        let digest = digest(&canonical);
        let expires_at = now_seconds().saturating_add(120);
        self.write_intents.lock().await.insert(
            intent_id.clone(),
            PendingEntry {
                request: pending,
                expires_at,
                resolved_route: resolution.mode.into(),
            },
        );
        Ok(BridgeWriteIntent {
            intent_id,
            operation,
            target_summary,
            resolved_route: resolution.mode.into(),
            warnings,
            expires_at,
            request_digest: digest,
        })
    }

    pub async fn prepare_bykc_select_course(
        &self,
        request: BridgeBykcCourseRequest,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        validate_id(request.course_id)?;
        self.prepare_write(
            ReadonlyFeature::Bykc,
            BridgeWriteOperation::BykcSelectCourse,
            format!("course_id={}", request.course_id),
            "选择一门博雅课程".to_owned(),
            vec!["提交后请刷新已选课程确认结果".to_owned()],
            PendingWrite::BykcSelect(request),
        )
        .await
    }
    pub async fn prepare_bykc_deselect_course(
        &self,
        request: BridgeBykcCourseRequest,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        validate_id(request.course_id)?;
        self.prepare_write(
            ReadonlyFeature::Bykc,
            BridgeWriteOperation::BykcDeselectCourse,
            format!("course_id={}", request.course_id),
            "退选一门博雅课程".to_owned(),
            vec!["请确认课程与退选截止时间".to_owned()],
            PendingWrite::BykcDeselect(request),
        )
        .await
    }
    pub async fn prepare_bykc_sign_course(
        &self,
        request: BridgeBykcSignCourseRequest,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        validate_id(request.course_id)?;
        self.prepare_write(
            ReadonlyFeature::Bykc,
            BridgeWriteOperation::BykcSignCourse,
            format!(
                "course_id={};lat={:?};lng={:?};sign_type={}",
                request.course_id, request.lat, request.lng, request.sign_type
            ),
            "提交博雅课程签到".to_owned(),
            vec!["位置只在本次请求中使用".to_owned()],
            PendingWrite::BykcSign(request),
        )
        .await
    }
    pub async fn prepare_signin_perform(
        &self,
        request: BridgeSigninPerformRequest,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        validate_text(&request.course_id)?;
        self.prepare_write(
            ReadonlyFeature::Signin,
            BridgeWriteOperation::SigninPerform,
            format!("course_id={}", request.course_id),
            "提交课堂签到".to_owned(),
            vec!["请确认课程和当前签到窗口".to_owned()],
            PendingWrite::Signin(request),
        )
        .await
    }
    pub async fn prepare_libbook_reserve(
        &self,
        request: BridgeLibbookReserveRequest,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        validate_text(&request.area_id)?;
        validate_text(&request.seat_id)?;
        validate_text(&request.day)?;
        let canonical = format!(
            "area={};seat={};day={};segment={};start={};end={}",
            request.area_id,
            request.seat_id,
            request.day,
            request.segment,
            request.start_time,
            request.end_time
        );
        self.prepare_write(
            ReadonlyFeature::LibBook,
            BridgeWriteOperation::LibbookReserve,
            canonical,
            "预约图书馆座位".to_owned(),
            vec!["提交后将通过预约记录核对状态".to_owned()],
            PendingWrite::LibbookReserve(request),
        )
        .await
    }
    pub async fn prepare_libbook_cancel_booking(
        &self,
        request: BridgeLibbookCancelBookingRequest,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        validate_text(&request.id)?;
        self.prepare_write(
            ReadonlyFeature::LibBook,
            BridgeWriteOperation::LibbookCancelBooking,
            format!("id={}", request.id),
            "取消一条图书馆预约".to_owned(),
            vec!["取消操作可能不可恢复".to_owned()],
            PendingWrite::LibbookCancel(request),
        )
        .await
    }
    pub async fn prepare_ygdk_submit(
        &self,
        request: BridgeYgdkSubmitRequest,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        let photo_digest = request.photo.as_ref().map(|p| digest_bytes(&p.bytes));
        let canonical = format!(
            "item={:?};start={:?};end={:?};place={:?};share={:?};photo={:?}",
            request.item_id,
            request.start_time,
            request.end_time,
            request.place,
            request.share_to_square,
            photo_digest
        );
        self.prepare_write(
            ReadonlyFeature::Ygdk,
            BridgeWriteOperation::YgdkSubmit,
            canonical,
            "提交一条阳光打卡记录".to_owned(),
            vec!["照片仅在本次操作内存中保留".to_owned()],
            PendingWrite::Ygdk(request),
        )
        .await
    }
    pub async fn prepare_cgyy_submit_reservation(
        &self,
        request: BridgeCgyySubmitReservationRequest,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        validate_text(&request.reservation_date)?;
        validate_text(&request.phone)?;
        validate_text(&request.theme)?;
        let canonical = format!(
            "site={};date={};selections={:?};phone={};theme={};purpose={};joiner_num={};content={};joiners={};philosophy={};off_school={}",
            request.venue_site_id,
            request.reservation_date,
            request
                .selections
                .iter()
                .map(|s| (s.space_id, s.time_id, s.venue_space_group_id))
                .collect::<Vec<_>>(),
            request.phone,
            request.theme,
            request.purpose_type,
            request.joiner_num,
            request.activity_content,
            request.joiners,
            request.is_philosophy_social_sciences,
            request.is_off_school_joiner
        );
        self.prepare_write(
            ReadonlyFeature::Cgyy,
            BridgeWriteOperation::CgyySubmitReservation,
            canonical,
            "提交场馆预约申请".to_owned(),
            vec![
                "如需验证码，材料只在本次操作内存中使用".to_owned(),
                "提交后必须查询订单核对结果".to_owned(),
            ],
            PendingWrite::CgyyReserve(request),
        )
        .await
    }
    pub async fn prepare_cgyy_cancel_order(
        &self,
        request: BridgeCgyyCancelOrderRequest,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        validate_id_i32(request.id)?;
        self.prepare_write(
            ReadonlyFeature::Cgyy,
            BridgeWriteOperation::CgyyCancelOrder,
            format!("id={}", request.id),
            "取消一笔场馆预约订单".to_owned(),
            vec!["取消操作可能不可恢复".to_owned()],
            PendingWrite::CgyyCancel(request),
        )
        .await
    }
    pub async fn prepare_evaluation_submit_courses(
        &self,
        request: BridgeEvaluationSubmitCoursesRequest,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        if request.courses.is_empty() {
            return Err(invalid_input("至少选择一门待评课程"));
        }
        let canonical = request
            .courses
            .iter()
            .map(|c| format!("{}:{}:{}", c.id, c.rwid, c.wjid))
            .collect::<Vec<_>>()
            .join("|");
        self.prepare_write(
            ReadonlyFeature::Evaluation,
            BridgeWriteOperation::EvaluationSubmitCourses,
            canonical,
            format!("提交 {} 门课程的教学评教", request.courses.len()),
            vec!["评教提交后不可撤销，请确认课程数量".to_owned()],
            PendingWrite::Evaluation(request),
        )
        .await
    }

    pub async fn commit_write(
        &self,
        intent_id: String,
    ) -> Result<BridgeWriteCommitResult, BridgeError> {
        if intent_id.trim().is_empty() {
            return Err(invalid_input("intent id is required"));
        }
        let entry = {
            let mut intents = self.write_intents.lock().await;
            intents.remove(&intent_id).ok_or_else(|| {
                BridgeError::local(
                    BridgeErrorCode::IntentExpired,
                    BridgeErrorKind::Input,
                    false,
                    "write intent is expired or already used",
                )
            })?
        };
        if now_seconds() > entry.expires_at {
            return Err(BridgeError::local(
                BridgeErrorCode::IntentExpired,
                BridgeErrorKind::Input,
                false,
                "write intent is expired",
            ));
        }
        let pending = entry.request;
        let operation = pending.operation();
        let mut guard = self.inner.lock().await;
        let client = guard.as_mut().ok_or_else(super::client::disposed_error)?;
        let current_resolution = client
            .resolve_route_for_feature(pending.feature())
            .map_err(|error| BridgeError::from_core(error, None))?;
        let current_route: BridgeConnectionMode = current_resolution.mode.into();
        if current_route != entry.resolved_route {
            return Err(BridgeError::local(
                BridgeErrorCode::OperationConflict,
                BridgeErrorKind::Input,
                true,
                "route changed; prepare the write again",
            ));
        }
        let result = match pending {
            PendingWrite::BykcSelect(request) => client
                .bykc_select_course(request.course_id)
                .await
                .map(|r| (r.resolution, safe_message("博雅选课已提交"), None)),
            PendingWrite::BykcDeselect(request) => client
                .bykc_deselect_course(request.course_id)
                .await
                .map(|r| (r.resolution, safe_message("博雅退选已提交"), None)),
            PendingWrite::BykcSign(request) => client
                .bykc_sign_course(domain::BykcSignRequest {
                    course_id: request.course_id,
                    lat: request.lat,
                    lng: request.lng,
                    sign_type: request.sign_type,
                })
                .await
                .map(|r| (r.resolution, safe_message("博雅签到已提交"), None)),
            PendingWrite::Signin(request) => client
                .signin_perform(&request.course_id)
                .await
                .map(|r| (r.resolution, safe_message("课堂签到已提交"), None)),
            PendingWrite::LibbookReserve(request) => client
                .libbook_reserve(domain::LibBookReserveRequest {
                    area_id: request.area_id,
                    seat_id: request.seat_id,
                    day: request.day,
                    segment: request.segment,
                    start_time: request.start_time,
                    end_time: request.end_time,
                })
                .await
                .map(|r| (r.resolution, safe_message("图书馆预约已提交"), None)),
            PendingWrite::LibbookCancel(request) => client
                .libbook_cancel_booking(&request.id)
                .await
                .map(|r| (r.resolution, safe_message("图书馆预约已取消"), None)),
            PendingWrite::Ygdk(request) => client
                .ygdk_submit(domain::YgdkClockinSubmitRequest {
                    item_id: request.item_id,
                    start_time: request.start_time,
                    end_time: request.end_time,
                    place: request.place,
                    share_to_square: request.share_to_square,
                    photo: request.photo.map(|p| domain::YgdkPhotoUpload {
                        bytes: p.bytes,
                        file_name: p.file_name,
                        mime_type: p.mime_type,
                    }),
                })
                .await
                .map(|r| (r.resolution, safe_message("阳光打卡已提交"), None)),
            PendingWrite::CgyyReserve(request) => client
                .cgyy_submit_reservation(map_cgyy_request(request))
                .await
                .map(|r| {
                    (
                        r.resolution,
                        safe_message("场馆预约已提交"),
                        r.data.order.map(super::read::map_cgyy_order),
                    )
                }),
            PendingWrite::CgyyCancel(request) => client
                .cgyy_cancel_order(request.id)
                .await
                .map(|r| (r.resolution, safe_message("场馆订单已取消"), None)),
            PendingWrite::Evaluation(request) => client
                .evaluation_submit_courses(
                    request
                        .courses
                        .into_iter()
                        .map(map_evaluation_course)
                        .collect(),
                )
                .await
                .map(|r| (r.resolution, safe_message("教学评教已提交"), None)),
        };
        match result {
            Ok((resolution, message, order)) => Ok(BridgeWriteCommitResult {
                operation,
                success: true,
                message,
                outcome_unknown: false,
                resolved_route: Some(resolution.mode.into()),
                order,
            }),
            Err(error) => {
                let unknown = matches!(
                    error.error.code,
                    ubaa_core::error::ErrorCode::NetworkError
                        | ubaa_core::error::ErrorCode::Timeout
                        | ubaa_core::error::ErrorCode::UpstreamUnavailable
                );
                if unknown {
                    Err(BridgeError::local(
                        BridgeErrorCode::OutcomeUnknown,
                        BridgeErrorKind::Network,
                        true,
                        "write outcome is unknown; refresh status before retrying",
                    ))
                } else {
                    Err(BridgeError::from_routed(error))
                }
            }
        }
    }
}

fn map_evaluation_course(c: BridgeEvaluationCourse) -> domain::EvaluationCourse {
    domain::EvaluationCourse {
        id: c.id,
        kcmc: c.kcmc,
        bpmc: c.bpmc,
        is_evaluated: c.is_evaluated,
        rwid: c.rwid,
        wjid: c.wjid,
        kcdm: c.kcdm,
        bpdm: c.bpdm,
        pjrdm: c.pjrdm,
        pjrmc: c.pjrmc,
        xnxq: c.xnxq,
        msid: c.msid,
        zdmc: c.zdmc,
        ypjcs: c.ypjcs,
        xypjcs: c.xypjcs,
        sxz: c.sxz,
        rwh: c.rwh,
        xn: c.xn,
        xq: c.xq,
        pjlxid: c.pjlxid,
        sfksqbpj: c.sfksqbpj,
        yxsfktjst: c.yxsfktjst,
    }
}

fn map_cgyy_request(c: BridgeCgyySubmitReservationRequest) -> domain::CgyyReservationSubmitRequest {
    let mut request = domain::CgyyReservationSubmitRequest::default();
    request.venue_site_id = c.venue_site_id;
    request.reservation_date = c.reservation_date;
    request.selections = c
        .selections
        .into_iter()
        .map(|selection| domain::CgyyReservationSelection {
            space_id: selection.space_id,
            time_id: selection.time_id,
            venue_space_group_id: selection.venue_space_group_id,
        })
        .collect();
    request.phone = c.phone;
    request.theme = c.theme;
    request.purpose_type = c.purpose_type;
    request.joiner_num = c.joiner_num;
    request.activity_content = c.activity_content;
    request.joiners = c.joiners;
    request.is_philosophy_social_sciences = c.is_philosophy_social_sciences;
    request.is_off_school_joiner = c.is_off_school_joiner;
    request
}

fn random_id() -> String {
    let mut value = String::with_capacity(32);
    for byte in random::<[u8; 16]>() {
        let _ = write!(value, "{byte:02x}");
    }
    value
}
fn digest(value: &str) -> String {
    digest_bytes(value.as_bytes())
}
fn digest_bytes(value: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(value);
    format!("{:x}", hasher.finalize())
}
fn now_seconds() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |duration| {
            i64::try_from(duration.as_secs()).unwrap_or(i64::MAX)
        })
}
fn validate_id(id: i64) -> Result<(), BridgeError> {
    if id <= 0 {
        Err(invalid_input("id must be positive"))
    } else {
        Ok(())
    }
}
fn validate_id_i32(id: i32) -> Result<(), BridgeError> {
    if id <= 0 {
        Err(invalid_input("id must be positive"))
    } else {
        Ok(())
    }
}
fn validate_text(value: &str) -> Result<(), BridgeError> {
    if value.trim().is_empty() {
        Err(invalid_input("required input is empty"))
    } else {
        Ok(())
    }
}
fn invalid_input(message: &str) -> BridgeError {
    BridgeError::local(
        BridgeErrorCode::InvalidInput,
        BridgeErrorKind::Input,
        false,
        message,
    )
}
fn safe_message(message: &str) -> String {
    message.to_owned()
}

#[cfg(test)]
mod tests {
    use super::{digest, random_id};
    use crate::api::client::{BridgeClient, BridgeErrorCode};

    #[test]
    fn intent_id_and_digest_are_stable_shapes_without_payload_leak() {
        let first = random_id();
        let second = random_id();
        assert_eq!(first.len(), 32);
        assert_eq!(second.len(), 32);
        assert_ne!(first, second);
        assert_eq!(digest("course_id=7").len(), 64);
        assert_eq!(digest("course_id=7"), digest("course_id=7"));
    }

    #[tokio::test]
    async fn unknown_or_reused_intent_is_rejected_before_network() {
        let path = std::env::temp_dir().join(format!("ubaa-bridge-write-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&path);
        let client = BridgeClient::open(path.to_string_lossy().into_owned()).expect("open client");
        let error = client
            .commit_write("missing-intent".to_owned())
            .await
            .expect_err("missing intent");
        assert_eq!(error.code, BridgeErrorCode::IntentExpired);
        let _ = std::fs::remove_dir_all(path);
    }
}
