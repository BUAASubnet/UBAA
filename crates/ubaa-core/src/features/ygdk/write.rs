//! 阳光打卡照片上传后的显式打卡提交。

use chrono::{NaiveDateTime, TimeZone};
use chrono_tz::Asia::Shanghai;
use serde_json::Value;

use crate::domain::{
    ActionEligibility, YgdkClockinSubmitRequest, YgdkClockinSubmitResult, YgdkPhotoUpload,
    YgdkSubmitPreflight, YgdkSubmitTarget,
};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::runtime::ClientRuntime;

use super::YgdkCredential;
use super::http::{ensure_active_credential, post_non_idempotent};
use super::read::{get_overview_context, get_overview_context_once};
use super::upload::{upload_photo, validate_photo};

const DATE_TIME_FORMAT: &str = "%Y-%m-%d %H:%M";

#[derive(Clone)]
pub(super) struct NormalizedSubmitRequest {
    pub(super) target: YgdkSubmitTarget,
    pub(super) start_time: String,
    pub(super) end_time: String,
    pub(super) start_epoch_seconds: i64,
    pub(super) end_epoch_seconds: i64,
    pub(super) form_time_fmt: String,
    place: String,
    share_to_square: bool,
    photo: YgdkPhotoUpload,
}

impl NormalizedSubmitRequest {
    fn into_request(self) -> YgdkClockinSubmitRequest {
        YgdkClockinSubmitRequest {
            target: self.target,
            start_time: self.start_time,
            end_time: self.end_time,
            place: Some(self.place),
            share_to_square: self.share_to_square,
            photo: self.photo,
        }
    }
}

struct SubmitPreflightContext {
    preflight: YgdkSubmitPreflight,
    generation: u64,
    credential: YgdkCredential,
}

pub(super) fn normalize_submit_request(
    request: &YgdkClockinSubmitRequest,
) -> Result<NormalizedSubmitRequest> {
    if request.target.classify_id <= 0 || request.target.item_id <= 0 {
        return Err(invalid_input("阳光打卡分类和项目标识必须为正数"));
    }
    let start = parse_shanghai_datetime(&request.start_time, "开始时间格式无效")?;
    let end = parse_shanghai_datetime(&request.end_time, "结束时间格式无效")?;
    if start.date() != end.date() {
        return Err(invalid_input("开始和结束时间必须在同一自然日"));
    }
    if end <= start {
        return Err(invalid_input("结束时间必须晚于开始时间"));
    }
    validate_photo(&request.photo)?;
    let start_epoch_seconds = Shanghai
        .from_local_datetime(&start)
        .single()
        .ok_or_else(|| invalid_input("开始时间无法按 Asia/Shanghai 解释"))?
        .timestamp();
    let end_epoch_seconds = Shanghai
        .from_local_datetime(&end)
        .single()
        .ok_or_else(|| invalid_input("结束时间无法按 Asia/Shanghai 解释"))?
        .timestamp();
    let start_time = start.format(DATE_TIME_FORMAT).to_string();
    let end_time = end.format(DATE_TIME_FORMAT).to_string();
    Ok(NormalizedSubmitRequest {
        target: request.target,
        form_time_fmt: format!("{}-{}", start_time, end.format("%H:%M")),
        start_time,
        end_time,
        start_epoch_seconds,
        end_epoch_seconds,
        place: request
            .place
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .unwrap_or("操场")
            .to_owned(),
        share_to_square: request.share_to_square,
        photo: request.photo.clone(),
    })
}

fn parse_shanghai_datetime(value: &str, message: &str) -> Result<NaiveDateTime> {
    if value != value.trim() {
        return Err(invalid_input(message));
    }
    let parsed = NaiveDateTime::parse_from_str(value, DATE_TIME_FORMAT)
        .map_err(|_| invalid_input(message))?;
    if parsed.format(DATE_TIME_FORMAT).to_string() != value {
        return Err(invalid_input(message));
    }
    Ok(parsed)
}

pub(crate) fn validate_submit_request(request: &YgdkClockinSubmitRequest) -> Result<()> {
    normalize_submit_request(request).map(|_| ())
}

/// fresh 读取分类和项目，并返回只含当前权威名称的规范化提交请求。
pub(crate) async fn preflight_submit(
    runtime: &mut ClientRuntime,
    request: &YgdkClockinSubmitRequest,
) -> Result<YgdkSubmitPreflight> {
    preflight_submit_with_context(runtime, request, true)
        .await
        .map(|context| context.preflight)
}

async fn preflight_submit_with_context(
    runtime: &mut ClientRuntime,
    request: &YgdkClockinSubmitRequest,
    allow_authentication_refresh: bool,
) -> Result<SubmitPreflightContext> {
    let normalized = normalize_submit_request(request)?;
    let overview_context = if allow_authentication_refresh {
        get_overview_context(runtime).await
    } else {
        get_overview_context_once(runtime).await
    }
    .map_err(sanitize_authority_error)?;
    let matching = overview_context
        .overview
        .items
        .iter()
        .filter(|item| {
            item.item_id == normalized.target.item_id
                && item.submit_eligibility == ActionEligibility::Allowed
                && item.submit_target == Some(normalized.target)
        })
        .collect::<Vec<_>>();
    if overview_context.overview.classify_id != normalized.target.classify_id || matching.len() != 1
    {
        return Err(authority_error());
    }
    let item_name = matching[0].name.clone();
    Ok(SubmitPreflightContext {
        preflight: YgdkSubmitPreflight {
            request: normalized.into_request(),
            item_name,
        },
        generation: overview_context.generation,
        credential: overview_context.credential,
    })
}

