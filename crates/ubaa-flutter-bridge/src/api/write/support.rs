//! 写入边界使用的校验、意图标识、脱敏摘要、DTO 映射与错误投影。

use std::fmt::Write as _;
use std::time::{SystemTime, UNIX_EPOCH};

use rand::random;
use sha2::{Digest, Sha256};
use ubaa_core::facade as domain;

use super::{
    BridgeBykcSignCourseRequest, BridgeCgyyReservationReceipt, BridgeCgyySubmitReservationRequest,
    BridgeWriteOperation, BridgeYgdkSubmitReceipt, BridgeYgdkSubmitRequest,
};
use crate::api::client::{BridgeConnectionMode, BridgeError, BridgeErrorCode, BridgeErrorKind};
use crate::api::read::BridgeEvaluationCourse;

pub(super) fn map_resolution_error(error: ubaa_core::facade::UbaaError) -> BridgeError {
    // Core 将跨进程会话修订冲突归约为 internal_error；在写 intent 的路线复核边界
    // 将这个已冻结的稳定消息投影为可行动的 operation_conflict，禁止继续提交旧请求。
    if error.message == "local session changed in another process" {
        return BridgeError::local(
            BridgeErrorCode::OperationConflict,
            BridgeErrorKind::Input,
            true,
            "session changed; prepare the write again",
        );
    }
    BridgeError::from_core(error, None)
}

pub(super) fn map_bykc_sign_preflight_error(error: domain::RoutedError) -> BridgeError {
    if error.error.message == "local session changed in another process" {
        return routed_local_error(
            &error,
            BridgeErrorCode::OperationConflict,
            BridgeErrorKind::Input,
            true,
            "session changed; prepare the write again",
        );
    }
    if error.error.code == domain::ErrorCode::InvalidInput && error.error.retryable {
        return routed_local_error(
            &error,
            BridgeErrorCode::OperationConflict,
            BridgeErrorKind::Input,
            true,
            "课程签到资格已变化，请刷新后重新准备",
        );
    }
    BridgeError::from_routed(error)
}

pub(super) fn map_libbook_preflight_error(error: domain::RoutedError) -> BridgeError {
    if error.error.message == "local session changed in another process" {
        return routed_local_error(
            &error,
            BridgeErrorCode::OperationConflict,
            BridgeErrorKind::Input,
            true,
            "session changed; prepare the write again",
        );
    }
    if error.error.code == domain::ErrorCode::InvalidInput && error.error.retryable {
        return routed_local_error(
            &error,
            BridgeErrorCode::OperationConflict,
            BridgeErrorKind::Input,
            true,
            "图书馆预约资格已变化，请刷新后重新准备",
        );
    }
    BridgeError::from_routed(error)
}

pub(super) fn map_libbook_cancel_preflight_error(error: domain::RoutedError) -> BridgeError {
    if error.error.message == "local session changed in another process" {
        return routed_local_error(
            &error,
            BridgeErrorCode::OperationConflict,
            BridgeErrorKind::Input,
            true,
            "session changed; prepare the write again",
        );
    }
    if error.error.code == domain::ErrorCode::InvalidInput && error.error.retryable {
        return routed_local_error(
            &error,
            BridgeErrorCode::OperationConflict,
            BridgeErrorKind::Input,
            true,
            "图书馆预约取消资格已变化，请刷新后重新准备",
        );
    }
    if error.error.code == domain::ErrorCode::UpstreamChanged {
        return routed_local_error(
            &error,
            BridgeErrorCode::UpstreamChanged,
            BridgeErrorKind::Upstream,
            false,
            "图书馆预约取消资格核对响应无效",
        );
    }
    BridgeError::from_routed(error)
}

pub(super) fn map_cgyy_preflight_error(error: domain::RoutedError) -> BridgeError {
    if error.error.message == "local session changed in another process" {
        return routed_local_error(
            &error,
            BridgeErrorCode::OperationConflict,
            BridgeErrorKind::Input,
            true,
            "session changed; prepare the write again",
        );
    }
    if error.error.code == domain::ErrorCode::InvalidInput && error.error.retryable {
        return routed_local_error(
            &error,
            BridgeErrorCode::OperationConflict,
            BridgeErrorKind::Input,
            true,
            "场馆预约资格已变化，请刷新后重新准备",
        );
    }
    if error.error.code == domain::ErrorCode::UpstreamChanged {
        return routed_local_error(
            &error,
            BridgeErrorCode::UpstreamChanged,
            BridgeErrorKind::Upstream,
            false,
            "场馆预约资格核对响应无效",
        );
    }
    BridgeError::from_routed(error)
}

