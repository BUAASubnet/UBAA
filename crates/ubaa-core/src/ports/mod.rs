//! Injectable host ports used by protocol and session code.

use std::collections::BTreeMap;
use std::fmt;

use async_trait::async_trait;
use serde::{Deserialize, Serialize};

use crate::error::Result;

/// HTTP method supported by the authentication protocol.
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "UPPERCASE")]
pub enum HttpMethod {
    /// Read an upstream resource.
    Get,
    /// Submit an upstream form.
    Post,
}

/// Auditable transport request with no automatic redirects.
#[derive(Clone, Eq, PartialEq)]
pub struct HttpRequest {
    /// Request method.
    pub method: HttpMethod,
    /// Fully resolved request URL.
    pub url: String,
    /// Request headers. Sensitive headers must never be logged.
    pub headers: BTreeMap<String, String>,
    /// Optional request body.
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
    /// Construct a GET request.
    pub fn get(url: impl Into<String>) -> Self {
        Self {
            method: HttpMethod::Get,
            url: url.into(),
            headers: BTreeMap::new(),
            body: Vec::new(),
        }
    }

    /// Construct a POST request.
    pub fn post(url: impl Into<String>, body: Vec<u8>) -> Self {
        Self {
            method: HttpMethod::Post,
            url: url.into(),
            headers: BTreeMap::new(),
            body,
        }
    }

    /// Add or replace one request header.
    #[must_use]
    pub fn with_header(mut self, name: impl Into<String>, value: impl Into<String>) -> Self {
        self.headers.insert(name.into(), value.into());
        self
    }
}

/// Raw response returned before redirect and Cookie processing.
#[derive(Clone, Eq, PartialEq)]
pub struct HttpResponse {
    /// HTTP status code.
    pub status: u16,
    /// URL of the request that produced this response.
    pub final_url: String,
    /// Response headers, preserving multiple values such as `Set-Cookie`.
    pub headers: BTreeMap<String, Vec<String>>,
    /// Uninterpreted response body.
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
    /// Construct a response without headers.
    pub fn new(status: u16, final_url: impl Into<String>, body: Vec<u8>) -> Self {
        Self {
            status,
            final_url: final_url.into(),
            headers: BTreeMap::new(),
            body,
        }
    }
}

/// Replaceable HTTP transport. Redirects and cookies remain core responsibilities.
#[async_trait]
pub trait HttpTransport: Send + Sync {
    /// Execute exactly one request and return the raw response.
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse>;
}

/// Production transport with TLS verification and redirects disabled.
#[derive(Clone, Debug)]
pub struct ReqwestTransport {
    client: reqwest::Client,
}

impl ReqwestTransport {
    /// Construct the production client with the verified browser user agent.
    ///
    /// # Errors
    ///
    /// Returns an internal error if the TLS-validating client cannot be built.
    pub fn new() -> Result<Self> {
        let client = reqwest::Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .connect_timeout(std::time::Duration::from_secs(10))
            .timeout(std::time::Duration::from_secs(30))
            .user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0")
            .build()
            .map_err(|_| {
                crate::error::UbaaError::new(
                    crate::error::ErrorCode::InternalError,
                    crate::error::ErrorKind::Internal,
                    false,
                    "could not build HTTP client",
                )
            })?;
        Ok(Self { client })
    }
}

#[async_trait]
impl HttpTransport for ReqwestTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let method = match request.method {
            HttpMethod::Get => reqwest::Method::GET,
            HttpMethod::Post => reqwest::Method::POST,
        };
        let mut builder = self.client.request(method, &request.url);
        for (name, value) in request.headers {
            builder = builder.header(name, value);
        }
        if !request.body.is_empty() {
            builder = builder.body(request.body);
        }
        let response = builder
            .send()
            .await
            .map_err(|error| transport_error(&error))?;
        let status = response.status().as_u16();
        let final_url = response.url().to_string();
        let mut headers = BTreeMap::<String, Vec<String>>::new();
        for (name, value) in response.headers() {
            if let Ok(value) = value.to_str() {
                headers
                    .entry(name.as_str().to_string())
                    .or_default()
                    .push(value.to_string());
            }
        }
        let body = response
            .bytes()
            .await
            .map_err(|error| transport_error(&error))?
            .to_vec();
        Ok(HttpResponse {
            status,
            final_url,
            headers,
            body,
        })
    }
}

fn transport_error(error: &reqwest::Error) -> crate::error::UbaaError {
    if error.is_timeout() {
        return crate::error::UbaaError::new(
            crate::error::ErrorCode::Timeout,
            crate::error::ErrorKind::Network,
            true,
            "upstream request timed out",
        );
    }
    crate::error::UbaaError::new(
        crate::error::ErrorCode::NetworkError,
        crate::error::ErrorKind::Network,
        true,
        "upstream network request failed",
    )
}

fn redacted_header_names(headers: &BTreeMap<String, String>) -> Vec<&str> {
    headers.keys().map(String::as_str).collect()
}

fn redacted_header_names_vec(headers: &BTreeMap<String, Vec<String>>) -> Vec<&str> {
    headers.keys().map(String::as_str).collect()
}
