//! 课堂签到只读查询的冻结响应解析。
#![allow(clippy::missing_errors_doc)]

use serde::Deserialize;
use serde_json::Value;

use crate::domain::{ActionEligibility, SigninActionResult, SigninClass};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::HttpRequest;

const SIGNIN_ENTRY_URL: &str = "https://iclass.buaa.edu.cn:8346/?type=jumpMyCenter";
const SIGNIN_LOGIN_URL: &str = "https://iclass.buaa.edu.cn:8347/app/user/login.action";
const SIGNIN_TODAY_URL: &str =
    "https://iclass.buaa.edu.cn:8347/app/course/get_stu_course_sched.action";
const REDIRECT_LIMIT: usize = 8;

pub(crate) use crate::internal::route_state::SigninCredential;

#[derive(Deserialize)]
struct LoginResponse {
    #[serde(rename = "STATUS")]
    status: Value,
    result: Option<LoginResult>,
}

#[derive(Deserialize)]
struct LoginResult {
    id: String,
    #[serde(default, rename = "sessionId")]
    session_id: Option<String>,
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
    #[serde(default, rename = "signStatus")]
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
    Ok(response.result.into_iter().map(map_row).collect())
}

/// 使用当前路线查询今日课堂签到状态。
pub(crate) async fn get_today(
    runtime: &mut crate::runtime::ClientRuntime,
) -> Result<Vec<SigninClass>> {
    get_today_once(runtime, true, None).await
}

pub(crate) async fn get_today_for_date(
    runtime: &mut crate::runtime::ClientRuntime,
    date: &str,
) -> Result<Vec<SigninClass>> {
    get_today_once(runtime, true, Some(date)).await
}

/// 只读复核唯一课程安排及其当前签到资格。
pub(crate) async fn preflight_signin(
    runtime: &mut crate::runtime::ClientRuntime,
    course_id: &str,
) -> Result<SigninClass> {
    validate_course_id(course_id)?;
    let matches = get_today(runtime)
        .await?
        .into_iter()
        .filter(|class| class.signin_target.as_deref() == Some(course_id))
        .collect::<Vec<_>>();
    let [class] = matches.as_slice() else {
        return if matches.is_empty() {
            Err(unavailable("今日签到目标已变化，请刷新后重新准备"))
        } else {
            Err(upstream_error("今日签到响应包含重复课程安排标识"))
        };
    };
    match class.signin_eligibility {
        ActionEligibility::Allowed => Ok(class.clone()),
        ActionEligibility::Denied => Err(unavailable("该课程当前不可重复签到")),
        ActionEligibility::Unknown => Err(upstream_error("课堂签到资格缺少必要字段")),
    }
}

/// 提交课堂签到请求。该接口有意保持低层；宿主调用前必须要求显式写操作确认。
#[allow(dead_code)]
pub(crate) async fn perform_signin(
    runtime: &mut crate::runtime::ClientRuntime,
    course_id: &str,
) -> Result<SigninActionResult> {
    preflight_signin(runtime, course_id).await?;
    let credential = current_credential(runtime).await?;
    let timestamp_url = signin_checkin_url(
        runtime.mode(),
        "app/common/get_timestamp.action",
        "app/common/get_timestamp.action",
    )?;
    let timestamp = runtime.request(HttpRequest::get(timestamp_url)).await?;
    if timestamp.status != 200 {
        return Err(upstream_error("无法获取签到时间戳"));
    }
    let timestamp = parse_timestamp(&timestamp.body)?;
    let url = build_signin_url(runtime.mode(), course_id, &timestamp)?;
    let response = submit_signin(runtime, url, &credential).await?;
    if response.status != 200 || final_url_is_authentication(&response.final_url) {
        return Err(write_outcome_unknown());
    }
    parse_action_response(&response.body)
}

fn signin_checkin_url(
    mode: crate::domain::ConnectionMode,
    direct_path: &str,
    webvpn_path: &str,
) -> Result<String> {
    let upstream_url = match mode {
        crate::domain::ConnectionMode::WebVpn => {
            format!("https://iclass.buaa.edu.cn:8347/{webvpn_path}")
        }
        crate::domain::ConnectionMode::Direct => {
            format!("http://iclass.buaa.edu.cn:8081/{direct_path}")
        }
    };
    match mode {
        crate::domain::ConnectionMode::Direct => Ok(upstream_url),
        crate::domain::ConnectionMode::WebVpn => crate::connection::to_webvpn_url(&upstream_url),
    }
}