pub(super) fn map_cgyy_cancel_preflight_error(error: domain::RoutedError) -> BridgeError {
    if error.error.message == "local session changed in another process" {
        return routed_local_error(
            &error,
            BridgeErrorCode::OperationConflict,
            BridgeErrorKind::Input,
            true,
            "session changed; prepare the write again",
        );
    }
    if error.error.code == domain::ErrorCode::InvalidInput && error.error.retryable {
        return routed_local_error(
            &error,
            BridgeErrorCode::OperationConflict,
            BridgeErrorKind::Input,
            true,
            "场馆订单取消资格已变化，请刷新后重新准备",
        );
    }
    if error.error.code == domain::ErrorCode::UpstreamChanged {
        return routed_local_error(
            &error,
            BridgeErrorCode::UpstreamChanged,
            BridgeErrorKind::Upstream,
            false,
            "场馆订单取消资格核对响应无效",
        );
    }
    BridgeError::from_routed(error)
}

pub(super) fn map_ygdk_preflight_error(error: domain::RoutedError) -> BridgeError {
    if error.error.message == "local session changed in another process" {
        return routed_local_error(
            &error,
            BridgeErrorCode::OperationConflict,
            BridgeErrorKind::Input,
            true,
            "session changed; prepare the write again",
        );
    }
    if error.error.code == domain::ErrorCode::UpstreamChanged {
        return routed_local_error(
            &error,
            BridgeErrorCode::UpstreamChanged,
            BridgeErrorKind::Upstream,
            false,
            "阳光打卡资格核对响应无效",
        );
    }
    BridgeError::from_routed(error)
}

pub(super) fn map_commit_error(
    operation: BridgeWriteOperation,
    error: domain::RoutedError,
) -> BridgeError {
    if error.error.message == "local session changed in another process" {
        return routed_local_error(
            &error,
            BridgeErrorCode::OperationConflict,
            BridgeErrorKind::Input,
            true,
            "session changed; prepare the write again",
        );
    }
    if matches!(
        operation,
        BridgeWriteOperation::BykcSignCourse
            | BridgeWriteOperation::SigninPerform
            | BridgeWriteOperation::LibbookReserve
            | BridgeWriteOperation::LibbookCancelBooking
            | BridgeWriteOperation::YgdkSubmit
            | BridgeWriteOperation::CgyySubmitReservation
            | BridgeWriteOperation::CgyyCancelOrder
    ) && error.error.code == domain::ErrorCode::InvalidInput
        && error.error.retryable
    {
        let message = match operation {
            BridgeWriteOperation::SigninPerform => "课堂签到资格已变化，请刷新后重新准备",
            BridgeWriteOperation::LibbookReserve => "图书馆预约资格已变化，请刷新后重新准备",
            BridgeWriteOperation::LibbookCancelBooking => {
                "图书馆预约取消资格已变化，请刷新后重新准备"
            }
            BridgeWriteOperation::YgdkSubmit => "阳光打卡资格已变化，请刷新后重新准备",
            BridgeWriteOperation::CgyySubmitReservation => "场馆预约资格已变化，请刷新后重新准备",
            BridgeWriteOperation::CgyyCancelOrder => "场馆订单取消资格已变化，请刷新后重新准备",
            _ => "课程签到资格已变化，请刷新后重新准备",
        };
        return routed_local_error(
            &error,
            BridgeErrorCode::OperationConflict,
            BridgeErrorKind::Input,
            true,
            message,
        );
    }
    if matches!(operation, BridgeWriteOperation::LibbookCancelBooking)
        && error.error.code == domain::ErrorCode::UpstreamChanged
    {
        return routed_local_error(
            &error,
            BridgeErrorCode::UpstreamChanged,
            BridgeErrorKind::Upstream,
            false,
            "图书馆预约取消资格核对响应无效",
        );
    }
    if matches!(operation, BridgeWriteOperation::CgyyCancelOrder)
        && error.error.code == domain::ErrorCode::UpstreamChanged
    {
        return routed_local_error(
            &error,
            BridgeErrorCode::UpstreamChanged,
            BridgeErrorKind::Upstream,
            false,
            "场馆订单取消资格核对响应无效",
        );
    }
    if matches!(operation, BridgeWriteOperation::YgdkSubmit)
        && error.error.code == domain::ErrorCode::UpstreamChanged
    {
        return routed_local_error(
            &error,
            BridgeErrorCode::UpstreamChanged,
            BridgeErrorKind::Upstream,
            false,
            "阳光打卡提交前资格核对响应无效",
        );
    }
    if error.error.code == domain::ErrorCode::OutcomeUnknown {
        let kind = error.error.kind.into();
        let message = match operation {
            BridgeWriteOperation::CgyyCancelOrder => {
                "场馆订单取消结果未知，请刷新订单列表与详情核对后再操作"
            }
            BridgeWriteOperation::YgdkSubmit => "阳光打卡结果未知，请刷新概览与记录后再操作",
            _ => &error.error.message,
        };
        return routed_local_error(
            &error,
            BridgeErrorCode::OutcomeUnknown,
            kind,
            false,
            message,
        );
    }
    let outcome_unknown = if matches!(
        operation,
        BridgeWriteOperation::BykcSignCourse
            | BridgeWriteOperation::SigninPerform
            | BridgeWriteOperation::LibbookReserve
            | BridgeWriteOperation::LibbookCancelBooking
            | BridgeWriteOperation::YgdkSubmit
            | BridgeWriteOperation::CgyySubmitReservation
            | BridgeWriteOperation::CgyyCancelOrder
    ) {
        false
    } else {
        matches!(
            error.error.code,
            domain::ErrorCode::NetworkError
                | domain::ErrorCode::Timeout
                | domain::ErrorCode::UpstreamUnavailable
        )
    };
    if outcome_unknown {
        return routed_local_error(
            &error,
            BridgeErrorCode::OutcomeUnknown,
            BridgeErrorKind::Network,
            false,
            "write outcome is unknown; refresh status before retrying",
        );
    }
    BridgeError::from_routed(error)
}

