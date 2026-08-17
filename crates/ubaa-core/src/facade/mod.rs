//! Stable facade consumed by CLI and future bindings.

use std::path::Path;

use base64::Engine as _;
use url::Url;

use crate::auth::LoginState;
use crate::connection::resolve_redirect;
use crate::domain::{AuthStatus, ConnectionMode, LoginChallenge, LoginInput, UserProfile};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::features::user::looks_unauthenticated;
use crate::ports::{HttpRequest, HttpResponse, HttpTransport, ReqwestTransport};
use crate::runtime::ClientRuntime;
use crate::session::{FileSessionStore, SessionStore};
use crate::upstream::{
    SSO_CAPTCHA_URL, SSO_LOGIN_URL, SSO_LOGOUT_URL, UC_ACTIVATE_URL, UC_STATUS_URL,
    UC_USERINFO_URL, build_captcha_form, build_login_form, detect_captcha, encode_form,
    extract_execution, find_login_error, is_password_risk_page, parse_user_info,
};

const MAX_REDIRECTS: usize = 10;

/// One independent Direct or `WebVPN` session and login state machine.
pub struct UbaaClient {
    runtime: ClientRuntime,
    login_state: LoginState,
}

impl UbaaClient {
    /// Construct a production client rooted at a host-selected configuration directory.
    ///
    /// # Errors
    ///
    /// Returns a safe transport or persistence error.
    pub fn new(mode: ConnectionMode, config_dir: impl AsRef<Path>) -> Result<Self> {
        Self::with_transport(
            mode,
            ReqwestTransport::new()?,
            FileSessionStore::new(config_dir)?,
        )
    }

    /// Construct a client with injected transport and persistence ports.
    ///
    /// # Errors
    ///
    /// Returns a safe persistence error when an existing session cannot be loaded.
    pub fn with_transport<T, S>(mode: ConnectionMode, transport: T, store: S) -> Result<Self>
    where
        T: HttpTransport + 'static,
        S: SessionStore + 'static,
    {
        Ok(Self {
            runtime: ClientRuntime::new(mode, transport, store)?,
            login_state: LoginState::default(),
        })
    }

    /// Return this client's fixed connection mode.
    #[must_use]
    pub const fn mode(&self) -> ConnectionMode {
        self.runtime.mode()
    }

    /// Load the current SSO page and retain its execution/Cookie challenge in this client.
    ///
    /// # Errors
    ///
    /// Returns a safe network, authentication, or upstream protocol error.
    pub async fn prepare_login(&mut self) -> Result<Option<LoginChallenge>> {
        let response = self
            .request(HttpRequest::get(self.url(SSO_LOGIN_URL)?))
            .await?;
        if is_redirect(response.status) {
            self.activate_user_center().await?;
            self.validate_status().await?;
            self.login_state.clear();
            return Ok(None);
        }
        if response.status != 200 {
            return Err(status_error(response.status, "SSO login page unavailable"));
        }
        let page = body_text(&response);
        let execution = extract_execution(&page)
            .ok_or_else(|| upstream_changed("SSO login page has no execution token"))?;
        let challenge = match detect_captcha(&page) {
            Some((_kind, id)) => Some(self.fetch_captcha(id, execution.clone()).await?),
            None => None,
        };
        self.login_state
            .remember(page, execution, challenge.clone());
        Ok(challenge)
    }

    /// Submit one credential/captcha form, activate User Center, and return its parsed profile.
    ///
    /// # Errors
    ///
    /// Returns a stable input, captcha, authentication, network, or upstream error.
    pub async fn login(&mut self, input: LoginInput) -> Result<UserProfile> {
        if input.username.trim().is_empty() || input.password.expose_secret().is_empty() {
            return Err(UbaaError::new(
                ErrorCode::InvalidInput,
                ErrorKind::Input,
                false,
                "username and password are required",
            ));
        }
        if self.login_state.page().is_none() {
            let challenge = self.prepare_login().await?;
            if challenge.is_none() && self.runtime.authenticated_at().is_some() {
                return self.get_user_info().await;
            }
        }
        let page = self
            .login_state
            .page()
            .ok_or_else(|| upstream_changed("SSO login page state is unavailable"))?
            .to_string();
        let execution = self
            .login_state
            .execution()
            .ok_or_else(|| upstream_changed("SSO execution state is unavailable"))?
            .to_string();
        let captcha_required =
            self.login_state.challenge().is_some() || detect_captcha(&page).is_some();
        if captcha_required && input.captcha.as_deref().is_none_or(str::is_empty) {
            let challenge = self
                .login_state
                .challenge()
                .cloned()
                .ok_or_else(|| upstream_changed("captcha state is unavailable"))?;
            return Err(UbaaError::new(
                ErrorCode::CaptchaRequired,
                ErrorKind::Authentication,
                true,
                "captcha input is required",
            )
            .with_challenge(challenge));
        }
        let form = if captcha_required || input.captcha.is_some() {
            build_captcha_form(&input, &execution)
        } else {
            build_login_form(&page, &input, &execution)?
        };
        let request = HttpRequest::post(self.url(SSO_LOGIN_URL)?, encode_form(&form))
            .with_header("Content-Type", "application/x-www-form-urlencoded");
        let response = self.request(request).await?;
        self.follow_login_response(response).await?;
        self.activate_user_center().await?;
        self.validate_status().await?;
        let profile = self.get_user_info().await?;
        self.login_state.clear();
        Ok(profile)
    }

