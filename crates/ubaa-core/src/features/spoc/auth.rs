//! SPOC CAS 引导、路线约束与业务凭据重试。

use std::future::Future;
use std::pin::Pin;

use super::SpocCredential;
use super::parser::{parse_optional_envelope, resolve_role_code, spoc_auth_error};

/// 不跟随重定向的 CAS 令牌引导地址。
pub const CAS_URL: &str = "https://spoc.buaa.edu.cn/spocnewht/cas";
/// CAS 角色/令牌激活地址。
pub const CAS_LOGIN_URL: &str = "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin";

async fn login(
    runtime: &mut crate::runtime::ClientRuntime,
) -> crate::error::Result<SpocCredential> {
    let token = fetch_login_token(runtime).await?;
    let token_header = format!("Inco-{token}");
    let cas = crate::features::post_json(
        runtime,
        runtime.url(CAS_LOGIN_URL)?,
        serde_json::json!({ "token": &token })
            .to_string()
            .into_bytes(),
        &[
            ("X-Requested-With", "XMLHttpRequest"),
            ("Token", &token_header),
        ],
    )
    .await?;
    check_business_response(&cas)?;
    let content: serde_json::Value =
        parse_optional_envelope(&crate::features::body(&cas))?.ok_or_else(spoc_auth_error)?;
    let role = resolve_role_code(&content).ok_or_else(spoc_auth_error)?;
    Ok(SpocCredential::new(token, role))
}

async fn ensure_credential(
    runtime: &mut crate::runtime::ClientRuntime,
    force_refresh: bool,
) -> crate::error::Result<SpocCredential> {
    let state = runtime.feature_state();
    if !force_refresh && let Some(credential) = state.spoc.credential() {
        return Ok(credential);
    }
    let _guard = state.spoc.login_guard().await;
    if force_refresh {
        state.spoc.clear_credential();
    } else if let Some(credential) = state.spoc.credential() {
        return Ok(credential);
    }
    let generation = state.spoc.generation();
    let credential = login(runtime).await?;
    state
        .spoc
        .store_credential(generation, credential.clone())
        .then_some(credential)
        .ok_or_else(spoc_auth_error)
}

type SpocOperationFuture<'a, T> =
    Pin<Box<dyn Future<Output = crate::error::Result<T>> + Send + 'a>>;

pub(super) async fn with_spoc_auth_retry<T, F>(
    runtime: &mut crate::runtime::ClientRuntime,
    mut operation: F,
) -> crate::error::Result<T>
where
    T: Send,
    F: for<'a> FnMut(
            &'a mut crate::runtime::ClientRuntime,
            &'a SpocCredential,
        ) -> SpocOperationFuture<'a, T>
        + Send,
{
    let credential = ensure_credential(runtime, false).await?;
    match operation(runtime, &credential).await {
        Err(error) if is_authentication_error(&error) => {
            let credential = ensure_credential(runtime, true).await?;
            operation(runtime, &credential).await
        }
        result => result,
    }
}

pub(super) async fn resolve_required_spoc_result<T>(
    runtime: &mut crate::runtime::ClientRuntime,
    result: crate::error::Result<T>,
) -> crate::error::Result<T> {
    match result {
        Err(error) if is_authentication_error(&error) => {
            resolve_spoc_business_authentication_failure(runtime).await
        }
        result => result,
    }
}

async fn resolve_spoc_business_authentication_failure<T>(
    runtime: &mut crate::runtime::ClientRuntime,
) -> crate::error::Result<T> {
    let mut preserve_primary_workflow = || {};
    match crate::features::user::validate_status(runtime, &mut preserve_primary_workflow).await {
        Err(error) if is_authentication_error(&error) => Err(error),
        Ok(_) | Err(_) => Err(spoc_business_authentication_error()),
    }
}

async fn fetch_login_token(
    runtime: &mut crate::runtime::ClientRuntime,
) -> crate::error::Result<String> {
    let mut current = runtime.url(CAS_URL)?;
    for _ in 0..8 {
        if let Some(token) = extract_login_token(&current, runtime.mode()) {
            return Ok(token);
        }
        let response = crate::features::get_with_headers(runtime, current.clone(), &[]).await?;
        if let Some(token) = extract_login_token(&response.final_url, runtime.mode()) {
            return Ok(token);
        }
        if response.status == 401 {
            return Err(spoc_auth_error());
        }
        if !(300..400).contains(&response.status) {
            crate::features::check_response(&response, "spoc")?;
            return Err(spoc_auth_error());
        }
        let location = response
            .headers
            .iter()
            .find(|(name, _)| name.eq_ignore_ascii_case("location"))
            .and_then(|(_, values)| values.first())
            .ok_or_else(spoc_auth_error)?;
        if let Some(token) = extract_login_token(location, runtime.mode()) {
            return Ok(token);
        }
        current = resolve_login_redirect(&response.final_url, location, runtime.mode())?;
    }
    Err(spoc_auth_error())
}