fn routed_local_error(
    error: &domain::RoutedError,
    code: BridgeErrorCode,
    kind: BridgeErrorKind,
    retryable: bool,
    message: &str,
) -> BridgeError {
    BridgeError {
        code,
        kind,
        retryable,
        message: message.to_owned(),
        resolved_route: error.resolution().map(|value| value.mode.into()),
    }
}

pub(super) fn ensure_bykc_select_allowed(
    eligibility: domain::ActionEligibility,
) -> Result<(), BridgeError> {
    match eligibility {
        domain::ActionEligibility::Allowed => Ok(()),
        domain::ActionEligibility::Denied => Err(BridgeError::local(
            BridgeErrorCode::OperationConflict,
            BridgeErrorKind::Input,
            true,
            "课程当前不可选，请刷新课程详情后重试",
        )),
        domain::ActionEligibility::Unknown => Err(BridgeError::local(
            BridgeErrorCode::UpstreamChanged,
            BridgeErrorKind::Upstream,
            false,
            "课程选课资格缺少必要字段",
        )),
    }
}

pub(super) fn ensure_bykc_deselect_allowed(
    eligibility: domain::ActionEligibility,
) -> Result<(), BridgeError> {
    match eligibility {
        domain::ActionEligibility::Allowed => Ok(()),
        domain::ActionEligibility::Denied => Err(BridgeError::local(
            BridgeErrorCode::OperationConflict,
            BridgeErrorKind::Input,
            true,
            "课程当前不可退选，请刷新课程详情后重试",
        )),
        domain::ActionEligibility::Unknown => Err(BridgeError::local(
            BridgeErrorCode::UpstreamChanged,
            BridgeErrorKind::Upstream,
            false,
            "课程退选资格缺少必要字段",
        )),
    }
}

pub(super) fn ensure_bykc_course_target(
    requested_id: i64,
    actual_id: i64,
) -> Result<(), BridgeError> {
    if requested_id == actual_id {
        return Ok(());
    }
    Err(BridgeError::local(
        BridgeErrorCode::UpstreamChanged,
        BridgeErrorKind::Upstream,
        false,
        "课程详情标识与请求不一致",
    ))
}

pub(super) fn ensure_bykc_preflight_route(
    expected: BridgeConnectionMode,
    actual: BridgeConnectionMode,
) -> Result<(), BridgeError> {
    if expected == actual {
        return Ok(());
    }
    Err(BridgeError::local(
        BridgeErrorCode::OperationConflict,
        BridgeErrorKind::Input,
        true,
        "route changed during preflight; prepare the write again",
    ))
}

pub(super) fn validate_bykc_sign_request(
    request: &BridgeBykcSignCourseRequest,
) -> Result<(), BridgeError> {
    validate_id(request.course_id)?;
    if !matches!(request.sign_type, 1 | 2) {
        return Err(invalid_input("sign type must be 1 or 2"));
    }
    match (request.lat, request.lng) {
        (None, None) => Ok(()),
        (Some(lat), Some(lng))
            if lat.is_finite()
                && lng.is_finite()
                && (-90.0..=90.0).contains(&lat)
                && (-180.0..=180.0).contains(&lng) =>
        {
            Ok(())
        }
        _ => Err(invalid_input(
            "latitude and longitude must be supplied together and be valid",
        )),
    }
}

