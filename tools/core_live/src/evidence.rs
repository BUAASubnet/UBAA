//! Core-live 安全证据行及错误名称投影。

use std::time::Instant;

use ubaa_core::facade::ErrorCode;

pub(crate) struct Evidence {
    route: &'static str,
    started: Instant,
    failed: bool,
    #[cfg(test)]
    lines: Option<std::cell::RefCell<Vec<String>>>,
}

impl Evidence {
    pub(crate) fn new(route: &'static str) -> Self {
        Self {
            route,
            started: Instant::now(),
            failed: false,
            #[cfg(test)]
            lines: None,
        }
    }

    #[cfg(test)]
    pub(crate) fn capturing(route: &'static str) -> Self {
        Self {
            lines: Some(std::cell::RefCell::default()),
            ..Self::new(route)
        }
    }

    #[cfg(test)]
    pub(crate) fn captured(self) -> Vec<String> {
        self.lines.expect("已启用证据捕获").into_inner()
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
            self,
            feature,
            operation,
            "PASS",
            None,
            count,
            None,
            extra_fields,
        );
    }

    pub(crate) fn fail(&mut self, feature: &str, operation: &str, code: ErrorCode) {
        self.fail_code(feature, operation, error_code(code));
    }

    pub(crate) fn fail_code(&mut self, feature: &str, operation: &str, code: &str) {
        self.fail_with_fields(feature, operation, code, None, &[]);
    }

    pub(crate) fn fail_with_fields(
        &mut self,
        feature: &str,
        operation: &str,
        code: &str,
        count: Option<usize>,
        fields: &[(&str, String)],
    ) {
        self.failed = true;
        emit(
            self,
            feature,
            operation,
            "FAIL",
            Some(code),
            count,
            None,
            fields,
        );
    }

    pub(crate) fn blocked(&mut self, feature: &str, operation: &str, reason: &str) {
        self.failed = true;
        emit(
            self,
            feature,
            operation,
            "BLOCKED",
            None,
            None,
            Some(reason),
            &[],
        );
    }

    pub(crate) fn not_applicable(&self, feature: &str, operation: &str, reason: &str) {
        emit(
            self,
            feature,
            operation,
            "NOT_APPLICABLE",
            None,
            None,
            Some(reason),
            &[],
        );
    }
}

#[allow(clippy::too_many_arguments)]
fn emit(
    evidence: &Evidence,
    feature: &str,
    operation: &str,
    status: &str,
    code: Option<&str>,
    count: Option<usize>,
    reason: Option<&str>,
    extra_fields: &[(&str, String)],
) {
    let route = evidence.route;
    let elapsed_ms = evidence.started.elapsed().as_millis();
    let mut fields = vec![
        format!("route={route}"),
        format!("feature={feature}"),
        format!("stage={feature}"),
        format!("operation={operation}"),
        format!("status={status}"),
        format!("elapsed_ms={elapsed_ms}"),
    ];
    if let Some(code) = code {
        fields.push(format!("error={code}"));
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
    let line = fields.join(" ");
    #[cfg(test)]
    if let Some(lines) = &evidence.lines {
        lines.borrow_mut().push(line);
        return;
    }
    println!("{line}");
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
        ErrorCode::BusinessUnavailable => "business_unavailable",
        ErrorCode::BusinessRejected => "business_rejected",
        ErrorCode::OutcomeUnknown => "outcome_unknown",
        ErrorCode::UpdateRequired => "update_required",
        ErrorCode::UpstreamChanged => "upstream_changed",
        ErrorCode::ParseError => "parse_error",
        ErrorCode::InternalError => "internal_error",
        ErrorCode::Unsupported => "unsupported",
    }
}
