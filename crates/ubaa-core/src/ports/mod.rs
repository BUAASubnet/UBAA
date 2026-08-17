//! Injectable host ports used by protocol and session code.

use std::collections::BTreeMap;

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
#[derive(Clone, Debug, Eq, PartialEq)]
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
}

/// Raw response returned before redirect and Cookie processing.
#[derive(Clone, Debug, Eq, PartialEq)]
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
