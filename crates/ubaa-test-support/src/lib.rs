//! 工作区各 crate 共享的脱敏夹具与确定性 HTTP 支持。

use std::collections::VecDeque;
use std::fmt;
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use ubaa_core::error::{ErrorCode, ErrorKind, Result, UbaaError};
use ubaa_core::ports::{HttpMethod, HttpRequest, HttpResponse, HttpTransport};

/// 返回一个已知的编译期认证夹具。
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

/// 返回一个已知的编译期脱敏只读业务夹具。
#[must_use]
pub fn readonly_fixture(name: &str) -> Option<&'static str> {
    match name {
        "schedule-terms.json" => Some(include_str!(
            "../../../fixtures/readonly/schedule-terms.json"
        )),
        "schedule-weeks.json" => Some(include_str!(
            "../../../fixtures/readonly/schedule-weeks.json"
        )),
        "schedule-week.json" => Some(include_str!(
            "../../../fixtures/readonly/schedule-week.json"
        )),
        "schedule-today.json" => Some(include_str!(
            "../../../fixtures/readonly/schedule-today.json"
        )),
        "exam.json" => Some(include_str!("../../../fixtures/readonly/exam.json")),
        "grades-page.html" => Some(include_str!("../../../fixtures/readonly/grades-page.html")),
        "grades.json" => Some(include_str!("../../../fixtures/readonly/grades.json")),
        "classroom.json" => Some(include_str!("../../../fixtures/readonly/classroom.json")),
        "spoc-page.json" => Some(include_str!("../../../fixtures/readonly/spoc-page.json")),
        "spoc-detail.json" => Some(include_str!("../../../fixtures/readonly/spoc-detail.json")),
        "judge-courses.html" => Some(include_str!(
            "../../../fixtures/readonly/judge-courses.html"
        )),
        "judge-assignments.html" => Some(include_str!(
            "../../../fixtures/readonly/judge-assignments.html"
        )),
        "judge-detail.html" => Some(include_str!("../../../fixtures/readonly/judge-detail.html")),
        "cgyy-sites.json" => Some(include_str!("../../../fixtures/readonly/cgyy-sites.json")),
        "cgyy-day.json" => Some(include_str!("../../../fixtures/readonly/cgyy-day.json")),
        "cgyy-orders.json" => Some(include_str!("../../../fixtures/readonly/cgyy-orders.json")),
        _ => None,
    }
}

/// 拒绝常见凭据/请求头标记及疑似较长个人数字标识。
///
/// # Errors
///
/// 当夹具包含禁止标记或疑似个人标识时返回提示信息。
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
            return Err(format!("fixture 包含禁止标记: {marker}"));
        }
    }

    if fixture
        .split(|character: char| !character.is_ascii_digit())
        .any(|digits| digits.len() >= 8)
    {
        return Err("fixture 包含疑似个人数字标识".into());
    }
    Ok(())
}

/// 一条期望请求及其确定性响应。
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
    /// 构造脚本化请求期望。
    pub fn new(method: HttpMethod, url: impl Into<String>, response: HttpResponse) -> Self {
        Self {
            method,
            url: url.into(),
            response,
        }
    }
}

/// 按先进先出顺序校验方法和地址且不记录请求体的传输实现。
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
    /// 根据脚本化期望构造传输实现。
    pub fn new(expectations: impl IntoIterator<Item = ExpectedRequest>) -> Self {
        Self {
            state: Arc::new(MockState {
                expected: Mutex::new(expectations.into_iter().collect()),
                requests: Mutex::new(Vec::new()),
            }),
        }
    }

    /// 验证协议已消费脚本中的全部请求。
    ///
    /// # Errors
    ///
    /// 当模拟传输中毒或仍有未消费的脚本请求时返回提示信息。
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

    /// 返回请求副本供断言使用；调用方不得打印请求体。
    ///
    /// # Errors
    ///
    /// 当模拟锁中毒时返回提示信息。
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

/// 确定性 Core 集成测试使用的内存会话存储。
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
    /// 构造空存储。
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// 返回副本供断言使用。
    ///
    /// # Errors
    ///
    /// 当存储锁中毒时返回提示信息。
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
