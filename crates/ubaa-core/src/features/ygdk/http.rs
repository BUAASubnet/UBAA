//! 阳光打卡表单请求、query 双写与公共请求头。

use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::HttpRequest;
use crate::runtime::ClientRuntime;

use super::YgdkCredential;
use super::parser::error;

pub(super) const FRONT_BASE: &str = "https://ygdk.buaa.edu.cn";
const GENERATION_GUARD_MESSAGE: &str = "阳光打卡业务会话已变化，请重新读取并确认";
const SESSION_GUARD_MESSAGE: &str = "阳光打卡本地会话状态检查失败";

pub(super) async fn post(
    runtime: &mut ClientRuntime,
    path: &str,
    credential: &YgdkCredential,
    generation: u64,
    params: &[(&str, String)],
) -> Result<String> {
    post_request(runtime, path, credential, generation, params, false).await
}

pub(super) async fn post_with_query(
    runtime: &mut ClientRuntime,
    path: &str,
    credential: &YgdkCredential,
    generation: u64,
    params: &[(&str, String)],
) -> Result<String> {
    post_request(runtime, path, credential, generation, params, true).await
}

pub(super) async fn post_non_idempotent(
    runtime: &mut ClientRuntime,
    path: &str,
    credential: &YgdkCredential,
    generation: u64,
    params: &[(&str, String)],
) -> Result<String> {
    let request = build_post_request(runtime, path, credential, params, false)?;
    let expected_final_url = request.url.clone();
    let response = runtime
        .request_non_idempotent_with_pre_send_check(request, |runtime| {
            ensure_active_credential(runtime, generation, credential)
        })
        .await
        .map_err(|error| {
            if error.code == ErrorCode::OutcomeUnknown {
                super::write_outcome_unknown()
            } else {
                error
            }
        })?;
    if response.status != 200 || response.final_url != expected_final_url {
        return Err(super::write_outcome_unknown());
    }
    Ok(super::super::body(&response))
}

async fn post_request(
    runtime: &mut ClientRuntime,
    path: &str,
    credential: &YgdkCredential,
    generation: u64,
    params: &[(&str, String)],
    duplicate_params_in_query: bool,
) -> Result<String> {
    let request = build_post_request(runtime, path, credential, params, duplicate_params_in_query)?;
    let expected_final_url = request.url.clone();
    let response = runtime
        .request_with_pre_send_check(request, |runtime| {
            ensure_active_credential(runtime, generation, credential)
        })
        .await?;
    if response.status != 200 || response.final_url != expected_final_url {
        return Err(error("阳光打卡服务暂时不可用"));
    }
    Ok(super::super::body(&response))
}

fn build_post_request(
    runtime: &mut ClientRuntime,
    path: &str,
    credential: &YgdkCredential,
    params: &[(&str, String)],
    duplicate_params_in_query: bool,
) -> Result<HttpRequest> {
    let mut form: Vec<(&str, String)> = params.iter().map(|(k, v)| (*k, v.clone())).collect();
    form.push(("uid", credential.uid.to_string()));
    form.push(("token", credential.token.clone()));
    let body = url::form_urlencoded::Serializer::new(String::new())
        .extend_pairs(form.iter().map(|(k, v)| (*k, v.as_str())))
        .finish()
        .into_bytes();
    let mut direct = url::Url::parse(&format!("{FRONT_BASE}{path}"))
        .map_err(|_| error("阳光打卡请求地址无效"))?;
    if duplicate_params_in_query {
        direct
            .query_pairs_mut()
            .extend_pairs(params.iter().map(|(key, value)| (*key, value.as_str())));
    }
    let mut request = HttpRequest::post(runtime.url(direct.as_str())?, body);
    request.headers.insert(
        "Content-Type".into(),
        "application/x-www-form-urlencoded; charset=UTF-8".into(),
    );
    request
        .headers
        .insert("X-Requested-With".into(), "XMLHttpRequest".into());
    Ok(request)
}

/// 在 transport 交付点确认请求使用的凭据仍属于当前业务代次。
pub(super) fn ensure_active_credential(
    runtime: &ClientRuntime,
    generation: u64,
    credential: &YgdkCredential,
) -> Result<()> {
    ensure_active_generation(runtime, generation)?;
    let state = runtime.feature_state();
    let current = state.ygdk.credential();
    let generation_after = state.ygdk.generation();
    if generation_after != generation || current.as_ref() != Some(credential) {
        return Err(generation_guard_error());
    }
    Ok(())
}

/// 在 OAuth 与业务登录链的每次发送入口确认会话及业务代次仍然有效。
pub(super) fn ensure_active_generation(runtime: &ClientRuntime, generation: u64) -> Result<()> {
    runtime.ensure_session_revision().map_err(|error| {
        UbaaError::new(
            error.code,
            error.kind,
            error.retryable,
            SESSION_GUARD_MESSAGE,
        )
    })?;
    let state = runtime.feature_state();
    let generation_before = state.ygdk.generation();
    let generation_after = state.ygdk.generation();
    if generation_before != generation || generation_after != generation {
        return Err(generation_guard_error());
    }
    Ok(())
}

fn generation_guard_error() -> UbaaError {
    UbaaError::new(
        ErrorCode::AuthenticationRequired,
        ErrorKind::Authentication,
        false,
        GENERATION_GUARD_MESSAGE,
    )
}

pub(super) fn is_pre_send_credential_error(error: &UbaaError) -> bool {
    matches!(
        (error.code, error.message.as_str()),
        (ErrorCode::AuthenticationRequired, GENERATION_GUARD_MESSAGE)
            | (ErrorCode::InternalError, SESSION_GUARD_MESSAGE)
    )
}
