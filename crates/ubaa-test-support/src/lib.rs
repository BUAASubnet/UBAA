//! Sanitized fixtures and deterministic HTTP support shared by workspace crates.

use std::collections::VecDeque;
use std::sync::Mutex;

use async_trait::async_trait;
use ubaa_core::error::{ErrorCode, ErrorKind, Result, UbaaError};
use ubaa_core::ports::{HttpMethod, HttpRequest, HttpResponse, HttpTransport};

/// Return one known, compile-time authentication fixture.
#[must_use]
pub fn auth_fixture(name: &str) -> Option<&'static str> {
    match name {
        "login-page.html" => Some(include_str!("../../../fixtures/auth/login-page.html")),
        "userinfo-success.json" => {
            Some(include_str!("../../../fixtures/auth/userinfo-success.json"))
        }
        _ => None,
    }
}

/// Reject common credential/header markers and plausible long numeric identifiers.
///
/// # Errors
///
/// Returns a message when the fixture contains a forbidden marker or plausible personal identifier.
pub fn assert_fixture_is_sanitized(fixture: &str) -> std::result::Result<(), String> {
    let lower = fixture.to_ascii_lowercase();
    for marker in [
        "set-cookie:",
        "cookie:",
        "authorization:",
        "ubaa_test_password",
        "-----begin private key-----",
    ] {
        if lower.contains(marker) {
            return Err(format!("fixture contains forbidden marker: {marker}"));
        }
    }

    if fixture
        .split(|character: char| !character.is_ascii_digit())
        .any(|digits| digits.len() >= 8)
    {
        return Err("fixture contains a plausible numeric personal identifier".into());
    }
    Ok(())
}

/// One expected request and its deterministic response.
#[derive(Clone, Debug)]
pub struct ExpectedRequest {
    method: HttpMethod,
    url: String,
    response: HttpResponse,
}

impl ExpectedRequest {
    /// Construct a scripted request expectation.
    pub fn new(method: HttpMethod, url: impl Into<String>, response: HttpResponse) -> Self {
        Self {
            method,
            url: url.into(),
            response,
        }
    }
}

/// FIFO transport that validates method and URL without logging request bodies.
#[derive(Debug)]
pub struct MockTransport {
    expected: Mutex<VecDeque<ExpectedRequest>>,
}

impl MockTransport {
    /// Construct a transport from scripted expectations.
    pub fn new(expectations: impl IntoIterator<Item = ExpectedRequest>) -> Self {
        Self {
            expected: Mutex::new(expectations.into_iter().collect()),
        }
    }

    /// Verify that the protocol consumed every scripted request.
    ///
    /// # Errors
    ///
    /// Returns a message when the mock is poisoned or scripted requests remain.
    pub fn assert_exhausted(&self) -> std::result::Result<(), String> {
        let remaining = self
            .expected
            .lock()
            .map_err(|_| "mock lock poisoned")?
            .len();
        if remaining == 0 {
            Ok(())
        } else {
            Err(format!("{remaining} scripted requests remain"))
        }
    }
}

#[async_trait]
impl HttpTransport for MockTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let expected = self
            .expected
            .lock()
            .map_err(|_| mock_error("mock lock poisoned"))?
            .pop_front()
            .ok_or_else(|| mock_error("unexpected request: no scripted response remains"))?;

        if request.method != expected.method || request.url != expected.url {
            return Err(mock_error(format!(
                "unexpected request method/url: {:?} {}",
                request.method, request.url
            )));
        }
        Ok(expected.response)
    }
}

fn mock_error(message: impl Into<String>) -> UbaaError {
    UbaaError::new(
        ErrorCode::InternalError,
        ErrorKind::Internal,
        false,
        message,
    )
}
