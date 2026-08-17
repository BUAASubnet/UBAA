use std::io::Cursor;

use async_trait::async_trait;
use clap::Parser;
use ubaa_cli::{Cli, CliBackend, run_with_backend};
use ubaa_core::domain::{AuthStatus, ConnectionMode, LoginChallenge, LoginInput, UserProfile};
use ubaa_core::error::{ErrorCode, ErrorKind, Result, UbaaError};

#[derive(Default)]
struct FakeBackend {
    challenge: Option<LoginChallenge>,
    login_calls: usize,
}

#[async_trait]
impl CliBackend for FakeBackend {
    fn mode(&self) -> ConnectionMode {
        ConnectionMode::Direct
    }

    async fn prepare_login(&mut self) -> Result<Option<LoginChallenge>> {
        Ok(self.challenge.clone())
    }

    async fn login(&mut self, _input: LoginInput) -> Result<UserProfile> {
        self.login_calls += 1;
        Ok(profile())
    }

    async fn auth_status(&mut self) -> Result<AuthStatus> {
        Ok(AuthStatus {
            user: profile(),
            authenticated_at: 100,
            last_activity: 101,
        })
    }

    async fn get_user_info(&mut self) -> Result<UserProfile> {
        Ok(profile())
    }

    async fn logout(&mut self) -> Result<()> {
        Ok(())
    }
}

fn profile() -> UserProfile {
    UserProfile {
        name: Some("Fixture User".into()),
        school_id: Some("TEST-0001".into()),
        username: Some("fixture-user".into()),
        phone: Some("PHONE-FIXTURE-VALUE".into()),
        id_card_number: Some("TEST-ID-0001".into()),
        ..UserProfile::default()
    }
}

#[tokio::test]
async fn json_login_outputs_one_parseable_redacted_envelope() {
    let cli = Cli::try_parse_from([
        "ubaa",
        "--json",
        "--config-dir",
        "/tmp/ubaa-fixture",
        "auth",
        "login",
        "--mode",
        "direct",
        "--username",
        "fixture-user",
        "--password-stdin",
    ])
    .unwrap();
    let mut backend = FakeBackend::default();
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let code = run_with_backend(
        cli,
        &mut backend,
        &mut Cursor::new(b"fixture-password\n"),
        &mut stdout,
        &mut stderr,
    )
    .await;

    assert_eq!(code, 0);
    let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();
    assert_eq!(value["ok"], true);
    assert_eq!(value["data"]["schoolId"], "TEST-0001");
    assert_ne!(value["data"]["phone"], "PHONE-FIXTURE-VALUE");
    assert_ne!(value["data"]["idCardNumber"], "TEST-ID-0001");
    assert!(!String::from_utf8_lossy(&stdout).contains("fixture-password"));
    assert!(stderr.is_empty());
}

#[tokio::test]
async fn json_captcha_returns_exit_four_without_image_or_login_submission() {
    let cli = Cli::try_parse_from([
        "ubaa",
        "--json",
        "auth",
        "login",
        "--mode",
        "direct",
        "--username",
        "fixture-user",
        "--password-stdin",
    ])
    .unwrap();
    let mut backend = FakeBackend {
        challenge: Some(LoginChallenge {
            id: "captcha-fixture".into(),
            execution: "e-cap".into(),
            image_data_url: Some("data:image/jpeg;base64,DO-NOT-PRINT".into()),
        }),
        login_calls: 0,
    };
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let code = run_with_backend(
        cli,
        &mut backend,
        &mut Cursor::new(b"fixture-password\n"),
        &mut stdout,
        &mut stderr,
    )
    .await;

    assert_eq!(code, 4);
    let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();
    assert_eq!(value["error"]["code"], "captcha_required");
    assert!(value["error"]["challenge"].get("imageDataUrl").is_none());
    assert_eq!(backend.login_calls, 0);
}

#[tokio::test]
async fn human_captcha_stays_in_process_until_non_empty_input() {
    let cli = Cli::try_parse_from([
        "ubaa",
        "auth",
        "login",
        "--mode",
        "direct",
        "--username",
        "fixture-user",
        "--password-stdin",
    ])
    .unwrap();
    let mut backend = FakeBackend {
        challenge: Some(LoginChallenge {
            id: "captcha-fixture".into(),
            execution: "e-cap".into(),
            image_data_url: Some("data:image/jpeg;base64,RklYVFVSRS1JTUFHRQ==".into()),
        }),
        login_calls: 0,
    };
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let code = run_with_backend(
        cli,
        &mut backend,
        &mut Cursor::new(b"fixture-password\n\ncaptcha-fixture-answer\n"),
        &mut stdout,
        &mut stderr,
    )
    .await;

    assert_eq!(code, 0);
    assert_eq!(backend.login_calls, 1);
    assert!(String::from_utf8(stderr).unwrap().contains("Captcha: "));
}

#[tokio::test]
async fn human_user_output_masks_phone_and_identity_number() {
    let cli = Cli::try_parse_from(["ubaa", "user", "show"]).unwrap();
    let mut backend = FakeBackend::default();
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let code = run_with_backend(
        cli,
        &mut backend,
        &mut Cursor::new(Vec::<u8>::new()),
        &mut stdout,
        &mut stderr,
    )
    .await;

    let output = String::from_utf8(stdout).unwrap();
    assert_eq!(code, 0);
    assert!(output.contains("Fixture User"));
    assert!(output.contains("TEST-0001"));
    assert!(!output.contains("PHONE-FIXTURE-VALUE"));
    assert!(!output.contains("TEST-ID-0001"));
}

#[test]
fn clap_has_no_plaintext_password_option() {
    let error = Cli::try_parse_from([
        "ubaa",
        "auth",
        "login",
        "--mode",
        "direct",
        "--password",
        "forbidden",
    ])
    .unwrap_err();
    assert!(
        error
            .to_string()
            .contains("unexpected argument '--password'")
    );
}

#[test]
fn login_can_reuse_a_saved_connection_mode() {
    let cli = Cli::try_parse_from([
        "ubaa",
        "auth",
        "login",
        "--username",
        "fixture-user",
        "--password-stdin",
    ])
    .unwrap();
    assert_eq!(
        cli.resolve_mode(Some(ConnectionMode::WebVpn)).unwrap(),
        ConnectionMode::WebVpn
    );

    let error = cli.resolve_mode(None).unwrap_err();
    assert_eq!(error.code, ErrorCode::InvalidInput);
}

#[test]
fn schema_accepts_success_and_captcha_failure_envelopes() {
    let schema: serde_json::Value =
        serde_json::from_str(include_str!("../../../docs/contracts/cli-json.schema.json")).unwrap();
    let validator = jsonschema::validator_for(&schema).unwrap();
    let success = serde_json::json!({
        "schemaVersion": 1,
        "ok": true,
        "data": {"schoolId": "TEST-0001"},
        "meta": {"connectionMode": "direct"}
    });
    let failure = serde_json::json!({
        "schemaVersion": 1,
        "ok": false,
        "error": {
            "code": "captcha_required",
            "kind": "authentication",
            "message": "captcha required",
            "retryable": true,
            "challenge": {"id": "fixture", "execution": "e-cap"}
        },
        "meta": {"connectionMode": "webvpn"}
    });
    assert!(validator.is_valid(&success));
    assert!(validator.is_valid(&failure));
}

#[test]
fn error_fixture_uses_stable_code_and_exit_mapping() {
    let error = UbaaError::new(
        ErrorCode::AuthenticationRequired,
        ErrorKind::Authentication,
        false,
        "fixture",
    );
    assert_eq!(error.code.exit_code() as i32, 3);
}
