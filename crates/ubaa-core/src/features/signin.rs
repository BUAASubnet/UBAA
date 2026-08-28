//! 课堂签到只读查询的冻结响应解析。
#![allow(clippy::missing_errors_doc)]

use serde::Deserialize;
use serde_json::Value;

use crate::domain::{SigninActionResult, SigninClass};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::HttpRequest;

const SIGNIN_ENTRY_URL: &str = "https://iclass.buaa.edu.cn:8346/?type=jumpMyCenter";
const SIGNIN_LOGIN_URL: &str = "https://iclass.buaa.edu.cn:8346/eschool/app/user/login_buaa.do";
const SIGNIN_TODAY_URL: &str =
    "https://iclass.buaa.edu.cn:8347/app/course/get_stu_course_sched.action";
const REDIRECT_LIMIT: usize = 8;

/// iClass 查询所需的路线内业务凭据。
#[allow(dead_code)]
#[derive(Clone)]
pub(crate) struct SigninCredential {
    pub(crate) user_id: String,
    pub(crate) session_id: String,
}

#[derive(Deserialize)]
struct LoginResponse {
    #[serde(rename = "STATUS")]
    status: Value,
    result: Option<LoginResult>,
}

#[derive(Deserialize)]
struct LoginResult {
    id: String,
}

#[derive(Deserialize)]
struct Response {
    #[serde(rename = "STATUS")]
    status: Value,
    #[serde(default)]
    result: Vec<Row>,
}

#[derive(Deserialize)]
struct Row {
    id: String,
    #[serde(rename = "courseName")]
    course_name: String,
    #[serde(rename = "classBeginTime")]
    class_begin_time: String,
    #[serde(rename = "classEndTime")]
    class_end_time: String,
    #[serde(rename = "stuSignStatus")]
    sign_status: Value,
}

/// 解析旧版 iClass 今日课程响应，不向调用方暴露上游包装字段。
pub fn parse_today(body: &str) -> Result<Vec<SigninClass>> {
    let response: Response = serde_json::from_str(body).map_err(|_| parse_error())?;
    if empty_result(&response.status) {
        return Ok(Vec::new());
    }
    if !success(&response.status) {
        return Err(UbaaError::new(
            ErrorCode::UpstreamChanged,
            ErrorKind::Upstream,
            false,
            "签到响应返回了非成功状态",
        ));
    }
    response.result.into_iter().map(map_row).collect()
}

/// 使用当前路线查询今日课堂签到状态。
pub(crate) async fn get_today(
    runtime: &mut crate::runtime::ClientRuntime,
) -> Result<Vec<SigninClass>> {
    get_today_once(runtime, true).await
}

/// Submit a classroom sign-in request. This is intentionally low-level; hosts
/// must require an explicit write confirmation before calling it.
#[allow(dead_code)]
pub(crate) async fn perform_signin(
    runtime: &mut crate::runtime::ClientRuntime,
    course_id: &str,
) -> Result<SigninActionResult> {
    if course_id.trim().is_empty() {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "课程编号不能为空",
        ));
    }
    let credential = current_credential(runtime).await?;
    let timestamp_url =
        runtime.url("https://iclass.buaa.edu.cn:8347/app/common/get_timestamp.action")?;
    let timestamp = runtime.request(HttpRequest::get(timestamp_url)).await?;
    if timestamp.status != 200 {
        return Err(upstream_error("无法获取签到时间戳"));
    }
    let timestamp = parse_timestamp(&timestamp.body)?;
    let url = build_signin_url(runtime, course_id, &timestamp)?;
    let response = super::post_form(
        runtime,
        url,
        &build_signin_form(course_id),
        &[("sessionId", &credential.session_id)],
    )
    .await?;
    if response.status != 200 {
        return Err(upstream_error("签到请求失败"));
    }
    let object: Value =
        serde_json::from_slice(&response.body).map_err(|_| upstream_error("签到响应格式无效"))?;
    let status = object
        .get("STATUS")
        .and_then(integer_value)
        .unwrap_or_default();
    let signed = object
        .get("stuSignStatus")
        .and_then(integer_value)
        .unwrap_or_default()
        == 1;
    Ok(SigninActionResult {
        code: i32::try_from(status).unwrap_or_default(),
        success: signed,
        message: object
            .get("message")
            .and_then(Value::as_str)
            .unwrap_or(if signed {
                "签到成功"
            } else {
                "签到未完成"
            })
            .to_owned(),
    })
}

fn build_signin_url(
    runtime: &crate::runtime::ClientRuntime,
    course_id: &str,
    timestamp: &str,
) -> Result<String> {
    let mut url = url::Url::parse(
        &runtime.url("https://iclass.buaa.edu.cn:8347/eschool/app/course/stu_scan_sign.action")?,
    )
    .map_err(|_| invalid_url())?;
    url.query_pairs_mut()
        .append_pair("courseSchedId", course_id)
        .append_pair("timestamp", timestamp);
    Ok(url.to_string())
}

