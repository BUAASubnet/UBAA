//! CAS authentication workflow and state for one client instance.

use std::collections::BTreeMap;

use url::Url;

use crate::domain::{LoginInput, UserProfile};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::features::user;
use crate::ports::{HttpRequest, HttpResponse};
use crate::runtime::ClientRuntime;
use crate::upstream::{
    SSO_LOGIN_URL, SSO_LOGOUT_URL, UC_ACTIVATE_URL, build_login_form, encode_form,
    extract_execution, find_login_error, has_unsupported_login_step, is_password_risk_page,
};

const MAX_REDIRECTS: usize = 10;

/// Pending login page scoped to one client instance.
#[derive(Clone, Default)]
pub(crate) struct LoginState {
    page: Option<String>,
    execution: Option<String>,
    authenticated_ready: bool,
}

impl std::fmt::Debug for LoginState {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("LoginState")
            .field("page", &self.page.as_ref().map(|_| "[REDACTED]"))
            .field("execution", &self.execution.as_ref().map(|_| "[REDACTED]"))
            .field("authenticated_ready", &self.authenticated_ready)
            .finish()
    }
}

impl LoginState {
    pub(crate) fn remember(&mut self, page: String, execution: String) {
        self.page = Some(page);
        self.execution = Some(execution);
        self.authenticated_ready = false;
    }

    pub(crate) fn remember_authenticated(&mut self) {
        self.clear();
        self.authenticated_ready = true;
    }

    pub(crate) fn page(&self) -> Option<&str> {
        self.page.as_deref()
    }

    pub(crate) fn execution(&self) -> Option<&str> {
        self.execution.as_deref()
    }

    pub(crate) const fn authenticated_ready(&self) -> bool {
        self.authenticated_ready
    }

    pub(crate) fn clear(&mut self) {
        *self = Self::default();
    }
}

/// Authentication workflow owned by the core facade.
#[derive(Default)]
pub(crate) struct AuthWorkflow {
    state: LoginState,
}

impl AuthWorkflow {
    pub(crate) async fn prepare_login(&mut self, runtime: &mut ClientRuntime) -> Result<()> {
        self.state.clear();
        let response = runtime
            .request(HttpRequest::get(runtime.url(SSO_LOGIN_URL)?))
            .await?;
        if is_redirect(response.status) {
            activate_user_center(runtime).await?;
            self.validate_status(runtime).await?;
            self.state.remember_authenticated();
            return Ok(());
        }
        if response.status != 200 {
            return Err(status_error(response.status, "SSO login page unavailable"));
        }
        let page = body_text(&response);
        let execution = extract_execution(&page)
            .ok_or_else(|| upstream_changed("SSO login page has no execution token"))?;
        if has_unsupported_login_step(&page) {
            return Err(upstream_changed(
                "SSO login page requires an unsupported interactive verification step",
            ));
        }
        self.state.remember(page, execution);
        Ok(())
    }

    pub(crate) async fn login(
        &mut self,
        runtime: &mut ClientRuntime,
        input: LoginInput,
    ) -> Result<UserProfile> {
        if input.username.trim().is_empty() || input.password.expose_secret().is_empty() {
            return Err(UbaaError::new(
                ErrorCode::InvalidInput,
                ErrorKind::Input,
                false,
                "username and password are required",
            ));
        }
        if self.state.authenticated_ready() {
            let profile = self.get_user_info(runtime).await?;
            return Ok(self.finish_successful_login(runtime, profile));
        }
        if self.state.page().is_none() {
            self.prepare_login(runtime).await?;
            if self.state.authenticated_ready() {
                let profile = self.get_user_info(runtime).await?;
                return Ok(self.finish_successful_login(runtime, profile));
            }
        }
        let page = self
            .state
            .page()
            .ok_or_else(|| upstream_changed("SSO login page state is unavailable"))?
            .to_string();
        let execution = self
            .state
            .execution()
            .ok_or_else(|| upstream_changed("SSO execution state is unavailable"))?
            .to_string();
        let form = build_login_form(&page, &input, &execution)?;
        let request = HttpRequest::post(runtime.url(SSO_LOGIN_URL)?, encode_form(&form))
            .with_header("Content-Type", "application/x-www-form-urlencoded");
        let response = runtime.request(request).await?;
        follow_login_response(runtime, response).await?;
        activate_user_center(runtime).await?;
        self.validate_status(runtime).await?;
        let profile = self.get_user_info(runtime).await?;
        Ok(self.finish_successful_login(runtime, profile))
    }

    fn finish_successful_login(
        &mut self,
        runtime: &ClientRuntime,
        profile: UserProfile,
    ) -> UserProfile {
        runtime.clear_feature_state();
        self.state.clear();
        profile
    }

    pub(crate) async fn logout(&mut self, runtime: &mut ClientRuntime) -> Result<()> {
        self.remote_logout(runtime).await;
        runtime.clear_with(|| self.state.clear())
    }

    pub(crate) async fn remote_logout(&mut self, runtime: &mut ClientRuntime) {
        if let Ok(url) = runtime.url(SSO_LOGOUT_URL) {
            let _ = runtime.request(HttpRequest::get(url)).await;
        }
    }