/// 上传照片并提交打卡。该操作只由显式确认的宿主调用，实时验证器不会调用。
pub(crate) async fn submit_clockin(
    runtime: &mut ClientRuntime,
    request: YgdkClockinSubmitRequest,
) -> Result<YgdkClockinSubmitResult> {
    let context = preflight_submit_with_context(runtime, &request, false).await?;
    let normalized = normalize_submit_request(&context.preflight.request)?;
    ensure_active_credential(runtime, context.generation, &context.credential)?;
    let file_name = upload_photo(
        runtime,
        &context.credential,
        context.generation,
        &normalized.photo,
    )
    .await?;
    ensure_active_credential(runtime, context.generation, &context.credential)?;
    let params = [
        ("start_time", normalized.start_epoch_seconds.to_string()),
        ("end_time", normalized.end_epoch_seconds.to_string()),
        ("place_type", "1".into()),
        ("place", normalized.place),
        (
            "isopen",
            if normalized.share_to_square { "1" } else { "0" }.into(),
        ),
        ("form_time_fmt", normalized.form_time_fmt),
        ("images", serde_json::json!([file_name]).to_string()),
        ("classify_id", normalized.target.classify_id.to_string()),
        ("item_id", normalized.target.item_id.to_string()),
        ("item_name", context.preflight.item_name),
    ];
    let body = post_non_idempotent(
        runtime,
        "/api/Front/Clockin/Clockin/clockin",
        &context.credential,
        context.generation,
        &params,
    )
    .await?;
    parse_submit_result(&body)
}

pub(super) fn parse_submit_result(body: &str) -> Result<YgdkClockinSubmitResult> {
    let root: Value = serde_json::from_str(body).map_err(|_| super::write_outcome_unknown())?;
    let object = root.as_object().ok_or_else(super::write_outcome_unknown)?;
    if object.get("code").and_then(Value::as_i64) != Some(1) {
        return Err(super::write_outcome_unknown());
    }
    let result = object
        .get("result")
        .and_then(Value::as_object)
        .ok_or_else(super::write_outcome_unknown)?;
    let record_id = result
        .get("record_id")
        .and_then(Value::as_i64)
        .and_then(|value| i32::try_from(value).ok())
        .filter(|value| *value > 0);
    Ok(YgdkClockinSubmitResult {
        success: true,
        message: "阳光打卡已提交".into(),
        record_id,
    })
}

fn invalid_input(message: &str) -> UbaaError {
    UbaaError::new(ErrorCode::InvalidInput, ErrorKind::Input, false, message)
}

fn authority_error() -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        "阳光打卡提交资格核对响应无效",
    )
}

fn sanitize_authority_error(error: UbaaError) -> UbaaError {
    let safe_message = match error.code {
        ErrorCode::UpstreamChanged => return authority_error(),
        ErrorCode::NetworkError => "阳光打卡资格核对网络请求失败",
        ErrorCode::Timeout => "阳光打卡资格核对请求超时",
        ErrorCode::UpstreamUnavailable => "阳光打卡资格核对服务暂时不可用",
        ErrorCode::ParseError => "阳光打卡资格核对响应无法解析",
        ErrorCode::OutcomeUnknown => "阳光打卡资格核对结果未知",
        ErrorCode::AuthenticationRequired | ErrorCode::InternalError | ErrorCode::InvalidInput => {
            return error;
        }
        ErrorCode::InvalidCredentials
        | ErrorCode::PasswordRiskConfirmationFailed
        | ErrorCode::PermissionDenied => return error,
    };
    UbaaError::new(error.code, error.kind, error.retryable, safe_message)
}

#[cfg(test)]
mod tests {
    use super::sanitize_authority_error;
    use crate::error::{ErrorCode, ErrorKind, UbaaError};

    #[test]
    fn 资格读取的确定发送前错误保留分类与可重试性但移除原始详情() {
        for (code, kind, retryable) in [
            (ErrorCode::NetworkError, ErrorKind::Network, true),
            (ErrorCode::Timeout, ErrorKind::Network, true),
            (ErrorCode::UpstreamUnavailable, ErrorKind::Upstream, true),
        ] {
            let sanitized = sanitize_authority_error(UbaaError::new(
                code,
                kind,
                retryable,
                "secret raw upstream detail\nprivate",
            ));

            assert_eq!(
                (sanitized.code, sanitized.kind, sanitized.retryable),
                (code, kind, retryable)
            );
            assert!(!sanitized.message.is_empty());
            assert!(!sanitized.message.contains("secret"));
            assert!(!sanitized.message.contains("private"));
            assert!(!sanitized.message.contains('\n'));
        }
    }

    #[test]
    fn 资格响应协议漂移归一为固定脱敏错误() {
        let sanitized = sanitize_authority_error(UbaaError::new(
            ErrorCode::UpstreamChanged,
            ErrorKind::Upstream,
            false,
            "secret raw upstream detail",
        ));

        assert_eq!(sanitized.code, ErrorCode::UpstreamChanged);
        assert_eq!(sanitized.kind, ErrorKind::Upstream);
        assert!(!sanitized.retryable);
        assert_eq!(sanitized.message, "阳光打卡提交资格核对响应无效");
    }
}