#[must_use]
fn build_signin_form(course_id: &str) -> Vec<(&'static str, String)> {
    vec![("id", course_id.into())]
}

fn parse_timestamp(body: &[u8]) -> Result<String> {
    let value: Value =
        serde_json::from_slice(body).map_err(|_| upstream_error("签到时间戳响应格式无效"))?;
    value
        .get("timestamp")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
        .ok_or_else(|| upstream_error("签到时间戳为空"))
}

async fn get_today_once(
    runtime: &mut crate::runtime::ClientRuntime,
    allow_retry: bool,
) -> Result<Vec<SigninClass>> {
    super::require_session(runtime)?;
    let credential = current_credential(runtime).await?;
    let mut url = url::Url::parse(&runtime.url(SIGNIN_TODAY_URL)?).map_err(|_| invalid_url())?;
    url.query_pairs_mut()
        .append_pair("id", &credential.user_id)
        .append_pair("dateStr", &shanghai_date());
    let mut request = HttpRequest::post(url.to_string(), Vec::new());
    request
        .headers
        .insert("Sessionid".into(), credential.session_id.clone());
    let response = runtime.request(request).await?;
    if response.status != 200 {
        return Err(upstream_error("签到查询服务暂时不可用"));
    }
    match parse_today(&super::body(&response)) {
        Ok(classes) => Ok(classes),
        Err(error) if allow_retry && error.code == ErrorCode::UpstreamChanged => {
            runtime.feature_state().signin.clear_credential();
            Box::pin(get_today_once(runtime, false)).await
        }
        Err(error) => Err(error),
    }
}

async fn current_credential(
    runtime: &mut crate::runtime::ClientRuntime,
) -> Result<SigninCredential> {
    let state = runtime.feature_state();
    if let Some(credential) = state.signin.credential() {
        return Ok(credential);
    }
    let _guard = state.signin.login_guard().await;
    if let Some(credential) = state.signin.credential() {
        return Ok(credential);
    }
    let generation = state.signin.generation();
    let credential = login(runtime).await?;
    if !state
        .signin
        .store_credential(generation, credential.clone())
    {
        return Err(UbaaError::new(
            ErrorCode::InternalError,
            ErrorKind::Internal,
            true,
            "签到业务会话在登录期间已失效",
        ));
    }
    Ok(credential)
}

async fn login(runtime: &mut crate::runtime::ClientRuntime) -> Result<SigninCredential> {
    let login_name = resolve_login_name(runtime).await?;
    let mut url = url::Url::parse(&runtime.url(SIGNIN_LOGIN_URL)?).map_err(|_| invalid_url())?;
    url.query_pairs_mut()
        .append_pair("password", "")
        .append_pair("phone", &login_name)
        .append_pair("userLevel", "1")
        .append_pair("verificationType", "2")
        .append_pair("verificationUrl", "");
    let response = runtime.request(HttpRequest::get(url.to_string())).await?;
    if response.status != 200 {
        return Err(upstream_error("无法建立签到业务会话"));
    }
    parse_login_credential(&response.body, &login_name)
}

fn parse_login_credential(body: &[u8], login_name: &str) -> Result<SigninCredential> {
    let response: LoginResponse =
        serde_json::from_slice(body).map_err(|_| upstream_error("签到登录响应格式无效"))?;
    let result = response
        .result
        .filter(|_| success(&response.status))
        .ok_or_else(|| upstream_error("签到业务登录失败"))?;
    if result.id.trim().is_empty() || login_name.trim().is_empty() {
        return Err(upstream_error("签到登录响应缺少会话字段"));
    }
    Ok(SigninCredential {
        user_id: result.id,
        session_id: login_name.to_owned(),
    })
}

async fn resolve_login_name(runtime: &mut crate::runtime::ClientRuntime) -> Result<String> {
    let mut direct_url = SIGNIN_ENTRY_URL.to_string();
    for _ in 0..REDIRECT_LIMIT {
        if let Some(login_name) = login_name_from_url(&direct_url) {
            return Ok(login_name);
        }
        let request_url = runtime.url(&direct_url)?;
        let response = runtime.request(HttpRequest::get(request_url)).await?;
        let final_direct = crate::connection::from_webvpn_url(&response.final_url)
            .unwrap_or_else(|_| response.final_url.clone());
        if let Some(login_name) = login_name_from_url(&final_direct) {
            return Ok(login_name);
        }
        let location = header(&response, "location")
            .ok_or_else(|| upstream_error("签到登录跳转缺少目标地址"))?;
        let location_direct =
            crate::connection::from_webvpn_url(location).unwrap_or_else(|_| location.to_string());
        let target = url::Url::parse(&final_direct)
            .and_then(|base| base.join(&location_direct))
            .map_err(|_| invalid_url())?;
        ensure_login_host(&target)?;
        direct_url = target.to_string();
    }
    Err(upstream_error("签到登录跳转次数超过限制"))
}