fn resolve_login_redirect(
    current: &str,
    location: &str,
    mode: crate::domain::ConnectionMode,
) -> crate::error::Result<String> {
    let routed_base = url::Url::parse(current).map_err(|_| spoc_auth_error())?;
    let routed_target = if location.starts_with("//") {
        url::Url::parse(&format!("{}:{location}", routed_base.scheme()))
            .map_err(|_| spoc_auth_error())?
    } else {
        routed_base.join(location).map_err(|_| spoc_auth_error())?
    };
    let routed_is_gateway = routed_target
        .host_str()
        .is_some_and(|host| host.eq_ignore_ascii_case("d.buaa.edu.cn"));
    if mode == crate::domain::ConnectionMode::Direct && routed_is_gateway {
        return Err(spoc_auth_error());
    }
    let direct = crate::connection::from_webvpn_url(routed_target.as_str())
        .map_err(|_| spoc_auth_error())?;
    let direct_target = url::Url::parse(&direct).map_err(|_| spoc_auth_error())?;
    if direct_target.scheme() != "https"
        || !direct_target.host_str().is_some_and(|host| {
            matches!(
                host.to_ascii_lowercase().as_str(),
                "spoc.buaa.edu.cn" | "sso.buaa.edu.cn"
            )
        })
    {
        return Err(spoc_auth_error());
    }
    if mode == crate::domain::ConnectionMode::WebVpn {
        if routed_is_gateway {
            Ok(routed_target.to_string())
        } else {
            crate::connection::to_webvpn_url(direct_target.as_str()).map_err(|_| spoc_auth_error())
        }
    } else {
        Ok(direct_target.to_string())
    }
}

fn spoc_business_authentication_error() -> crate::error::UbaaError {
    crate::error::UbaaError::new(
        crate::error::ErrorCode::UpstreamUnavailable,
        crate::error::ErrorKind::Upstream,
        true,
        "SPOC 业务认证失败，但未明确要求使主会话失效",
    )
}

fn is_authentication_error(error: &crate::error::UbaaError) -> bool {
    error.code == crate::error::ErrorCode::AuthenticationRequired
}

pub(super) fn check_business_response(
    response: &crate::ports::HttpResponse,
) -> crate::error::Result<()> {
    if response_location_targets_sso(response) {
        return Err(spoc_auth_error());
    }
    crate::features::check_response(response, "spoc")
}

fn response_location_targets_sso(response: &crate::ports::HttpResponse) -> bool {
    response
        .headers
        .iter()
        .find(|(name, _)| name.eq_ignore_ascii_case("location"))
        .and_then(|(_, values)| values.first())
        .is_some_and(|location| {
            let resolved = url::Url::parse(&response.final_url)
                .ok()
                .and_then(|base| base.join(location).ok())
                .map_or_else(|| location.clone(), |target| target.to_string());
            let direct =
                crate::connection::from_webvpn_url(&resolved).unwrap_or_else(|_| resolved.clone());
            url::Url::parse(&direct)
                .ok()
                .and_then(|target| target.host_str().map(str::to_ascii_lowercase))
                .is_some_and(|host| host == "sso.buaa.edu.cn")
        })
}

pub(super) fn extract_login_token(
    candidate: &str,
    mode: crate::domain::ConnectionMode,
) -> Option<String> {
    let raw = url::Url::parse(candidate).ok()?;
    let raw_is_gateway = raw
        .host_str()
        .is_some_and(|host| host.eq_ignore_ascii_case("d.buaa.edu.cn"));
    if (mode == crate::domain::ConnectionMode::Direct && raw_is_gateway)
        || (mode == crate::domain::ConnectionMode::WebVpn && !raw_is_gateway)
    {
        return None;
    }
    let direct = crate::connection::from_webvpn_url(candidate).ok()?;
    let parsed = url::Url::parse(&direct).ok()?;
    if parsed.scheme() != "https"
        || !parsed
            .host_str()
            .is_some_and(|host| host.eq_ignore_ascii_case("spoc.buaa.edu.cn"))
        || parsed.path() != "/spocnew/cas"
    {
        return None;
    }
    parsed
        .query_pairs()
        .find(|(key, _)| key == "token")
        .map(|(_, value)| value.into_owned())
        .filter(|value| !value.trim().is_empty())
}
