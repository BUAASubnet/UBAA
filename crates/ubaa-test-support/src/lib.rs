//! Sanitized fixtures and deterministic HTTP support shared by workspace crates.

use std::collections::VecDeque;
use std::fmt;
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
#[derive(Clone)]
pub struct ExpectedRequest {
    method: HttpMethod,
    url: String,
    response: HttpResponse,
}

impl fmt::Debug for ExpectedRequest {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("ExpectedRequest")
            .field("method", &self.method)
            .field("url", &"[REDACTED]")
            .field("response_status", &self.response.status)
            .finish()
    }
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
#[derive(Clone)]
pub struct MockTransport {
    state: Arc<MockState>,
}

struct MockState {
    expected: Mutex<VecDeque<ExpectedRequest>>,
    requests: Mutex<Vec<HttpRequest>>,
}

impl fmt::Debug for MockTransport {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let expected_count = self
            .state
            .expected
            .try_lock()
            .ok()
            .map(|expected| expected.len());
        let request_count = self
            .state
            .requests
            .try_lock()
            .ok()
            .map(|requests| requests.len());
        formatter
            .debug_struct("MockTransport")
            .field("expected_count", &expected_count)
            .field("request_count", &request_count)
            .finish()
    }
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
            return Err(mock_error("unexpected request method/url mismatch"));
        }
        Ok(expected.response)
    }
}

/// In-memory session store used by deterministic Core integration tests.
#[derive(Clone, Debug, Default)]
pub struct MemorySessionStore {
    state: Arc<Mutex<MemorySessionState>>,
}

#[derive(Debug, Default)]
struct MemorySessionState {
    snapshot: Option<ubaa_core::session::SessionSnapshot>,
    revision: u64,
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
            .map(|state| state.snapshot.clone())
            .map_err(|_| "memory store lock poisoned".into())
    }
}

impl ubaa_core::session::SessionStore for MemorySessionStore {
    fn load_versioned(&self) -> Result<ubaa_core::session::VersionedSession> {
        let state = self
            .state
            .lock()
            .map_err(|_| mock_error("memory store lock poisoned"))?;
        Ok(ubaa_core::session::VersionedSession {
            snapshot: state.snapshot.clone(),
            revision: state.revision,
        })
    }

    fn compare_exchange(
        &self,
        expected_revision: u64,
        replacement: Option<&ubaa_core::session::SessionSnapshot>,
    ) -> Result<ubaa_core::session::SessionMutation> {
        let mut state = self
            .state
            .lock()
            .map_err(|_| mock_error("memory store lock poisoned"))?;
        if state.revision != expected_revision {
            return Ok(ubaa_core::session::SessionMutation::Conflict);
        }
        state.revision = state
            .revision
            .checked_add(1)
            .ok_or_else(|| mock_error("memory session revision is exhausted"))?;
        state.snapshot = replacement.cloned();
        Ok(ubaa_core::session::SessionMutation::Applied {
            revision: state.revision,
        })
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