fn build_signin_url(
    mode: crate::domain::ConnectionMode,
    course_id: &str,
    timestamp: &str,
) -> Result<String> {
    let base_url = signin_checkin_url(
        mode,
        "eschool/app/course/stu_scan_sign.action",
        "app/course/stu_scan_sign.action",
    )?;
    let mut url = url::Url::parse(&base_url).map_err(|_| invalid_url())?;
    url.query_pairs_mut()
        .append_pair("courseSchedId", course_id)
        .append_pair("timestamp", timestamp);
    Ok(url.to_string())
}

#[must_use]
fn build_signin_form(user_id: &str) -> Vec<(&'static str, String)> {
    vec![("id", user_id.into())]
}

async fn submit_signin(
    runtime: &mut crate::runtime::ClientRuntime,
    url: String,
    credential: &SigninCredential,
) -> Result<crate::ports::HttpResponse> {
    super::require_session(runtime)?;
    let body = url::form_urlencoded::Serializer::new(String::new())
        .extend_pairs(build_signin_form(&credential.user_id))
        .finish()
        .into_bytes();
    let mut request = HttpRequest::post(url, body);
    request.headers.insert(
        "Content-Type".into(),
        "application/x-www-form-urlencoded".into(),
    );
    request
        .headers
        .insert("sessionId".into(), credential.session_id.clone());
    runtime.request_non_idempotent(request).await
}

fn parse_action_response(body: &[u8]) -> Result<SigninActionResult> {
    let value: Value = serde_json::from_slice(body).map_err(|_| write_outcome_unknown())?;
    let object = value.as_object().ok_or_else(write_outcome_unknown)?;
    let status = object
        .get("STATUS")
        .and_then(action_status)
        .ok_or_else(write_outcome_unknown)?;
    let success = if matches!(status, 0 | 200) {
        match object
            .get("result")
            .and_then(Value::as_object)
            .and_then(|result| result.get("stuSignStatus"))
            .and_then(integer_value)
            .ok_or_else(write_outcome_unknown)?
        {
            1 => true,
            0 => false,
            _ => return Err(write_outcome_unknown()),
        }
    } else {
        false
    };
    Ok(SigninActionResult {
        code: if success { 200 } else { 400 },
        success,
        message: if success {
            "签到成功"
        } else {
            "签到未完成"
        }
        .to_owned(),
    })
}

fn action_status(value: &Value) -> Option<i64> {
    if value.as_str() == Some("success") {
        Some(0)
    } else {
        integer_value(value)
    }
}

fn final_url_is_authentication(value: &str) -> bool {
    crate::connection::is_sso_url(value)
}

fn parse_timestamp(body: &[u8]) -> Result<String> {
    let value: Value =
        serde_json::from_slice(body).map_err(|_| upstream_error("签到时间戳响应格式无效"))?;
    value
        .get("timestamp")
        .and_then(|value| match value {
            Value::String(text) => Some(text.trim().to_owned()),
            Value::Number(number) if number.is_i64() || number.is_u64() => Some(number.to_string()),
            _ => None,
        })
        .filter(|value| !value.is_empty())
        .ok_or_else(|| upstream_error("签到时间戳为空"))
}

fn build_today_request(
    base_url: &str,
    user_id: &str,
    session_id: &str,
    date: &str,
) -> Result<HttpRequest> {
    let mut url = url::Url::parse(base_url).map_err(|_| invalid_url())?;
    url.query_pairs_mut()
        .append_pair("id", user_id)
        .append_pair("dateStr", date);
    let mut request = HttpRequest::get(url.to_string());
    request
        .headers
        .insert("sessionId".into(), session_id.to_owned());
    Ok(request)
}

