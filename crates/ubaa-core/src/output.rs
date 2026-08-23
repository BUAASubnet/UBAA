//! Host-neutral JSON envelopes used by the CLI contract.

use std::fmt;

use serde::Serialize;

use crate::connection::{NetworkState, RouteResolution};
use crate::domain::{
    ConnectionMode, LoginOutcome, LoginReadiness, RouteLoginChallenge, RouteLoginState,
    RoutePolicy, SafeError,
};
use crate::error::{ErrorCode, ErrorKind, UbaaError};

/// The only supported CLI JSON schema version.
pub const CLI_JSON_SCHEMA_VERSION: u32 = 2;

/// Closed feature names used by CLI JSON metadata.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum CliFeature {
    /// Argument parsing and process startup.
    Cli,
    /// Authentication, status, and logout.
    Auth,
    /// User profile lookup.
    User,
    /// Schedule and teaching-week queries.
    Schedule,
    /// Exam arrangement queries.
    Exam,
    /// Grade queries.
    Grades,
    /// Empty-classroom queries.
    Classroom,
    /// SPOC assignment queries.
    Spoc,
    /// Judge assignment queries.
    Judge,
}

impl CliFeature {
    /// Return the stable JSON spelling.
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Cli => "cli",
            Self::Auth => "auth",
            Self::User => "user",
            Self::Schedule => "schedule",
            Self::Exam => "exam",
            Self::Grades => "grades",
            Self::Classroom => "classroom",
            Self::Spoc => "spoc",
            Self::Judge => "judge",
        }
    }
}

/// Complete route metadata emitted after Core resolved a route.
#[derive(Clone, Copy, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ResolvedRoutedJsonMeta {
    route_policy: RoutePolicy,
    network_state: NetworkState,
    initial_route: ConnectionMode,
    resolved_route: ConnectionMode,
    used_fallback: bool,
    feature: CliFeature,
}

impl ResolvedRoutedJsonMeta {
    /// Project a Core route decision into stable CLI metadata.
    #[must_use]
    pub const fn from_resolution(feature: CliFeature, resolution: RouteResolution) -> Self {
        Self {
            route_policy: resolution.policy,
            network_state: resolution.diagnostic.network,
            initial_route: resolution.diagnostic.initial_route,
            resolved_route: resolution.mode,
            used_fallback: resolution.diagnostic.used_fallback,
            feature,
        }
    }

    /// Build metadata for an explicit diagnostic route that did not run a probe.
    #[must_use]
    pub const fn explicit(feature: CliFeature, mode: ConnectionMode) -> Self {
        Self {
            route_policy: match mode {
                ConnectionMode::Direct => RoutePolicy::Direct,
                ConnectionMode::WebVpn => RoutePolicy::WebVpn,
            },
            network_state: NetworkState::Unknown,
            initial_route: mode,
            resolved_route: mode,
            used_fallback: false,
            feature,
        }
    }
}

/// Minimal metadata for a failure that happened before route resolution.
#[derive(Clone, Copy, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UnresolvedRoutedJsonMeta {
    feature: CliFeature,
}

impl UnresolvedRoutedJsonMeta {
    /// Identify the operation without inventing route diagnostics.
    #[must_use]
    pub const fn new(feature: CliFeature) -> Self {
        Self { feature }
    }
}

#[derive(Clone, Copy, Debug, Serialize)]
#[serde(untagged)]
enum RoutedJsonMeta {
    Resolved(ResolvedRoutedJsonMeta),
    Unresolved(UnresolvedRoutedJsonMeta),
}

/// Public captcha projection that excludes upstream execution and image data.
#[derive(Clone, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
struct PublicCaptchaChallenge {
    route: ConnectionMode,
    challenge_id: String,
    image_available: bool,
}

impl fmt::Debug for PublicCaptchaChallenge {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("PublicCaptchaChallenge")
            .field("route", &self.route)
            .field("challenge_id", &"[REDACTED]")
            .field("image_available", &self.image_available)
            .finish()
    }
}

