//! 写入边界使用的校验、意图标识、脱敏摘要、DTO 映射与错误投影。

use std::fmt::Write as _;
use std::time::{SystemTime, UNIX_EPOCH};

use rand::random;
use sha2::{Digest, Sha256};
use ubaa_core::facade as domain;

use super::{BridgeCgyySubmitReservationRequest, BridgeYgdkSubmitRequest};
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
    let Some(photo) = request.photo.as_ref() else {
        return Err(invalid_input("photo is required"));
    };
    if photo.bytes.is_empty() {
        return Err(invalid_input("photo is empty"));
    }
    if request.start_time.is_none() || request.end_time.is_none() {
        return Err(invalid_input("start and end time are both required"));
    }
    Ok(())
}

pub(super) fn validate_cgyy_request(
    request: &BridgeCgyySubmitReservationRequest,
) -> Result<(), BridgeError> {
    validate_id_i32(request.venue_site_id)?;
    validate_text(&request.reservation_date)?;
    if request.selections.is_empty() {
        return Err(invalid_input("至少选择一个预约时段"));
    }
    let first_space = request.selections[0].space_id;
    for selection in &request.selections {
        validate_id_i32(selection.space_id)?;
        validate_id_i32(selection.time_id)?;
        if selection.space_id != first_space {
            return Err(invalid_input("同次预约只能选择同一房间的时段"));
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
    Ok(())
}

pub(super) fn ygdk_canonical(request: &BridgeYgdkSubmitRequest) -> String {
    let photo_shape = request.photo.as_ref().map_or_else(
        || "none".to_owned(),
        |photo| format!("present:{}:{}", photo.bytes.len(), photo.mime_type),
    );
    format!(
        "item={:?};start={};end={};place={};share={:?};photo={}",
        request.item_id,
        text_shape(request.start_time.as_deref()),
        text_shape(request.end_time.as_deref()),
        text_shape(request.place.as_deref()),
        request.share_to_square,
        photo_shape,
    )
}

pub(super) fn cgyy_canonical(request: &BridgeCgyySubmitReservationRequest) -> String {
    let selections = request
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
