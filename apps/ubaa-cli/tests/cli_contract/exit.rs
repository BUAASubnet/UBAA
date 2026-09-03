use std::io::{self, Write};

use ubaa_cli::{CliFeature, render_startup_error};
use ubaa_core::error::{ErrorCode, ErrorKind, UbaaError};

use crate::common::assert_cli_schema;

const SAFE_MESSAGE: &str = "fixture-safe-error";

#[derive(Clone, Copy)]
struct ExitCase {
    error_code: ErrorCode,
    error_kind: ErrorKind,
    wire_code: &'static str,
    wire_kind: &'static str,
    exit: i32,
}

const CASES: [ExitCase; 11] = [
    ExitCase {
        error_code: ErrorCode::InvalidInput,
        error_kind: ErrorKind::Input,
        wire_code: "invalid_input",
        wire_kind: "input",
        exit: 2,
    },
    ExitCase {
        error_code: ErrorCode::AuthenticationRequired,
        error_kind: ErrorKind::Authentication,
        wire_code: "authentication_required",
        wire_kind: "authentication",
        exit: 3,
    },
    ExitCase {
        error_code: ErrorCode::InvalidCredentials,
        error_kind: ErrorKind::Authentication,
        wire_code: "invalid_credentials",
        wire_kind: "authentication",
        exit: 3,
    },
    ExitCase {
        error_code: ErrorCode::PasswordRiskConfirmationFailed,
        error_kind: ErrorKind::Authentication,
        wire_code: "password_risk_confirmation_failed",
        wire_kind: "authentication",
        exit: 3,
    },
    ExitCase {
        error_code: ErrorCode::PermissionDenied,
        error_kind: ErrorKind::Authentication,
        wire_code: "permission_denied",
        wire_kind: "authentication",
        exit: 3,
    },
    ExitCase {
        error_code: ErrorCode::NetworkError,
        error_kind: ErrorKind::Network,
        wire_code: "network_error",
        wire_kind: "network",
        exit: 5,
    },
    ExitCase {
        error_code: ErrorCode::Timeout,
        error_kind: ErrorKind::Network,
        wire_code: "timeout",
        wire_kind: "network",
        exit: 5,
    },
    ExitCase {
        error_code: ErrorCode::UpstreamUnavailable,
        error_kind: ErrorKind::Upstream,
        wire_code: "upstream_unavailable",
        wire_kind: "upstream",
        exit: 5,
    },
    ExitCase {
        error_code: ErrorCode::UpstreamChanged,
        error_kind: ErrorKind::Upstream,
        wire_code: "upstream_changed",
        wire_kind: "upstream",
        exit: 6,
    },
    ExitCase {
        error_code: ErrorCode::ParseError,
        error_kind: ErrorKind::Parse,
        wire_code: "parse_error",
        wire_kind: "parse",
        exit: 6,
    },
    ExitCase {
        error_code: ErrorCode::InternalError,
        error_kind: ErrorKind::Internal,
        wire_code: "internal_error",
        wire_kind: "internal",
        exit: 7,
    },
];

struct FailingWriter;

impl Write for FailingWriter {
    fn write(&mut self, _buffer: &[u8]) -> io::Result<usize> {
        Err(io::Error::other("fixture writer failure"))
    }

    fn flush(&mut self) -> io::Result<()> {
        Err(io::Error::other("fixture writer failure"))
    }
}

fn fixture_error(case: ExitCase) -> UbaaError {
    UbaaError::new(case.error_code, case.error_kind, false, SAFE_MESSAGE)
}

fn assert_json_and_human_streams(case: ExitCase) {
    let mut json_stdout = Vec::new();
    let mut json_stderr = Vec::new();
    let json_exit = render_startup_error(
        true,
        CliFeature::Cli,
        fixture_error(case),
        &mut json_stdout,
        &mut json_stderr,
    );

    assert_eq!(json_exit, case.exit);
    assert!(json_stderr.is_empty());
    let json_text = std::str::from_utf8(&json_stdout).unwrap();
    assert_eq!(json_text.lines().count(), 1);
    let mut envelopes =
        serde_json::Deserializer::from_slice(&json_stdout).into_iter::<serde_json::Value>();
    let envelope = envelopes.next().expect("missing JSON envelope").unwrap();
    assert!(
        envelopes.next().is_none(),
        "stdout contains multiple JSON values"
    );
    assert_cli_schema(&envelope);
    assert_eq!(envelope["schemaVersion"], 2);
    assert_eq!(envelope["ok"], false);
    assert!(envelope.get("data").is_none());
    assert_eq!(envelope["error"]["code"], case.wire_code);
    assert_eq!(envelope["error"]["kind"], case.wire_kind);
    assert_eq!(envelope["error"]["message"], SAFE_MESSAGE);
    assert_eq!(envelope["error"]["retryable"], false);
    assert_eq!(envelope["meta"], serde_json::json!({"feature": "cli"}));
    assert!(envelope["meta"].get("resolvedRoute").is_none());

    let mut human_stdout = Vec::new();
    let mut human_stderr = Vec::new();
    let human_exit = render_startup_error(
        false,
        CliFeature::Cli,
        fixture_error(case),
        &mut human_stdout,
        &mut human_stderr,
    );

    assert_eq!(human_exit, case.exit);
    assert!(human_stdout.is_empty());
    assert_eq!(
        std::str::from_utf8(&human_stderr).unwrap(),
        "错误：fixture-safe-error\n"
    );
}

fn assert_writer_failures_return_internal_exit() {
    let case = CASES[0];
    let mut discarded_stderr = Vec::new();
    assert_eq!(
        render_startup_error(
            true,
            CliFeature::Cli,
            fixture_error(case),
            &mut FailingWriter,
            &mut discarded_stderr,
        ),
        7
    );
    assert!(discarded_stderr.is_empty());

    let mut discarded_stdout = Vec::new();
    assert_eq!(
        render_startup_error(
            false,
            CliFeature::Cli,
            fixture_error(case),
            &mut discarded_stdout,
            &mut FailingWriter,
        ),
        7
    );
    assert!(discarded_stdout.is_empty());
}

#[test]
fn error_fixture_uses_stable_code_and_exit_mapping() {
    for case in CASES {
        assert_json_and_human_streams(case);
    }
    assert_writer_failures_return_internal_exit();
}