/// Safe CLI error payload with an optional route-scoped public captcha handle.
#[derive(Clone, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CliJsonError {
    code: String,
    kind: String,
    message: String,
    retryable: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    challenge: Option<PublicCaptchaChallenge>,
}

impl CliJsonError {
    /// Convert a Core error while discarding any raw upstream captcha state.
    #[must_use]
    pub fn from_core(error: UbaaError) -> Self {
        Self {
            code: error_code_name(error.code).to_owned(),
            kind: error_kind_name(error.kind).to_owned(),
            message: error.message,
            retryable: error.retryable,
            challenge: None,
        }
    }

    /// Convert a validated aggregate error projection.
    ///
    /// # Errors
    ///
    /// Returns an internal error if the projection contains an unknown code or kind.
    pub fn try_from_safe(error: SafeError) -> Result<Self, UbaaError> {
        if !is_error_code(&error.code) || !is_error_kind(&error.kind) {
            return Err(output_invariant_error(
                "aggregate error projection has an unsupported code or kind",
            ));
        }
        Ok(Self {
            code: error.code,
            kind: error.kind,
            message: error.message,
            retryable: error.retryable,
            challenge: None,
        })
    }

    /// Attach only the already-sanitized, route-scoped captcha projection.
    #[must_use]
    pub fn with_route_challenge(mut self, challenge: &RouteLoginChallenge) -> Self {
        self.challenge = Some(PublicCaptchaChallenge {
            route: challenge.route,
            challenge_id: challenge.challenge_id.clone(),
            image_available: challenge.image_available,
        });
        self
    }
}

impl From<UbaaError> for CliJsonError {
    fn from(error: UbaaError) -> Self {
        Self::from_core(error)
    }
}

impl fmt::Debug for CliJsonError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("CliJsonError")
            .field("code", &self.code)
            .field("kind", &self.kind)
            .field("message", &"[REDACTED]")
            .field("retryable", &self.retryable)
            .field("challenge", &self.challenge)
            .finish()
    }
}

/// JSON envelope for one routed command.
#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RoutedJsonEnvelope<T> {
    schema_version: u32,
    ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    data: Option<T>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<CliJsonError>,
    meta: RoutedJsonMeta,
}

impl<T> RoutedJsonEnvelope<T> {
    /// Build a successful response after route resolution.
    #[must_use]
    pub const fn success(data: T, meta: ResolvedRoutedJsonMeta) -> Self {
        Self {
            schema_version: CLI_JSON_SCHEMA_VERSION,
            ok: true,
            data: Some(data),
            error: None,
            meta: RoutedJsonMeta::Resolved(meta),
        }
    }
}

impl RoutedJsonEnvelope<serde_json::Value> {
    /// Build a failed response after route resolution.
    #[must_use]
    pub fn resolved_failure(error: impl Into<CliJsonError>, meta: ResolvedRoutedJsonMeta) -> Self {
        Self {
            schema_version: CLI_JSON_SCHEMA_VERSION,
            ok: false,
            data: None,
            error: Some(error.into()),
            meta: RoutedJsonMeta::Resolved(meta),
        }
    }

    /// Build a failed response without inventing route metadata.
    #[must_use]
    pub fn unresolved_failure(
        error: impl Into<CliJsonError>,
        meta: UnresolvedRoutedJsonMeta,
    ) -> Self {
        Self {
            schema_version: CLI_JSON_SCHEMA_VERSION,
            ok: false,
            data: None,
            error: Some(error.into()),
            meta: RoutedJsonMeta::Unresolved(meta),
        }
    }
}

impl<T> fmt::Debug for RoutedJsonEnvelope<T> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("RoutedJsonEnvelope")
            .field("schema_version", &self.schema_version)
            .field("ok", &self.ok)
            .field("data_present", &self.data.is_some())
            .field("error_present", &self.error.is_some())
            .field("meta", &self.meta)
            .finish()
    }
}

