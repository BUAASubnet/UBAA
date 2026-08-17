//! Sanitized fixtures and deterministic HTTP support shared by workspace crates.

use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

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
#[derive(Clone, Debug)]
pub struct MockTransport {
    state: Arc<MockState>,
}

#[derive(Debug)]
struct MockState {
    expected: Mutex<VecDeque<ExpectedRequest>>,
    requests: Mutex<Vec<HttpRequest>>,
}

impl MockTransport {
    /// Construct a transport from scripted expectations.
    pub fn new(expectations: impl IntoIterator<Item = ExpectedRequest>) -> Self {
        Self {
            state: Arc::new(MockState {
                expected: Mutex::new(expectations.into_iter().collect()),
                requests: Mutex::new(Vec::new()),
            }),
        }
    }

    /// Verify that the protocol consumed every scripted request.
    ///
    /// # Errors
    ///
    /// Returns a message when the mock is poisoned or scripted requests remain.
    pub fn assert_exhausted(&self) -> std::result::Result<(), String> {
        let remaining = self
            .state
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

    /// Return a copy of requests for assertions; callers must not print bodies.
    ///
    /// # Errors
    ///
    /// Returns a message when the mock lock is poisoned.
    pub fn requests(&self) -> std::result::Result<Vec<HttpRequest>, String> {
        self.state
            .requests
            .lock()
            .map(|requests| requests.clone())
            .map_err(|_| "mock lock poisoned".into())
    }
}

#[async_trait]
impl HttpTransport for MockTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.state
            .requests
            .lock()
            .map_err(|_| mock_error("mock lock poisoned"))?
            .push(request.clone());
        let expected = self
            .state
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

/// In-memory session store used by deterministic Core integration tests.
#[derive(Clone, Debug, Default)]
pub struct MemorySessionStore {
    state: Arc<Mutex<Option<ubaa_core::session::SessionSnapshot>>>,
}

impl MemorySessionStore {
    /// Construct an empty store.
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Return a copy for assertions.
    ///
    /// # Errors
    ///
    /// Returns a message when the store lock is poisoned.
    pub fn snapshot(
        &self,
    ) -> std::result::Result<Option<ubaa_core::session::SessionSnapshot>, String> {
        self.state
            .lock()
            .map(|snapshot| snapshot.clone())
            .map_err(|_| "memory store lock poisoned".into())
    }
}

impl ubaa_core::session::SessionStore for MemorySessionStore {
    fn load(&self) -> Result<Option<ubaa_core::session::SessionSnapshot>> {
        self.snapshot().map_err(mock_error)
    }

    fn save(&self, snapshot: &ubaa_core::session::SessionSnapshot) -> Result<()> {
        self.state
            .lock()
            .map_err(|_| mock_error("memory store lock poisoned"))?
            .replace(snapshot.clone());
        Ok(())
    }

    fn clear(&self) -> Result<()> {
        self.state
            .lock()
            .map_err(|_| mock_error("memory store lock poisoned"))?
            .take();
        Ok(())
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