    /// Validate the current User Center session and refresh last activity.
    ///
    /// # Errors
    ///
    /// Returns authentication-required for explicit invalidation while preserving state on timeout/5xx.
    pub async fn auth_status(&mut self) -> Result<AuthStatus> {
        if !self.runtime.has_local_session() {
            return Err(authentication_required());
        }
        self.validate_status().await
    }

    /// Fetch and parse the latest User Center profile.
    ///
    /// # Errors
    ///
    /// Returns a stable authentication, network, availability, or parsing error.
    pub async fn get_user_info(&mut self) -> Result<UserProfile> {
        let response = self
            .request(HttpRequest::get(self.url(UC_USERINFO_URL)?))
            .await?;
        let body = body_text(&response);
        if looks_unauthenticated(response.status, &response.final_url, &body) {
            self.clear_local()?;
            return Err(authentication_required());
        }
        if response.status >= 500 {
            return Err(status_error(response.status, "User Center is unavailable"));
        }
        if response.status != 200 {
            return Err(status_error(
                response.status,
                "User Center profile request failed",
            ));
        }
        parse_user_info(&body)
    }

    /// Best-effort remote logout followed by unconditional local session cleanup.
    ///
    /// # Errors
    ///
    /// Returns only a local persistence error; remote logout failures are intentionally ignored.
    pub async fn logout(&mut self) -> Result<()> {
        if let Ok(url) = self.url(SSO_LOGOUT_URL) {
            let _ = self.request(HttpRequest::get(url)).await;
        }
        self.clear_local()
    }

    async fn validate_status(&mut self) -> Result<AuthStatus> {
        let response = self
            .request(HttpRequest::get(self.url(UC_STATUS_URL)?))
            .await?;
        let body = body_text(&response);
        if response.status >= 500 {
            return Err(status_error(
                response.status,
                "authentication service is unavailable",
            ));
        }
        if looks_unauthenticated(response.status, &response.final_url, &body)
            || !body.trim_start().starts_with('{')
        {
            self.clear_local()?;
            return Err(authentication_required());
        }
        if response.status != 200 {
            self.clear_local()?;
            return Err(authentication_required());
        }
        let Ok(user) = parse_user_info(&body) else {
            self.clear_local()?;
            return Err(authentication_required());
        };
        let (authenticated_at, last_activity) = self.runtime.refresh_authentication()?;
        Ok(AuthStatus {
            user,
            authenticated_at,
            last_activity,
        })
    }

    async fn fetch_captcha(&mut self, id: String, execution: String) -> Result<LoginChallenge> {
        let url = format!("{}?captchaId={id}", self.url(SSO_CAPTCHA_URL)?);
        let response = self.request(HttpRequest::get(url)).await?;
        if response.status != 200 {
            return Err(status_error(
                response.status,
                "captcha image is unavailable",
            ));
        }
        let encoded = base64::engine::general_purpose::STANDARD.encode(response.body);
        Ok(LoginChallenge {
            id,
            execution,
            image_data_url: Some(format!("data:image/jpeg;base64,{encoded}")),
        })
    }

    async fn follow_login_response(&mut self, mut response: HttpResponse) -> Result<()> {
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
                let next = resolve_redirect(&response.final_url, location, self.mode())?;
                response = self.request(HttpRequest::get(next)).await?;
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
                let form = std::collections::BTreeMap::from([
                    ("execution".to_string(), execution),
                    ("_eventId".to_string(), "ignoreAndContinue".to_string()),
                ]);
                let target = strip_query(&response.final_url)?;
                response = self
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

    async fn activate_user_center(&mut self) -> Result<()> {
        let mut response = self
            .request(HttpRequest::get(self.url(UC_ACTIVATE_URL)?))
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
            let next = resolve_redirect(&response.final_url, location, self.mode())?;
            response = self.request(HttpRequest::get(next)).await?;
        }
        Err(upstream_changed("activation redirect limit exceeded"))
    }

    async fn request(&mut self, request: HttpRequest) -> Result<HttpResponse> {
        self.runtime.request(request).await
    }

    fn url(&self, direct: &str) -> Result<String> {
        self.runtime.url(direct)
    }

    fn clear_local(&mut self) -> Result<()> {
        self.login_state.clear();
        self.runtime.clear()
    }
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

fn authentication_required() -> UbaaError {
    UbaaError::new(
        ErrorCode::AuthenticationRequired,
        ErrorKind::Authentication,
        false,
        "authentication is required",
    )
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
        UbaaError::new(
            ErrorCode::UpstreamChanged,
            ErrorKind::Upstream,
            false,
            message,
        )
    }
}
