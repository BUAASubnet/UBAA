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
async fn read(
    runtime: &mut ClientRuntime,
    endpoint: &str,
    pairs: &[(&str, &str)],
) -> Result<Value> {
    let target = url(runtime, endpoint, pairs)?;
    let result = with_spoc_auth_retry(runtime, |runtime, cred| {
        let request = HttpRequest::get(&target)
            .with_header("Token", cred.token_header())
            .with_header("RoleCode", &cred.role)
            .with_header("X-Requested-With", "XMLHttpRequest");
        Box::pin(async move {
            let response = runtime.request(request).await?;
            check_business_response(&response)?;
            Ok(parse_optional_envelope(&crate::features::body(&response))?.unwrap_or(Value::Null))
        })
    })
    .await;
    resolve_required_spoc_result(runtime, result).await
}
fn scalar(value: &Value) -> Result<String> {
    match value {
        Value::String(value) => Ok(value.clone()),
        Value::Number(_) | Value::Bool(_) => Ok(value.to_string()),
        _ => Err(msa::changed()),
    }
}
pub(crate) async fn map(runtime: &mut ClientRuntime, kcid: &str) -> Result<(String, String)> {
    let trimmed = kcid.trim();
    if trimmed.is_empty() || trimmed.chars().count() > 128 || kcid.chars().any(char::is_control) {
        return Err(UbaaError::invalid_input("课堂课程标识无效"));
    }
    let kcid = trimmed;
    crate::features::require_session(runtime)?;
    let identity = read(runtime, IDENTITY, &[("kcid", kcid)]).await?;
    if identity != "2" {
        let message = match identity.as_str() {
            Some("1" | "3" | "6") => "暂不支持教师身份",
            _ => "暂不支持当前身份",
        };
        return Err(UbaaError::new(
            ErrorCode::Unsupported,
            ErrorKind::Upstream,
            false,
            message,
        ));
    }
    let sign = read(
        runtime,
        SIGN,
        &[("kcid", kcid), ("type", ""), ("isxs", "1")],
    )
    .await?;
    if !sign.is_object() {
        return Err(msa::changed());
    }
    if sign["bind_id"].is_null() || sign["bind_id"] == "" {
        return Err(UbaaError::business_unavailable("该课程未开通课堂直录播"));
    }
    let target = mapping_url(runtime, &sign)?;
    let expected = url::Url::parse(&target).map_err(|_| msa::changed())?;
    let response = msa::isolated_get(runtime, HttpRequest::get(target)).await?;
    if response.status != 302 || response.final_url != expected.as_str() {
        return Err(msa::changed());
    }
    let next = msa::redirect(&response, runtime.mode())?;
    if !msa::endpoint(&next, msa::CLASS, "/coursedetail") {
        return Err(msa::changed());
    }
    let mut ids = next.query_pairs().filter(|(key, _)| key == "course_id");
    let (_, course) = ids
        .next()
        .filter(|(_, value)| msa::digits(value))
        .ok_or_else(msa::changed)?;
    if ids.next().is_some() {
        return Err(msa::changed());
    }
    Ok((course.into_owned(), scalar(&sign["username"])?))
}

fn mapping_url(runtime: &ClientRuntime, sign: &Value) -> Result<String> {
    let base = sign["ktsl_url"].as_str().ok_or_else(msa::changed)?;
    if base.strip_suffix('?') != Some(MAP) {
        return Err(msa::changed());
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
        let value = scalar(&sign[key])?;
        if value.is_empty() {
            return Err(msa::changed());
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
                return Err(msa::changed());
            }
        }
    }
    Ok(target)
}