pub(super) fn bykc_sign_canonical(request: &BridgeBykcSignCourseRequest) -> String {
    format!(
        "course_id={};coordinates={};sign_type={}",
        request.course_id,
        if request.lat.is_some() && request.lng.is_some() {
            "present"
        } else {
            "absent"
        },
        request.sign_type,
    )
}

pub(super) fn map_evaluation_course(c: BridgeEvaluationCourse) -> domain::EvaluationCourse {
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

pub(super) fn map_cgyy_request(
    c: BridgeCgyySubmitReservationRequest,
) -> domain::CgyyReservationSubmitRequest {
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

pub(super) fn map_cgyy_receipt(
    receipt: domain::CgyyReservationReceipt,
) -> BridgeCgyyReservationReceipt {
    BridgeCgyyReservationReceipt {
        order_id: receipt.order_id,
        venue_site_id: receipt.venue_site_id,
        reservation_date: receipt.reservation_date,
        order_status: receipt.order_status,
    }
}

pub(super) fn map_ygdk_receipt(record_id: Option<i32>) -> Option<BridgeYgdkSubmitReceipt> {
    record_id
        .filter(|value| *value > 0)
        .map(|record_id| BridgeYgdkSubmitReceipt { record_id })
}

pub(super) fn random_id() -> String {
    let mut value = String::with_capacity(32);
    for byte in random::<[u8; 16]>() {
        let _ = write!(value, "{byte:02x}");
    }
    value
}
pub(super) fn digest(value: &str) -> String {
    digest_bytes(value.as_bytes())
}
fn digest_bytes(value: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(value);
    format!("{:x}", hasher.finalize())
}
pub(super) fn now_seconds() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |duration| {
            i64::try_from(duration.as_secs()).unwrap_or(i64::MAX)
        })
}
pub(super) fn validate_id(id: i64) -> Result<(), BridgeError> {
    if id <= 0 {
        Err(invalid_input("id must be positive"))
    } else {
        Ok(())
    }
}
pub(super) fn validate_id_i32(id: i32) -> Result<(), BridgeError> {
    if id <= 0 {
        Err(invalid_input("id must be positive"))
    } else {
        Ok(())
    }
}
pub(super) fn validate_text(value: &str) -> Result<(), BridgeError> {
    if value.trim().is_empty() {
        Err(invalid_input("required input is empty"))
    } else {
        Ok(())
    }
}
pub(super) fn validate_ygdk_request(request: &BridgeYgdkSubmitRequest) -> Result<(), BridgeError> {
    validate_id_i32(request.target.classify_id)?;
    validate_id_i32(request.target.item_id)?;
    let photo = &request.photo;
    if photo.bytes.is_empty() {
        return Err(invalid_input("photo is empty"));
    }
    if photo.bytes.len() > 10 * 1024 * 1024 {
        return Err(invalid_input("photo exceeds the 10 MiB limit"));
    }
    validate_photo_file_name(&photo.file_name)?;
    validate_photo_mime_type(&photo.mime_type)?;
    validate_text(&request.start_time)?;
    validate_text(&request.end_time)?;
    Ok(())
}

fn validate_photo_file_name(value: &str) -> Result<(), BridgeError> {
    if value != value.trim()
        || value.is_empty()
        || value.chars().count() > 128
        || matches!(value, "." | "..")
        || value
            .chars()
            .any(|ch| ch.is_control() || matches!(ch, '/' | '\\' | '"'))
    {
        return Err(invalid_input("photo file name is invalid"));
    }
    Ok(())
}

fn validate_photo_mime_type(value: &str) -> Result<(), BridgeError> {
    if !is_valid_photo_mime_type(value) {
        return Err(invalid_input("photo MIME type must be image/*"));
    }
    Ok(())
}

pub(super) fn is_valid_photo_mime_type(value: &str) -> bool {
    value
        .strip_prefix("image/")
        .is_some_and(|subtype| !subtype.is_empty() && subtype.bytes().all(is_http_token_byte))
}

