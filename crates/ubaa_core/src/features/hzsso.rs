//! 杭州校区统一身份认证（hzsso，竹云 `IDaaS` 4.18）经「北航登录」CAS 插件的登录。
//!
//! hzsso 的 CAS 插件以 `sso.buaa.edu.cn` 为上游，因此只要主会话仍有效，就能不再输入
//! 杭州密码完成登录。流程、字段与证据见 `docs/protocol/parity/cgyy.md` 杭州专项记录：
//!
//! 1. `GET /api/public/bff/v1.2/frontend/login_data` → `data.clientId`
//! 2. `POST /api/public/bff/v1.2/authenticate/plugin/generate_trace_id` → `data.traceId`
//! 3. `POST /public/api/authenticate/plugin_cas/login` → `loginUrl`（北航 CAS）
//! 4. 主会话跟随 `loginUrl`，落到 `plugin_cas/static/callback.html?ticket=`
//! 5. `POST /public/api/authenticate/plugin_cas/valid_ticket`
//! 6. `POST /api/public/bff/v1.2/authenticate/plugin/validate_trace_id` → `data.accessToken`
//! 7. `POST /api/bff/v1.2/commons/session/save`（`Bearer` + `access_token`）
//!
//! 令牌、票据和 traceId 只在本次调用内存中流转，不写入会话文件或日志。

use serde_json::{Value, json};
use tracing::{debug, info, warn};

use crate::domain::ConnectionMode;
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::{HttpRequest, HttpResponse};
use crate::runtime::ClientRuntime;

const ORIGIN: &str = "http://hzsso.buaa.edu.cn";
const HOST: &str = "hzsso.buaa.edu.cn";
const ENTERPRISE_ID: &str = "idaas";
const CAS_AUTH_ID: &str = "idaasplugin_cas";
const LOGIN_PATH: &str = "/login";
const LOGIN_PAGE_PREFIX: &str = "/frontend/login";
const CAS_CALLBACK_PATH: &str = "/public/api/authenticate/plugin_cas/static/callback.html";

/// 杭州系统目前只验证过直连；北航 `WebVPN` 能否访问杭州主机没有证据，不做猜测性转换。
pub(crate) fn require_direct_route(runtime: &ClientRuntime) -> Result<()> {
    if runtime.mode() == ConnectionMode::Direct {
        return Ok(());
    }
    Err(UbaaError::new(
        ErrorCode::Unsupported,
        ErrorKind::Upstream,
        false,
        "杭州校区服务暂只支持直连",
    )
    .with_diagnostic("route", "hangzhou_webvpn_unverified"))
}

/// 经 hzsso 的应用 SSO 入口进入杭州业务系统；hzsso 未登录时先用北航 CAS 插件登录，再重进一次。
pub(crate) async fn enter_application(
    runtime: &mut ClientRuntime,
    application_url: &str,
    feature: &str,
) -> Result<HttpResponse> {
    require_direct_route(runtime)?;
    let response =
        super::get_with_redirects(runtime, application_url.to_owned(), &[], feature).await?;
    if !is_login_page(&response.final_url) {
        debug!(target: "ubaa::hzsso", operation = "application.enter", reused_session = true, "hzsso 会话有效，直接进入应用");
        return Ok(response);
    }
    login(runtime, feature).await?;
    let response =
        super::get_with_redirects(runtime, application_url.to_owned(), &[], feature).await?;
    if is_login_page(&response.final_url) {
        warn!(target: "ubaa::hzsso", operation = "application.enter", "hzsso 登录完成后仍回到登录页");
        return Err(authentication_error("杭州统一认证登录后仍未进入应用"));
    }
    Ok(response)
}

async fn login(runtime: &mut ClientRuntime, feature: &str) -> Result<()> {
    info!(target: "ubaa::hzsso", operation = "login", "开始经北航统一认证登录 hzsso");
    let login_data = get_json(runtime, "/api/public/bff/v1.2/frontend/login_data", feature).await?;
    let client_id = data_string(&login_data, "clientId")?;

    let trace = post_json(
        runtime,
        "/api/public/bff/v1.2/authenticate/plugin/generate_trace_id",
        &json!({
            "enterpriseAuthId": CAS_AUTH_ID,
            "enterpriseId": ENTERPRISE_ID,
            "clientId": client_id,
        }),
        None,
        feature,
    )
    .await?;
    let trace_id = data_string(&trace, "traceId")?;

    let cas = post_json(
        runtime,
        "/public/api/authenticate/plugin_cas/login",
        &json!({"enterpriseAuthId": CAS_AUTH_ID, "traceId": trace_id}),
        None,
        feature,
    )
    .await?;
    require_success(&cas, "杭州统一认证未返回北航登录地址")?;
    let cas_url = top_string(&cas, "loginUrl")?;
    if !crate::connection::is_allowed_auth_host(&cas_url) {
        return Err(changed("杭州统一认证返回了非北航认证地址"));
    }

    let callback = super::get_with_redirects(runtime, cas_url, &[], feature).await?;
    let ticket = callback_ticket(&callback.final_url).ok_or_else(|| {
        warn!(target: "ubaa::hzsso", operation = "login.cas", "北航统一认证未签发 hzsso 票据");
        authentication_error("北航统一认证未签发杭州统一认证票据")
    })?;
    debug!(target: "ubaa::hzsso", operation = "login.cas", ticket_len = ticket.len(), "已取得 hzsso CAS 票据");

    let valid = post_json(
        runtime,
        "/public/api/authenticate/plugin_cas/valid_ticket",
        &json!({"enterpriseAuthId": CAS_AUTH_ID, "traceId": trace_id, "ticket": ticket}),
        None,
        feature,
    )
    .await?;
    require_success(&valid, "杭州统一认证拒绝了北航票据")?;

    let verified = post_json(
        runtime,
        "/api/public/bff/v1.2/authenticate/plugin/validate_trace_id",
        &json!({"traceId": trace_id}),
        None,
        feature,
    )
    .await?;
    let access_token = data_string(&verified, "accessToken")?;

    let saved = post_json(
        runtime,
        "/api/bff/v1.2/commons/session/save",
        &json!({"access_token": access_token}),
        Some(&access_token),
        feature,
    )
    .await?;
    if saved.get("data").and_then(|data| data.get("result")) != Some(&Value::Bool(true)) {
        return Err(authentication_error("杭州统一认证未保存登录会话"));
    }
    info!(target: "ubaa::hzsso", operation = "login", access_token_len = access_token.len(), "hzsso 登录完成");
    Ok(())
}