    pub(crate) fn clear(&mut self) {
        self.state.clear();
    }

    async fn validate_status(&mut self, runtime: &mut ClientRuntime) -> Result<()> {
        let mut clear_workflow = || self.state.clear();
        user::validate_status(runtime, &mut clear_workflow).await?;
        runtime.clear_feature_state();
        Ok(())
    }

    async fn get_user_info(&mut self, runtime: &mut ClientRuntime) -> Result<UserProfile> {
        let mut clear_workflow = || self.state.clear();
        user::get_user_info(runtime, &mut clear_workflow).await
    }
}

async fn follow_login_response(
    runtime: &mut ClientRuntime,
    mut response: HttpResponse,
) -> Result<()> {
    let mut redirects = 0_usize;
    let mut risk_ignored = false;
    loop {
        while is_redirect(response.status) {
            if redirects >= MAX_REDIRECTS {
                return Err(upstream_changed("SSO redirect limit exceeded"));
            }
            redirects += 1;
            let location = header_first(&response, "location")
                .ok_or_else(|| upstream_changed("SSO redirect has no Location"))?;
            let next =
                crate::connection::resolve_redirect(&response.final_url, location, runtime.mode())?;
            response = runtime.request(HttpRequest::get(next)).await?;
        }
        let body = body_text(&response);
        if is_password_risk_page(&body) {
            if risk_ignored {
                return Err(UbaaError::new(
                    ErrorCode::PasswordRiskConfirmationFailed,
                    ErrorKind::Authentication,
                    false,
                    "password-risk confirmation was not accepted",
                ));
            }
            risk_ignored = true;
            let execution = extract_execution(&body)
                .ok_or_else(|| upstream_changed("password-risk page has no execution token"))?;
            let form = BTreeMap::from([
                ("execution".to_string(), execution),
                ("_eventId".to_string(), "ignoreAndContinue".to_string()),
            ]);
            let target = strip_query(&response.final_url)?;
            response = runtime
                .request(
                    HttpRequest::post(target, encode_form(&form))
                        .with_header("Content-Type", "application/x-www-form-urlencoded"),
                )
                .await?;
            continue;
        }
        if response.status >= 500 {
            return Err(status_error(response.status, "SSO is unavailable"));
        }
        if response.status == 401
            || find_login_error(&body).is_some()
            || extract_execution(&body).is_some()
        {
            return Err(UbaaError::new(
                ErrorCode::InvalidCredentials,
                ErrorKind::Authentication,
                false,
                find_login_error(&body)
                    .unwrap_or_else(|| "username or password was rejected".into()),
            ));
        }
        return Ok(());
    }
}

async fn activate_user_center(runtime: &mut ClientRuntime) -> Result<()> {
    let mut response = runtime
        .request(HttpRequest::get(runtime.url(UC_ACTIVATE_URL)?))
        .await?;
    for _ in 0..MAX_REDIRECTS {
        if !is_redirect(response.status) {
            return if response.status >= 500 {
                Err(status_error(
                    response.status,
                    "User Center activation failed",
                ))
            } else {
                Ok(())
            };
        }
        let location = header_first(&response, "location")
            .ok_or_else(|| upstream_changed("activation redirect has no Location"))?;
        let next =
            crate::connection::resolve_redirect(&response.final_url, location, runtime.mode())?;
        response = runtime.request(HttpRequest::get(next)).await?;
    }
    Err(upstream_changed("activation redirect limit exceeded"))
}

fn is_redirect(status: u16) -> bool {
    (300..400).contains(&status)
}

fn header_first<'a>(response: &'a HttpResponse, name: &str) -> Option<&'a str> {
    response
        .headers
        .iter()
        .find(|(key, _)| key.eq_ignore_ascii_case(name))
        .and_then(|(_, values)| values.first())
        .map(String::as_str)
}

fn body_text(response: &HttpResponse) -> String {
    String::from_utf8_lossy(&response.body).into_owned()
}

fn strip_query(url: &str) -> Result<String> {
    let mut parsed = Url::parse(url).map_err(|_| upstream_changed("invalid password-risk URL"))?;
    parsed.set_query(None);
    Ok(parsed.to_string())
}

fn upstream_changed(message: impl Into<String>) -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        message,
    )
}

fn status_error(status: u16, message: impl Into<String>) -> UbaaError {
    if status >= 500 {
        UbaaError::new(
            ErrorCode::UpstreamUnavailable,
            ErrorKind::Upstream,
            true,
            message,
        )
    } else {
        upstream_changed(message)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn debug_formatting_redacts_pending_login_state() {
        let mut state = LoginState::default();
        state.remember(
            "<html>PAGE-SENTINEL</html>".into(),
            "EXECUTION-SENTINEL".into(),
        );

        let formatted = format!("{state:?}");
        for sentinel in ["PAGE-SENTINEL", "EXECUTION-SENTINEL"] {
            assert!(
                !formatted.contains(sentinel),
                "leaked {sentinel} in {formatted}"
            );
        }
    }
}
