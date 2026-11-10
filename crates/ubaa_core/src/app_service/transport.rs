//! 应用服务专用 HTTP 客户端，仅访问已验证的服务来源。

use super::{AppServiceError, AppServiceResult};
use crate::{
    error::{Result, UbaaError},
    ports::{HttpRequest, HttpResponse, HttpTransport, execute_with_client},
};
use async_trait::async_trait;
use std::net::{Ipv4Addr, Ipv6Addr, SocketAddr};
use url::Url;

const MAX_RESPONSE_BODY_BYTES: usize = 64 * 1024;

pub(super) struct AppServiceTransport {
    endpoint: Url,
    client: reqwest::Client,
}

impl AppServiceTransport {
    pub(super) fn new(endpoint: &Url) -> AppServiceResult<Self> {
        // 独立客户端不安装 Cookie 容器，也不从系统代理转发回环请求。
        let mut builder = reqwest::Client::builder()
            .no_proxy()
            .redirect(reqwest::redirect::Policy::none())
            .retry(reqwest::retry::never())
            .https_only(endpoint.scheme() == "https")
            .tls_danger_accept_invalid_certs(false)
            .tls_danger_accept_invalid_hostnames(false);
        if let Some(host @ ("localhost" | "localhost.")) = endpoint.host_str() {
            builder = builder.resolve_to_addrs(
                host,
                &[
                    SocketAddr::from((Ipv4Addr::LOCALHOST, 0)),
                    SocketAddr::from((Ipv6Addr::LOCALHOST, 0)),
                ],
            );
        }
        Ok(Self {
            endpoint: endpoint.clone(),
            client: builder
                .build()
                .map_err(|_| AppServiceError::TransportUnavailable)?,
        })
    }
}

#[async_trait]
impl HttpTransport for AppServiceTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let url = Url::parse(&request.url).ok();
        if !url.is_some_and(|url| {
            url.origin() == self.endpoint.origin()
                && url.username().is_empty()
                && url.password().is_none()
        }) {
            return Err(UbaaError::invalid_input("应用服务请求地址与构建配置不符"));
        }
        execute_with_client(&self.client, request, MAX_RESPONSE_BODY_BYTES).await
    }
}

#[cfg(test)]
#[path = "tests/transport.rs"]
mod tests;