fn login_name_from_url(value: &str) -> Option<String> {
    let url = url::Url::parse(value).ok()?;
    url.query_pairs()
        .find(|(key, _)| key.eq_ignore_ascii_case("loginName"))
        .map(|(_, value)| value.into_owned())
        .filter(|value| !value.trim().is_empty())
}

fn ensure_login_host(url: &url::Url) -> Result<()> {
    if matches!(
        url.host_str().map(str::to_ascii_lowercase).as_deref(),
        Some("iclass.buaa.edu.cn" | "sso.buaa.edu.cn")
    ) {
        Ok(())
    } else {
        Err(upstream_error("签到登录跳转到未允许的主机"))
    }
}

fn header<'a>(response: &'a crate::ports::HttpResponse, name: &str) -> Option<&'a str> {
    response
        .headers
        .iter()
        .find(|(header, _)| header.eq_ignore_ascii_case(name))
        .and_then(|(_, values)| values.first())
        .map(String::as_str)
}

fn shanghai_date() -> String {
    let seconds = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |value| value.as_secs())
        + 8 * 60 * 60;
    let days = i64::try_from(seconds / 86_400).unwrap_or(i64::MAX);
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let year = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = mp + if mp < 10 { 3 } else { -9 };
    let year = year + i64::from(month <= 2);
    format!("{year:04}{month:02}{day:02}")
}

fn invalid_url() -> UbaaError {
    upstream_error("签到服务地址无效")
}

fn upstream_error(message: &'static str) -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        message,
    )
}

fn success(value: &Value) -> bool {
    matches!(value, Value::Number(number) if number.as_i64() == Some(0) || number.as_i64() == Some(200))
        || matches!(value, Value::String(text) if matches!(text.as_str(), "0" | "200" | "success"))
}

fn integer_value(value: &Value) -> Option<i64> {
    value
        .as_i64()
        .or_else(|| value.as_str().and_then(|text| text.parse().ok()))
}

fn empty_result(value: &Value) -> bool {
    matches!(value, Value::Number(number) if number.as_i64() == Some(2))
        || matches!(value, Value::String(text) if text == "2")
}

fn map_row(row: Row) -> Result<SigninClass> {
    let sign_status = match row.sign_status {
        Value::Number(number) => number.as_i64(),
        Value::String(text) => text.parse::<i64>().ok(),
        _ => None,
    }
    .and_then(|value| i32::try_from(value).ok())
    .ok_or_else(parse_error)?;
    Ok(SigninClass {
        course_id: row.id,
        course_name: row.course_name,
        class_begin_time: row.class_begin_time,
        class_end_time: row.class_end_time,
        sign_status,
    })
}

fn parse_error() -> UbaaError {
    UbaaError::new(
        ErrorCode::ParseError,
        ErrorKind::Parse,
        false,
        "签到响应格式无效",
    )
}

#[cfg(test)]
mod tests {
    use super::{
        SIGNIN_LOGIN_URL, build_signin_form, integer_value, parse_login_credential, parse_timestamp,
    };

    #[test]
    fn 时间戳读取冻结的_json字段() {
        assert_eq!(
            parse_timestamp(br#"{"timestamp":"1700000000000"}"#).unwrap(),
            "1700000000000"
        );
        assert!(parse_timestamp(br"1700000000000").is_err());
    }

    #[test]
    fn 签到业务登录使用已验证的新入口() {
        assert_eq!(
            SIGNIN_LOGIN_URL,
            "https://iclass.buaa.edu.cn:8346/eschool/app/user/login_buaa.do"
        );
    }

    #[test]
    fn 签到提交表单只发送冻结的用户标识字段() {
        let form = build_signin_form("course-safe");
        assert_eq!(form.len(), 1);
        assert_eq!(form[0], ("id", "course-safe".to_owned()));
    }

    #[test]
    fn 新版登录响应仅需用户标识并使用登录名作为会话() {
        let credential = parse_login_credential(
            r#"{"STATUS":"0","result":{"id":"用户标识已脱敏"}}"#.as_bytes(),
            "登录名已脱敏",
        )
        .expect("新版登录响应应可解析");
        assert_eq!(credential.user_id, "用户标识已脱敏");
        assert_eq!(credential.session_id, "登录名已脱敏");
    }

    #[test]
    fn 状态二表示今日没有课程() {
        let classes = super::parse_today(r#"{"STATUS":"2"}"#).expect("空课程状态应成功");
        assert!(classes.is_empty());
    }

    #[test]
    fn 签到写响应的数字字符串状态保持兼容() {
        assert_eq!(integer_value(&serde_json::json!("200")), Some(200));
        assert_eq!(integer_value(&serde_json::json!("1")), Some(1));
    }
}
