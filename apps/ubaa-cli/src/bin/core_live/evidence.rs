//! Core-live 安全证据行及错误名称投影。

use std::time::Instant;

use ubaa_core::error::ErrorCode;

pub(crate) struct Evidence {
    route: &'static str,
    started: Instant,
    failed: bool,
}

impl Evidence {
    pub(crate) fn new(route: &'static str) -> Self {
        Self {
            route,
            started: Instant::now(),
            failed: false,
        }
    }

    pub(crate) const fn failed(&self) -> bool {
        self.failed
    }

    pub(crate) fn pass(&self, feature: &str, operation: &str, count: Option<usize>) {
        self.pass_with_fields(feature, operation, count, &[]);
    }

    pub(crate) fn pass_with_fields(
        &self,
        feature: &str,
        operation: &str,
        count: Option<usize>,
        extra_fields: &[(&str, String)],
    ) {
        emit(
            self.route,
            feature,
            operation,
            "PASS",
            None,
            count,
            None,
            self.started.elapsed().as_millis(),
            extra_fields,
        );
    }

    pub(crate) fn fail(&mut self, feature: &str, operation: &str, code: ErrorCode) {
        self.failed = true;
        emit(
            self.route,
            feature,
            operation,
            "FAIL",
            Some(code),
            None,
            None,
            self.started.elapsed().as_millis(),
            &[],
        );
    }

    pub(crate) fn blocked(&mut self, feature: &str, operation: &str, reason: &str) {
        self.failed = true;
        emit(
            self.route,
            feature,
            operation,
            "BLOCKED",
            None,
            None,
            Some(reason),
            self.started.elapsed().as_millis(),
            &[],
        );
    }

    pub(crate) fn not_applicable(&self, feature: &str, operation: &str, reason: &str) {
        emit(
            self.route,
            feature,
            operation,
            "NOT_APPLICABLE",
            None,
            None,
            Some(reason),
            self.started.elapsed().as_millis(),
            &[],
        );
    }
}

#[allow(clippy::too_many_arguments)]
fn emit(
    route: &str,
    feature: &str,
    operation: &str,
    status: &str,
    code: Option<ErrorCode>,
    count: Option<usize>,
    reason: Option<&str>,
    elapsed_ms: u128,
    extra_fields: &[(&str, String)],
) {
    let mut fields = vec![
        format!("route={route}"),
        format!("feature={feature}"),
        format!("stage={feature}"),
        format!("operation={operation}"),
        format!("status={status}"),
        format!("elapsed_ms={elapsed_ms}"),
    ];
    if let Some(code) = code {
        fields.push(format!("error={}", error_code(code)));
    }
    if let Some(count) = count {
        fields.push(format!("count={count}"));
    }
    if let Some(reason) = reason {
        fields.push(format!("reason={reason}"));
    }
    for (key, value) in extra_fields {
        fields.push(format!("{key}={value}"));
    }
    println!("{}", fields.join(" "));
}

pub(crate) fn error_code(code: ErrorCode) -> &'static str {
    match code {
        ErrorCode::InvalidInput => "invalid_input",
        ErrorCode::AuthenticationRequired => "authentication_required",
        ErrorCode::InvalidCredentials => "invalid_credentials",
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
