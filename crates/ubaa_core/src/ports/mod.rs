//! 协议和会话代码使用的可注入宿主端口。

mod reqwest_transport;

pub use reqwest_transport::ReqwestTransport;

use std::collections::BTreeMap;
use std::fmt;

use async_trait::async_trait;
use serde::{Deserialize, Serialize};

use crate::error::Result;

/// 认证协议支持的 HTTP 方法。
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "UPPERCASE")]
pub enum HttpMethod {
    /// 读取上游资源。
    Get,
    /// 提交上游表单。
    Post,
}

/// 不自动跟随重定向、可审计的传输请求。
#[derive(Clone, Eq, PartialEq)]
pub struct HttpRequest {
    /// 请求方法。
    pub method: HttpMethod,
    /// 完整解析后的请求地址。
    pub url: String,
    /// 请求头。敏感请求头绝不能写入日志。
    pub headers: BTreeMap<String, String>,
    /// 可选请求体。
    pub body: Vec<u8>,
}

impl fmt::Debug for HttpRequest {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("HttpRequest")
            .field("method", &self.method)
            .field("url", &"[REDACTED]")
            .field("headers", &redacted_header_names(&self.headers))
            .field("body_len", &self.body.len())
            .finish()
    }
}

impl HttpRequest {
    /// 构造 GET 请求。
    pub fn get(url: impl Into<String>) -> Self {
        Self {
            method: HttpMethod::Get,
            url: url.into(),
            headers: BTreeMap::new(),
            body: Vec::new(),
        }
    }

    /// 构造 POST 请求。
    pub fn post(url: impl Into<String>, body: Vec<u8>) -> Self {
        Self {
            method: HttpMethod::Post,
            url: url.into(),
            headers: BTreeMap::new(),
            body,
        }
    }

    /// 添加或替换一个请求头。
    #[must_use]
    pub fn with_header(mut self, name: impl Into<String>, value: impl Into<String>) -> Self {
        self.headers.insert(name.into(), value.into());
        self
    }
}

/// 重定向和 Cookie 处理前返回的原始响应。
#[derive(Clone, Eq, PartialEq)]
pub struct HttpResponse {
    /// HTTP 状态码。
    pub status: u16,
    /// 产生该响应的请求地址。
    pub final_url: String,
    /// 响应头，保留 `Set-Cookie` 等多值字段。
    pub headers: BTreeMap<String, Vec<String>>,
    /// 未解释的响应体。
    pub body: Vec<u8>,
}

impl fmt::Debug for HttpResponse {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("HttpResponse")
            .field("status", &self.status)
            .field("final_url", &"[REDACTED]")
            .field("headers", &redacted_header_names_vec(&self.headers))
            .field("body_len", &self.body.len())
            .finish()
    }
}

impl HttpResponse {
    /// 构造不含响应头的响应。
    #[cfg(any(test, feature = "test-contract"))]
    pub fn new(status: u16, final_url: impl Into<String>, body: Vec<u8>) -> Self {
        Self {
            status,
            final_url: final_url.into(),
            headers: BTreeMap::new(),
            body,
        }
    }
}

/// 可替换的 HTTP 传输。重定向和 Cookie 仍由 Core 负责。
#[async_trait]
pub trait HttpTransport: Send + Sync {
    /// 恰好执行一次请求并返回原始响应。
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse>;
}

fn redacted_header_names(headers: &BTreeMap<String, String>) -> Vec<&str> {
    headers.keys().map(String::as_str).collect()
}

fn redacted_header_names_vec(headers: &BTreeMap<String, Vec<String>>) -> Vec<&str> {
    headers.keys().map(String::as_str).collect()
}