async fn get_json(runtime: &mut ClientRuntime, path: &str, feature: &str) -> Result<Value> {
    let mut request = HttpRequest::get(format!("{ORIGIN}{path}"));
    request
        .headers
        .insert("Accept".into(), "application/json, text/plain, */*".into());
    send(runtime, request, path, feature).await
}

async fn post_json(
    runtime: &mut ClientRuntime,
    path: &str,
    body: &Value,
    bearer: Option<&str>,
    feature: &str,
) -> Result<Value> {
    let mut request = HttpRequest::post(format!("{ORIGIN}{path}"), body.to_string().into_bytes());
    request
        .headers
        .insert("Accept".into(), "application/json, text/plain, */*".into());
    request.headers.insert(
        "Content-Type".into(),
        "application/json;charset=UTF-8".into(),
    );
    if let Some(token) = bearer {
        request
            .headers
            .insert("Authorization".into(), format!("Bearer {token}"));
    }
    send(runtime, request, path, feature).await
}

async fn send(
    runtime: &mut ClientRuntime,
    request: HttpRequest,
    path: &str,
    feature: &str,
) -> Result<Value> {
    let response = runtime.request(request).await?;
    debug!(target: "ubaa::hzsso", operation = path, status = response.status, body_len = response.body.len(), "收到 hzsso 响应");
    if response.status == 401 {
        return Err(authentication_error("杭州统一认证需要重新登录"));
    }
    if response.status != 200 {
        return Err(super::http::http_status_error(&response, feature));
    }
    serde_json::from_slice(&response.body).map_err(|_| changed("杭州统一认证响应不是 JSON"))
}

/// 未登录时应用入口 302 到 `/login`（2026-11-25 真机诊断），浏览器再由该页跳到
/// `/frontend/login/`；两者都视为 hzsso 登录页。
fn is_login_page(url: &str) -> bool {
    url::Url::parse(url).is_ok_and(|url| {
        url.host_str()
            .is_some_and(|host| host.eq_ignore_ascii_case(HOST))
            && (url.path() == LOGIN_PATH || url.path().starts_with(LOGIN_PAGE_PREFIX))
    })
}

fn callback_ticket(url: &str) -> Option<String> {
    let url = url::Url::parse(url).ok()?;
    if !url.host_str()?.eq_ignore_ascii_case(HOST) || url.path() != CAS_CALLBACK_PATH {
        return None;
    }
    url.query_pairs()
        .find(|(name, _)| name == "ticket")
        .map(|(_, value)| value.into_owned())
        .filter(|ticket| !ticket.is_empty())
}

fn require_success(value: &Value, message: &str) -> Result<()> {
    if value.get("success") == Some(&Value::Bool(true)) {
        Ok(())
    } else {
        Err(authentication_error(message))
    }
}

fn data_string(value: &Value, key: &str) -> Result<String> {
    value
        .get("data")
        .and_then(|data| data.get(key))
        .and_then(Value::as_str)
        .filter(|text| !text.is_empty())
        .map(str::to_owned)
        .ok_or_else(|| changed("杭州统一认证响应缺少必要字段"))
}

fn top_string(value: &Value, key: &str) -> Result<String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .filter(|text| !text.is_empty())
        .map(str::to_owned)
        .ok_or_else(|| changed("杭州统一认证响应缺少必要字段"))
}

#[track_caller]
fn authentication_error(message: &str) -> UbaaError {
    UbaaError::new(
        ErrorCode::AuthenticationRequired,
        ErrorKind::Authentication,
        false,
        message,
    )
}

#[track_caller]
fn changed(message: &str) -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        message,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 只从hzsso回调页取票据() {
        assert_eq!(
            callback_ticket(
                "http://hzsso.buaa.edu.cn/public/api/authenticate/plugin_cas/static/callback.html?enterpriseAuthId=idaasplugin_cas&ticket=ST-x"
            )
            .as_deref(),
            Some("ST-x")
        );
        assert_eq!(
            callback_ticket("https://sso.buaa.edu.cn/login?ticket=ST-x"),
            None
        );
        assert_eq!(
            callback_ticket(
                "http://hzsso.buaa.edu.cn/public/api/authenticate/plugin_cas/static/callback.html?ticket="
            ),
            None
        );
    }

    #[test]
    fn 识别hzsso登录页() {
        assert!(is_login_page(
            "http://hzsso.buaa.edu.cn/frontend/login/#/login?sp_code=x"
        ));
        assert!(is_login_page("http://hzsso.buaa.edu.cn/login"));
        assert!(!is_login_page("http://hzsso.buaa.edu.cn/loginx"));
        assert!(!is_login_page("https://hzsm.buaa.edu.cn/venue/login"));
    }
}
