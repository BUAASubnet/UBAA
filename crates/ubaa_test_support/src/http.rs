use std::collections::VecDeque;
use std::fmt;
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use ubaa_core::facade::testing::{HttpMethod, HttpRequest, HttpResponse, HttpTransport};
use ubaa_core::facade::{ErrorCode, ErrorKind, Result, UbaaError};

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
    sso_checks: bool,
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
    /// 业务测试声明验票响应时同时加入标准取票步骤，实际请求仍按顺序严格匹配。
    /// # Panics
    /// 内置合成 SSO 地址无法转换时触发测试失败。
    pub fn with_sso_checks(expectations: impl IntoIterator<Item = ExpectedRequest>) -> Self {
        let mut steps = Vec::new();
        for expected in expectations {
            let direct =
                ubaa_core::facade::testing::from_webvpn_url(&expected.url).unwrap_or_default();
            if direct.starts_with("https://sso.buaa.edu.cn/serviceValidate?") {
                let login = "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fbyxt.buaa.edu.cn%2Fjwapp%2Fsys%2Fhomeapp%2Findex.do%3FcontextPath%3D%2Fjwapp";
                let login = if expected.url.starts_with("https://d.buaa.edu.cn/") {
                    ubaa_core::facade::testing::to_webvpn_url(login).unwrap()
                } else {
                    login.into()
                };
                let request = HttpRequest::get(&login);
                let response = ubaa_core::facade::testing::sso_fixture_ticket(&request)
                    .expect("固定合成取票请求");
                steps.push(ExpectedRequest::new(HttpMethod::Get, login, response));
            }
            steps.push(expected);
        }
        Self::build(steps, true)
    }

    /// 根据脚本化期望构造传输实现。
    pub fn new(expectations: impl IntoIterator<Item = ExpectedRequest>) -> Self {
        Self::build(expectations, false)
    }

    fn build(expectations: impl IntoIterator<Item = ExpectedRequest>, sso_checks: bool) -> Self {
        Self {
            state: Arc::new(MockState {
                sso_checks,
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
        if self.state.sso_checks
            && (request.url.contains("cas_login%3Dtrue") || request.url == "https://d.buaa.edu.cn/")
            && let Some(response) = ubaa_core::facade::testing::sso_fixture_ticket(&request)
        {
            self.state
                .requests
                .lock()
                .map_err(|_| mock_error("mock lock poisoned"))?
                .push(request);
            return Ok(response);
        }
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

pub(crate) fn mock_error(message: impl Into<String>) -> UbaaError {
    UbaaError::new(
        ErrorCode::InternalError,
        ErrorKind::Internal,
        false,
        message,
    )
}