/// Aggregate authentication metadata with a fixed Direct, `WebVPN` route pair.
#[derive(Clone, Copy, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AggregateJsonMeta {
    route_policy: RoutePolicy,
    resolved_routes: [ConnectionMode; 2],
    feature: CliFeature,
}

impl AggregateJsonMeta {
    /// Construct authentication metadata without accepting caller-provided routes.
    #[must_use]
    pub const fn auth(route_policy: RoutePolicy) -> Self {
        Self {
            route_policy,
            resolved_routes: [ConnectionMode::Direct, ConnectionMode::WebVpn],
            feature: CliFeature::Auth,
        }
    }
}

/// Aggregate JSON envelope whose state can only be created by contract constructors.
#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AggregateJsonEnvelope<T> {
    schema_version: u32,
    ok: bool,
    data: T,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<CliJsonError>,
    meta: AggregateJsonMeta,
}

impl AggregateJsonEnvelope<LoginOutcome> {
    /// Build a successful aggregate authentication response.
    ///
    /// # Errors
    ///
    /// Returns an internal error if the route pair is not Direct then `WebVPN`.
    pub fn auth_success(
        outcome: LoginOutcome,
        route_policy: RoutePolicy,
    ) -> Result<Self, UbaaError> {
        validate_auth_outcome(&outcome, true)?;
        Ok(Self {
            schema_version: CLI_JSON_SCHEMA_VERSION,
            ok: true,
            data: outcome,
            error: None,
            meta: AggregateJsonMeta::auth(route_policy),
        })
    }

    /// Build a failed aggregate authentication response.
    ///
    /// # Errors
    ///
    /// Returns an internal error if the route pair or safe error projection is invalid.
    pub fn auth_failure(
        outcome: LoginOutcome,
        error: SafeError,
        route_policy: RoutePolicy,
    ) -> Result<Self, UbaaError> {
        validate_auth_outcome(&outcome, false)?;
        let is_captcha = error.code == "captcha_required";
        let mut error = CliJsonError::try_from_safe(error)?;
        if is_captcha && let Some(challenge) = outcome.challenges.first() {
            error = error.with_route_challenge(challenge);
        }
        Ok(Self {
            schema_version: CLI_JSON_SCHEMA_VERSION,
            ok: false,
            data: outcome,
            error: Some(error),
            meta: AggregateJsonMeta::auth(route_policy),
        })
    }
}

impl<T> fmt::Debug for AggregateJsonEnvelope<T> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("AggregateJsonEnvelope")
            .field("schema_version", &self.schema_version)
            .field("ok", &self.ok)
            .field("data", &"[REDACTED]")
            .field("error_present", &self.error.is_some())
            .field("meta", &self.meta)
            .finish()
    }
}

/// Fixed route state emitted by aggregate logout.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
enum AggregateLogoutRouteState {
    LoggedOut,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
struct AggregateLogoutRoute {
    route: ConnectionMode,
    state: AggregateLogoutRouteState,
}

/// Successful aggregate logout data with both route slots named explicitly.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AggregateLogoutData {
    logged_out: bool,
    routes: [AggregateLogoutRoute; 2],
}

impl AggregateLogoutData {
    /// Construct the only valid aggregate logout result.
    #[must_use]
    pub const fn new() -> Self {
        Self {
            logged_out: true,
            routes: [
                AggregateLogoutRoute {
                    route: ConnectionMode::Direct,
                    state: AggregateLogoutRouteState::LoggedOut,
                },
                AggregateLogoutRoute {
                    route: ConnectionMode::WebVpn,
                    state: AggregateLogoutRouteState::LoggedOut,
                },
            ],
        }
    }
}

impl Default for AggregateLogoutData {
    fn default() -> Self {
        Self::new()
    }
}