fn is_http_token_byte(value: u8) -> bool {
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

pub(super) fn map_ygdk_request(
    request: BridgeYgdkSubmitRequest,
) -> domain::YgdkClockinSubmitRequest {
    domain::YgdkClockinSubmitRequest {
        target: domain::YgdkSubmitTarget {
            classify_id: request.target.classify_id,
            item_id: request.target.item_id,
        },
        start_time: request.start_time,
        end_time: request.end_time,
        place: request.place,
        share_to_square: request.share_to_square,
        photo: domain::YgdkPhotoUpload {
            bytes: request.photo.bytes,
            file_name: request.photo.file_name,
            mime_type: request.photo.mime_type,
        },
    }
}

pub(super) fn validate_cgyy_request(
    request: &BridgeCgyySubmitReservationRequest,
) -> Result<(), BridgeError> {
    validate_id_i32(request.venue_site_id)?;
    validate_text(&request.reservation_date)?;
    if request.selections.is_empty() {
        return Err(invalid_input("至少选择一个预约时段"));
    }
    if request.selections.len() > 2 {
        return Err(invalid_input("同次预约最多选择两个时段"));
    }
    let first_space = request.selections[0].space_id;
    let first_group = request.selections[0].venue_space_group_id;
    let mut time_ids = std::collections::BTreeSet::new();
    for selection in &request.selections {
        validate_id_i32(selection.space_id)?;
        validate_id_i32(selection.time_id)?;
        if selection.space_id != first_space {
            return Err(invalid_input("同次预约只能选择同一房间的时段"));
        }
        if selection.venue_space_group_id != first_group {
            return Err(invalid_input("同次预约的空间分组必须一致"));
        }
        if selection
            .venue_space_group_id
            .is_some_and(|group_id| group_id <= 0)
        {
            return Err(invalid_input("空间分组标识必须为正数"));
        }
        if !time_ids.insert(selection.time_id) {
            return Err(invalid_input("同次预约不能重复选择时段"));
        }
    }
    validate_text(&request.phone)?;
    validate_text(&request.theme)?;
    if request.purpose_type <= 0 {
        return Err(invalid_input("用途编号必须是正整数"));
    }
    if request.joiner_num <= 0 {
        return Err(invalid_input("参与人数必须是正整数"));
    }
    validate_text(&request.activity_content)?;
    validate_text(&request.joiners)?;
    Ok(())
}

pub(super) fn ygdk_canonical(request: &BridgeYgdkSubmitRequest) -> String {
    let photo_shape = format!(
        "present:{}:{}",
        request.photo.bytes.len(),
        request.photo.mime_type
    );
    format!(
        "classify={};item={};start={};end={};place={};share={};photo={}",
        request.target.classify_id,
        request.target.item_id,
        presence_shape(Some(&request.start_time)),
        presence_shape(Some(&request.end_time)),
        presence_shape(request.place.as_deref()),
        request.share_to_square,
        photo_shape,
    )
}

fn presence_shape(value: Option<&str>) -> &'static str {
    if value.is_some() { "present" } else { "none" }
}

pub(super) fn cgyy_canonical(request: &BridgeCgyySubmitReservationRequest) -> String {
    let mut selections = request
        .selections
        .iter()
        .map(|selection| {
            (
                selection.space_id,
                selection.time_id,
                selection.venue_space_group_id,
            )
        })
        .collect::<Vec<_>>();
    selections.sort_unstable();
    format!(
        "site={};date={};selections={selections:?};phone={};theme={};purpose={};joiner_num={};content={};joiners={};philosophy={};off_school={}",
        request.venue_site_id,
        request.reservation_date,
        text_shape(Some(&request.phone)),
        text_shape(Some(&request.theme)),
        request.purpose_type,
        request.joiner_num,
        text_shape(Some(&request.activity_content)),
        text_shape(Some(&request.joiners)),
        request.is_philosophy_social_sciences,
        request.is_off_school_joiner,
    )
}

fn text_shape(value: Option<&str>) -> String {
    value.map_or_else(
        || "none".to_owned(),
        |text| format!("present:{}", text.len()),
    )
}
pub(super) fn invalid_input(message: &str) -> BridgeError {
    BridgeError::local(
        BridgeErrorCode::InvalidInput,
        BridgeErrorKind::Input,
        false,
        message,
    )
}
pub(super) fn safe_message(message: &str) -> String {
    message.to_owned()
}

pub(super) fn safe_summary_label(value: &str, fallback: &str) -> String {
    let sanitized = value
        .trim()
        .chars()
        .filter(|value| !unsafe_summary_character(*value))
        .take(80)
        .collect::<String>();
    if sanitized.is_empty() {
        fallback.to_owned()
    } else {
        sanitized
    }
}

fn unsafe_summary_character(value: char) -> bool {
    value.is_control()
        || matches!(
            value,
            '\u{00ad}'
                | '\u{061c}'
                | '\u{200b}'..='\u{200f}'
                | '\u{2028}'..='\u{202e}'
                | '\u{2060}'..='\u{206f}'
                | '\u{feff}'
        )
}
