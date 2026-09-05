//! 启用 TLS 校验、限制响应大小的 Reqwest 生产传输。

use std::collections::BTreeMap;

use async_trait::async_trait;

use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

use super::{HttpMethod, HttpRequest, HttpResponse, HttpTransport};

/// 完整缓冲认证和用户中心响应的保守上限。
///
/// 这是实现安全预算，不是上游协议大小声明。更大的业务载荷应使用独立流式端口，
/// 不应全局提高此上限。
const MAX_RESPONSE_BODY_BYTES: usize = 8 * 1024 * 1024;

/// 启用 TLS 校验且禁用重定向的生产传输。
#[derive(Clone, Debug)]
pub struct ReqwestTransport {
    client: reqwest::Client,
}

impl ReqwestTransport {
    /// 使用已验证的浏览器 User-Agent 构造生产客户端。
    ///
    /// # Errors
    ///
    /// 无法构造执行 TLS 校验的客户端时返回内部错误。
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
                    "无法构造 HTTP 客户端",
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
        let mut response = builder
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
        let body = collect_response_body(&mut response).await?;
        Ok(HttpResponse {
            status,
            final_url,
            headers,
            body,
        })
    }
}

async fn collect_response_body(response: &mut reqwest::Response) -> Result<Vec<u8>> {
    if response
        .content_length()
        .is_some_and(|length| length > MAX_RESPONSE_BODY_BYTES as u64)
    {
        return Err(response_too_large());
    }

    let mut body = Vec::new();
    while let Some(chunk) = response
        .chunk()
        .await
        .map_err(|error| transport_error(&error))?
    {
        append_bounded(&mut body, &chunk, MAX_RESPONSE_BODY_BYTES)?;
    }
    Ok(body)
}

fn append_bounded(body: &mut Vec<u8>, chunk: &[u8], limit: usize) -> Result<()> {
    let new_len = body
        .len()
        .checked_add(chunk.len())
        .ok_or_else(response_too_large)?;
    if new_len > limit {
        return Err(response_too_large());
    }
    body.extend_from_slice(chunk);
    Ok(())
}

fn response_too_large() -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        "上游响应体超过允许大小",
    )
}

fn transport_error(error: &reqwest::Error) -> crate::error::UbaaError {
    if error.is_timeout() {
        return crate::error::UbaaError::new(
            crate::error::ErrorCode::Timeout,
            crate::error::ErrorKind::Network,
            true,
            "上游请求超时",
        );
    }
    crate::error::UbaaError::new(
        crate::error::ErrorCode::NetworkError,
        crate::error::ErrorKind::Network,
        true,
        "上游网络请求失败",
    )
}

#[cfg(test)]
mod tests {
    use std::io::{Read, Write};
    use std::net::TcpListener;

    use super::{HttpRequest, HttpTransport, ReqwestTransport, append_bounded};
    use crate::error::{ErrorCode, ErrorKind};

    #[test]
    fn bounded_append_accepts_exact_limit_and_rejects_without_copying() {
        let mut body = vec![1, 2];
        append_bounded(&mut body, &[3, 4], 4).expect("exact limit is valid");
        assert_eq!(body, [1, 2, 3, 4]);

        let before = body.clone();
        let error = append_bounded(&mut body, &[5], 4).expect_err("one byte over limit fails");
        assert_eq!(error.message, "上游响应体超过允许大小");
        assert_eq!(body, before, "rejected chunk must not be appended");
    }

    #[test]
    fn bounded_append_rejects_length_overflow() {
        let mut body = Vec::new();
        let error = append_bounded(&mut body, &[0; 4], 3).expect_err("over-limit chunk fails");
        assert_eq!(error.message, "上游响应体超过允许大小");
    }

    #[test]
    fn reqwest_transport_rejects_oversized_chunked_response() {
        const LIMIT: usize = 8 * 1024 * 1024;
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let server = std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut request = [0_u8; 4096];
            let _ = stream.read(&mut request);
            stream
                .write_all(
                    b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n",
                )
                .unwrap();
            let chunk = vec![b'x'; 64 * 1024];
            let mut remaining = LIMIT + 1;
            while remaining > 0 {
                let length = remaining.min(chunk.len());
                if write!(stream, "{length:X}\r\n")
                    .and_then(|()| stream.write_all(&chunk[..length]))
                    .and_then(|()| stream.write_all(b"\r\n"))
                    .is_err()
                {
                    return;
                }
                remaining -= length;
            }
            let _ = stream.write_all(b"0\r\n\r\n");
        });
        let transport = ReqwestTransport::new().unwrap();
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();

        let error = runtime
            .block_on(transport.execute(HttpRequest::get(format!("http://{address}/oversized"))))
            .expect_err("an oversized streamed response must be rejected");

        assert_eq!(error.code, ErrorCode::UpstreamChanged);
        assert_eq!(error.kind, ErrorKind::Upstream);
        assert!(!error.retryable);
        assert_eq!(error.message, "上游响应体超过允许大小");
        server.join().unwrap();
    }
}