impl AggregateJsonEnvelope<AggregateLogoutData> {
    /// Build a successful aggregate logout response for both session slots.
    #[must_use]
    pub const fn logout_success(route_policy: RoutePolicy) -> Self {
        Self {
            schema_version: CLI_JSON_SCHEMA_VERSION,
            ok: true,
            data: AggregateLogoutData::new(),
            error: None,
            meta: AggregateJsonMeta::auth(route_policy),
        }
    }
}

fn validate_auth_outcome(outcome: &LoginOutcome, success: bool) -> Result<(), UbaaError> {
    if outcome.routes[0].route != ConnectionMode::Direct
        || outcome.routes[1].route != ConnectionMode::WebVpn
    {
        return Err(output_invariant_error(
            "aggregate authentication routes must be Direct then WebVPN",
        ));
    }
    for route in &outcome.routes {
        if (route.state == RouteLoginState::Ready && route.error.is_some())
            || (route.state == RouteLoginState::Failed && route.error.is_none())
        {
            return Err(output_invariant_error(
                "aggregate authentication route state does not match its error",
            ));
        }
    }
    let ready_count = outcome
        .routes
        .iter()
        .filter(|route| route.state == RouteLoginState::Ready)
        .count();
    let expected_readiness = match ready_count {
        2 => LoginReadiness::AllReady,
        1 => LoginReadiness::Partial,
        _ => LoginReadiness::NoneReady,
    };
    if outcome.readiness != expected_readiness {
        return Err(output_invariant_error(
            "aggregate authentication readiness does not match route states",
        ));
    }
    let requires_failure = ready_count == 0
        || outcome
            .routes
            .iter()
            .any(|route| route.state == RouteLoginState::CaptchaRequired);
    if success == requires_failure {
        return Err(output_invariant_error(
            "aggregate authentication ok flag does not match route states",
        ));
    }
    Ok(())
}

fn output_invariant_error(message: &'static str) -> UbaaError {
    UbaaError::new(
        ErrorCode::InternalError,
        ErrorKind::Internal,
        false,
        message,
    )
}

const fn error_code_name(code: ErrorCode) -> &'static str {
    match code {
        ErrorCode::InvalidInput => "invalid_input",
        ErrorCode::AuthenticationRequired => "authentication_required",
        ErrorCode::InvalidCredentials => "invalid_credentials",
        ErrorCode::CaptchaRequired => "captcha_required",
        ErrorCode::PasswordRiskConfirmationFailed => "password_risk_confirmation_failed",
        ErrorCode::PermissionDenied => "permission_denied",
        ErrorCode::NetworkError => "network_error",
        ErrorCode::Timeout => "timeout",
        ErrorCode::UpstreamUnavailable => "upstream_unavailable",
        ErrorCode::UpstreamChanged => "upstream_changed",
        ErrorCode::ParseError => "parse_error",
        ErrorCode::InternalError => "internal_error",
    }
}

const fn error_kind_name(kind: ErrorKind) -> &'static str {
    match kind {
        ErrorKind::Input => "input",
        ErrorKind::Authentication => "authentication",
        ErrorKind::Network => "network",
        ErrorKind::Upstream => "upstream",
        ErrorKind::Parse => "parse",
        ErrorKind::Internal => "internal",
    }
}

fn is_error_code(code: &str) -> bool {
    matches!(
        code,
        "invalid_input"
            | "authentication_required"
            | "invalid_credentials"
            | "captcha_required"
            | "password_risk_confirmation_failed"
            | "permission_denied"
            | "network_error"
            | "timeout"
            | "upstream_unavailable"
            | "upstream_changed"
            | "parse_error"
            | "internal_error"
    )
}

fn is_error_kind(kind: &str) -> bool {
    matches!(
        kind,
        "input" | "authentication" | "network" | "upstream" | "parse" | "internal"
    )
}
