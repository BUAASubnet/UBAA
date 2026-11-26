use super::{
    auth::{check_business_response, resolve_required_spoc_result, with_spoc_auth_retry},
    files::url,
    parser::parse_optional_envelope,
};
use crate::{
    error::{ErrorCode, ErrorKind, Result, UbaaError},
    features::msa,
    ports::HttpRequest,
    runtime::ClientRuntime,
};
use serde_json::Value;
use std::fmt::Write;

const IDENTITY: &str = "https://spoc.buaa.edu.cn/spocnewht/kc/queryYhSflx";
const SIGN: &str = "https://spoc.buaa.edu.cn/spocnewht/yun/getHxyTimestampAndSignature2";
const MAP: &str =
    "https://yjapi.msa.buaa.edu.cn/coursescheduleapi/v2/bh-university/get-bh-course-url";
const STAGE: &str = "spoc_mapping";
async fn read(
    runtime: &mut ClientRuntime,
    endpoint: &str,
    pairs: &[(&str, &str)],
    http_reason: &'static str,
    envelope_reason: &'static str,
) -> Result<Value> {
    let target = url(runtime, endpoint, pairs)?;
    let result = with_spoc_auth_retry(runtime, |runtime, cred| {
        let request = HttpRequest::get(&target)
            .with_header("Token", cred.token_header())
            .with_header("RoleCode", &cred.role)
            .with_header("X-Requested-With", "XMLHttpRequest");
        Box::pin(async move {
            let response = runtime.request(request).await?;
            check_business_response(&response)
                .map_err(|error| msa::diagnose_changed(error, STAGE, http_reason))?;
            let content = parse_optional_envelope(&crate::features::body(&response))
                .map_err(|error| msa::diagnose_changed(error, STAGE, envelope_reason))?;
            Ok(content.unwrap_or(Value::Null))
        })
    })
    .await;
    resolve_required_spoc_result(runtime, result).await
}
fn scalar(value: &Value, reason: &'static str) -> Result<String> {
    match value {
        Value::String(value) => Ok(value.clone()),
        Value::Number(_) | Value::Bool(_) => Ok(value.to_string()),
        _ => Err(msa::changed(STAGE, reason)),
    }
}
pub(crate) async fn map(runtime: &mut ClientRuntime, kcid: &str) -> Result<(String, String)> {
    let trimmed = kcid.trim();
    if trimmed.is_empty() || trimmed.chars().count() > 128 || kcid.chars().any(char::is_control) {
        return Err(UbaaError::invalid_input("课堂课程标识无效"));
    }
    let kcid = trimmed;
    crate::features::require_session(runtime)?;
    let identity = read(
        runtime,
        IDENTITY,
        &[("kcid", kcid)],
        "role_http_status",
        "role_envelope_shape",
    )
    .await?;
    if identity != "2" {
        let (message, reason) = match identity.as_str() {
            Some("1" | "3" | "6") => ("暂不支持教师身份", "role_teacher_unsupported"),
            Some(_) => ("暂不支持当前身份", "role_unsupported"),
            None => ("暂不支持当前身份", "role_shape"),
        };
        return Err(
            UbaaError::new(ErrorCode::Unsupported, ErrorKind::Upstream, false, message)
                .with_diagnostic(STAGE, reason),
        );
    }
    let sign = read(
        runtime,
        SIGN,
        &[("kcid", kcid), ("type", ""), ("isxs", "1")],
        "signature_http_status",
        "signature_envelope_shape",
    )
    .await?;
    if !sign.is_object() {
        return Err(msa::changed(STAGE, "signature_shape"));
    }
    if sign["bind_id"].is_null() || sign["bind_id"] == "" {
        return Err(UbaaError::business_unavailable("该课程未开通课堂直录播")
            .with_diagnostic(STAGE, "bind_id_missing"));
    }
    let target = mapping_url(runtime, &sign)?;
    let expected =
        url::Url::parse(&target).map_err(|_| msa::changed(STAGE, "mapping_request_url"))?;
    let response = msa::isolated_get(runtime, HttpRequest::get(target)).await?;
    if response.status != 302 {
        return Err(msa::changed(STAGE, "mapping_status"));
    }
    if response.final_url != expected.as_str() {
        return Err(msa::changed(STAGE, "mapping_final_target"));
    }
    let next = msa::redirect(&response, runtime.mode(), STAGE)?;
    if !msa::origin(&next, msa::CLASS) {
        return Err(msa::changed(STAGE, "mapping_location_host"));
    }
    if next.path() != "/coursedetail" || next.fragment().is_some() {
        return Err(msa::changed(STAGE, "mapping_location_path"));
    }
    let mut ids = next.query_pairs().filter(|(key, _)| key == "course_id");
    let (_, course) = ids
        .next()
        .filter(|(_, value)| msa::digits(value))
        .ok_or_else(|| msa::changed(STAGE, "mapping_course_id"))?;
    if ids.next().is_some() {
        return Err(msa::changed(STAGE, "mapping_course_id_duplicate"));
    }
    Ok((
        course.into_owned(),
        scalar(&sign["username"], "mapping_username_shape")?,
    ))
}

fn mapping_url(runtime: &ClientRuntime, sign: &Value) -> Result<String> {
    let base = sign["ktsl_url"]
        .as_str()
        .ok_or_else(|| msa::changed(STAGE, "ktsl_url_shape"))?;
    if base.strip_suffix('?') != Some(MAP) {
        return Err(msa::changed(STAGE, "ktsl_url_untrusted"));
    }
    let mut target = runtime.url(base)?;
    if !target.ends_with('?') {
        target.push('?');
    }
    for key in [
        "bind_id",
        "username",
        "realname",
        "tenant_code",
        "timestamp",
        "signature",
        "allow_live",
    ] {
        let value = scalar(&sign[key], "signature_field_shape")?;
        if value.is_empty() {
            return Err(msa::changed(STAGE, "signature_field_empty"));
        }
        if key != "bind_id" {
            target.push('&');
        }
        target.push_str(key);
        target.push('=');
        for byte in value.bytes() {
            if byte.is_ascii_alphanumeric()
                || b"._-".contains(&byte)
                || (key == "realname" && b"!~*'()".contains(&byte))
            {
                target.push(char::from(byte));
            } else if key == "realname" {
                write!(target, "%{byte:02X}").expect("写入字符串");
            } else {
                return Err(msa::changed(STAGE, "signature_field_unsafe"));
            }
        }
    }
    Ok(target)
}