async fn get_today_once(
    runtime: &mut crate::runtime::ClientRuntime,
    allow_retry: bool,
    date: Option<&str>,
) -> Result<Vec<SigninClass>> {
    super::require_session(runtime)?;
    let credential = current_credential(runtime).await?;
    // 旧入口仍在每次认证后取当天日期；缓存入口固定同一次捕获的日期。
    let request_date = date.map_or_else(
        || crate::time::shanghai_compact_date(std::time::SystemTime::now()),
        str::to_owned,
    );
    let request = build_today_request(
        &runtime.url(SIGNIN_TODAY_URL)?,
        &credential.user_id,
        &credential.session_id,
        &request_date,
    )?;
    let response = runtime.request(request).await?;
    if response.status != 200 {
        return Err(upstream_error("签到查询服务暂时不可用"));
    }
    match parse_today(&super::body(&response)) {
        Ok(classes) => Ok(classes),
        Err(error) if allow_retry && error.code == ErrorCode::UpstreamChanged => {
            runtime.feature_state().signin.clear_credential();
            Box::pin(get_today_once(runtime, false, date)).await
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
    parse_login_credential(&response.body)
}

fn parse_login_credential(body: &[u8]) -> Result<SigninCredential> {
    let response: LoginResponse =
        serde_json::from_slice(body).map_err(|_| upstream_error("签到登录响应格式无效"))?;
    let result = response
        .result
        .filter(|_| success(&response.status))
        .ok_or_else(|| upstream_error("签到业务登录失败"))?;
    if result.id.trim().is_empty() {
        return Err(upstream_error("签到登录响应缺少会话字段"));
    }
    let session_id = result
        .session_id
        .map(|value| value.trim().to_owned())
        .filter(|value| !value.is_empty())
        .ok_or_else(|| upstream_error("签到登录响应缺少会话字段"))?;
    Ok(SigninCredential {
        user_id: result.id,
        session_id,
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
        let final_url = url::Url::parse(&final_direct).map_err(|_| invalid_url())?;
        ensure_login_host(&final_url)?;
        if let Some(login_name) = login_name_from_url(final_url.as_str()) {
            return Ok(login_name);
        }
        let location = response
            .header_first("location")
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
    if crate::connection::is_valid_auth_target(
        url,
        &["iclass.buaa.edu.cn", "sso.buaa.edu.cn"],
        true,
        &[8346, 8347],
    ) {
        Ok(())
    } else {
        Err(upstream_error("签到登录跳转到未允许的主机"))
    }
}

fn invalid_url() -> UbaaError {
    upstream_error("签到服务地址无效")
}

fn upstream_error(message: &'static str) -> UbaaError {
    UbaaError::upstream_changed(message)
}

fn validate_course_id(course_id: &str) -> Result<()> {
    if course_id.trim().is_empty() {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "课程编号不能为空",
        ));
    }
    Ok(())
}

fn unavailable(message: &'static str) -> UbaaError {
    UbaaError::new(ErrorCode::InvalidInput, ErrorKind::Input, true, message)
}

fn write_outcome_unknown() -> UbaaError {
    UbaaError::new(
        ErrorCode::OutcomeUnknown,
        ErrorKind::Upstream,
        false,
        "签到结果未知，请刷新今日状态后再决定是否重试",
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

fn map_row(row: Row) -> SigninClass {
    let sign_status = match row.sign_status {
        Value::Number(number) => number.as_i64(),
        Value::String(text) => text.parse::<i64>().ok(),
        _ => None,
    }
    .and_then(|value| i32::try_from(value).ok());
    let signin_target = (!row.id.trim().is_empty()).then(|| row.id.clone());
    let signin_eligibility = match (signin_target.as_ref(), sign_status) {
        (Some(_), Some(0)) => ActionEligibility::Allowed,
        (Some(_), Some(1)) => ActionEligibility::Denied,
        _ => ActionEligibility::Unknown,
    };
    SigninClass {
        course_id: row.id,
        course_name: row.course_name,
        class_begin_time: row.class_begin_time,
        class_end_time: row.class_end_time,
        sign_status,
        signin_eligibility,
        signin_target,
    }
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
mod contract_tests;

#[cfg(test)]
mod tests {
    use super::{
        SIGNIN_LOGIN_URL, build_signin_form, build_signin_url, build_today_request,
        final_url_is_authentication, integer_value, parse_login_credential, parse_timestamp,
        signin_checkin_url,
    };

    #[test]
    fn 直连与webvpn签到地址生成对齐冻结旧版() {
        let direct_ts = signin_checkin_url(
            crate::domain::ConnectionMode::Direct,
            "app/common/get_timestamp.action",
            "app/common/get_timestamp.action",
        )
        .expect("直连时间戳地址应可构造");
        assert_eq!(
            direct_ts,
            "http://iclass.buaa.edu.cn:8081/app/common/get_timestamp.action"
        );

        let direct_sign = build_signin_url(
            crate::domain::ConnectionMode::Direct,
            "course-123",
            "1700000000000",
        )
        .expect("直连签到提交地址应可构造");
        assert_eq!(
            direct_sign,
            "http://iclass.buaa.edu.cn:8081/eschool/app/course/stu_scan_sign.action?courseSchedId=course-123&timestamp=1700000000000"
        );

        let vpn_ts = signin_checkin_url(
            crate::domain::ConnectionMode::WebVpn,
            "app/common/get_timestamp.action",
            "app/common/get_timestamp.action",
        )
        .expect("WebVPN 时间戳地址应可构造");
        let vpn_ts_direct =
            crate::connection::from_webvpn_url(&vpn_ts).expect("WebVPN 应可反向解码");
        assert_eq!(
            vpn_ts_direct,
            "https://iclass.buaa.edu.cn:8347/app/common/get_timestamp.action"
        );

        let vpn_sign = build_signin_url(
            crate::domain::ConnectionMode::WebVpn,
            "course-123",
            "1700000000000",
        )
        .expect("WebVPN 签到提交地址应可构造");
        let vpn_sign_direct =
            crate::connection::from_webvpn_url(&vpn_sign).expect("WebVPN 应可反向解码");
        assert_eq!(
            vpn_sign_direct,
            "https://iclass.buaa.edu.cn:8347/app/course/stu_scan_sign.action?courseSchedId=course-123&timestamp=1700000000000"
        );
        assert!(!vpn_sign_direct.contains("eschool"));
    }

    #[test]
    fn 今日查询请求匹配冻结方法和会话头() {
        let request = build_today_request(
            "https://iclass.buaa.edu.cn:8347/app/course/get_stu_course_sched.action",
            "student-safe",
            "session-safe",
            "20260829",
        )
        .expect("今日查询请求应可构造");
        assert_eq!(request.method, crate::ports::HttpMethod::Get);
        assert_eq!(
            request.headers.get("sessionId").map(String::as_str),
            Some("session-safe")
        );
        assert!(!request.headers.contains_key("Sessionid"));
        let url = url::Url::parse(&request.url).expect("请求 URL 应有效");
        assert_eq!(
            url.query_pairs().find(|(k, _)| k == "id").unwrap().1,
            "student-safe"
        );
        assert_eq!(
            url.query_pairs().find(|(k, _)| k == "dateStr").unwrap().1,
            "20260829"
        );
    }

    #[test]
    fn 时间戳读取冻结的_json字段() {
        assert_eq!(
            parse_timestamp(br#"{"timestamp":"1700000000000"}"#).unwrap(),
            "1700000000000"
        );
        assert!(parse_timestamp(br"1700000000000").is_err());
    }

    #[test]
    fn 签到业务登录使用冻结旧版入口() {
        assert_eq!(
            SIGNIN_LOGIN_URL,
            "https://iclass.buaa.edu.cn:8347/app/user/login.action"
        );
    }

    #[test]
    fn 签到提交表单只发送冻结的用户标识字段() {
        let form = build_signin_form("user-safe");
        assert_eq!(form.len(), 1);
        assert_eq!(form[0], ("id", "user-safe".to_owned()));
    }

    #[test]
    fn 签到结果只把安全的_sso_地址判定为认证失效() {
        assert!(final_url_is_authentication(
            "https://sso.buaa.edu.cn/login?execution=fixture"
        ));
        for url in [
            "https://user@sso.buaa.edu.cn/login",
            "https://sso.buaa.edu.cn:8443/login",
            "https://sso.buaa.edu.cn.evil.example/login",
            "https://iclass.buaa.edu.cn/login",
        ] {
            assert!(!final_url_is_authentication(url), "不应误判认证地址：{url}");
        }
    }

    #[test]
    fn 登录响应包含会话标识时优先使用服务端会话() {
        let credential = parse_login_credential(
            r#"{"STATUS":"0","result":{"id":"user-1","sessionId":"session-1"}}"#.as_bytes(),
        )
        .expect("包含会话标识的响应应可解析");
        assert_eq!(credential.user_id, "user-1");
        assert_eq!(credential.session_id, "session-1");
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
