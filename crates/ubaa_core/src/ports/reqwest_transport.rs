//! 启用 TLS 校验、限制响应大小的 Reqwest 生产传输。

use std::collections::BTreeMap;
use std::time::Instant;

use async_trait::async_trait;

use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

use super::{HttpMethod, HttpRequest, HttpResponse, HttpTransport};

#[path = "reqwest_transport_diagnostic.rs"]
mod diagnostic;

#[cfg(test)]
#[path = "reqwest_transport_compression_tests.rs"]
mod compression_tests;

#[cfg(test)]
#[path = "reqwest_object_tests.rs"]
mod object_tests;

/// 完整缓冲 HTTP 正文的默认上限。
///
/// 希冀详情中的长代码文本使用单独预算，文件对象使用专用流式端口。
/// 这些是本机资源预算，不是上游协议大小声明。
const MAX_RESPONSE_BODY_BYTES: usize = 8 * 1024 * 1024;
const MAX_JUDGE_DETAIL_BODY_BYTES: usize = 16 * 1024 * 1024;

/// 启用 TLS 校验且禁用重定向的生产传输。
#[derive(Clone, Debug)]
pub struct ReqwestTransport {
    client: reqwest::Client,
    fast_connect_client: reqwest::Client,
    object_client: reqwest::Client,
}

impl ReqwestTransport {
    /// 使用已验证的浏览器 User-Agent 构造生产客户端。
    ///
    /// # Errors
    ///
    /// 无法构造执行 TLS 校验的客户端时返回内部错误。
    pub fn new() -> Result<Self> {
        let ordinary = |connect_seconds| {
            reqwest::Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            // 只协商响应压缩；正文上限继续由流式解压后的累计字节数检查。
            .gzip(true)
            .connect_timeout(std::time::Duration::from_secs(connect_seconds))
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
            })
        };
        let client = ordinary(10)?;
        let fast_connect_client = ordinary(2)?;
        let object_client = reqwest::Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .gzip(false)
            .connect_timeout(std::time::Duration::from_secs(10))
            .timeout(std::time::Duration::from_mins(10))
            .build()
            .map_err(|_| {
                UbaaError::new(
                    ErrorCode::InternalError,
                    ErrorKind::Internal,
                    false,
                    "无法构造对象传输客户端",
                )
            })?;
        Ok(Self {
            client,
            fast_connect_client,
            object_client,
        })
    }
}

#[async_trait]
impl HttpTransport for ReqwestTransport {
    async fn execute_with_fast_connect(&self, request: HttpRequest) -> Result<HttpResponse> {
        let body_limit = response_body_limit(request.method, &request.url);
        execute_with_client(&self.fast_connect_client, request, body_limit).await
    }
    async fn upload(
        &self,
        request: HttpRequest,
        body: Option<super::HttpFileRange>,
        observer: std::sync::Arc<dyn super::HttpTransferObserver>,
    ) -> Result<HttpResponse> {
        self.upload_object(request, body, observer).await
    }
    async fn download(
        &self,
        request: HttpRequest,
        destination: std::fs::File,
        observer: std::sync::Arc<dyn super::HttpTransferObserver>,
    ) -> Result<HttpResponse> {
        self.download_object(request, destination, observer).await
    }

    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let body_limit = response_body_limit(request.method, &request.url);
        execute_with_client(&self.client, request, body_limit).await
    }
}

/// 使用调用方独立配置的客户端执行一次请求，沿用有界正文读取和安全诊断。
pub(crate) async fn execute_with_client(
    client: &reqwest::Client,
    request: HttpRequest,
    body_limit: usize,
) -> Result<HttpResponse> {
    let started = Instant::now();
    let method = match request.method {
        HttpMethod::Get => reqwest::Method::GET,
        HttpMethod::Post => reqwest::Method::POST,
        HttpMethod::Put => reqwest::Method::PUT,
        HttpMethod::Delete => reqwest::Method::DELETE,
    };
    tracing::debug!(target: "ubaa::transport", method = ?method, "HTTP 请求发送");
    let mut builder = client.request(method, &request.url);
    for (name, value) in request.headers {
        builder = builder.header(name, value);
    }
    if !request.body.is_empty() {
        builder = builder.body(request.body);
    }
    let mut response = builder.send().await.map_err(|error| {
        tracing::debug!(
            target: "ubaa::transport",
            timeout = error.is_timeout(),
            connect = error.is_connect(),
            "HTTP 请求发送失败"
        );
        diagnostic::record_reqwest_failure(
            diagnostic::TransportStage::Send,
            &error,
            started.elapsed(),
        );
        transport_error(&error)
    })?;
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
    let body = collect_response_body(&mut response, started, body_limit).await?;
    tracing::debug!(
        target: "ubaa::transport",
        status = status,
        body_bytes = body.len(),
        elapsed = ?started.elapsed(),
        "HTTP 响应完成"
    );
    Ok(HttpResponse {
        status,
        final_url,
        headers,
        body,
    })
}

pub(crate) fn record_telemetry_rejection(status: u16, elapsed: std::time::Duration) {
    let reason = match status {
        400 => diagnostic::FailureReason::TelemetryInvalidPayload,
        413 => diagnostic::FailureReason::TelemetryPayloadTooLarge,
        _ => return,
    };
    diagnostic::record_known_failure(diagnostic::TransportStage::Receive, reason, elapsed);
}

fn response_body_limit(method: HttpMethod, request_url: &str) -> usize {
    if method == HttpMethod::Get {
        let direct_url = crate::connection::from_webvpn_url(request_url)
            .unwrap_or_else(|_| request_url.to_owned());
        if url::Url::parse(&direct_url).is_ok_and(|url| {
            url.host_str() == Some("print.lib.buaa.edu.cn")
                && url.path() == "/api/client/Scan/Download"
        }) {
            return 32 * 1024 * 1024;
        }
        if url::Url::parse(&direct_url).is_ok_and(|url| {
            url.host_str() == Some("judge.buaa.edu.cn")
                && url.path() == "/assignment/index.jsp"
                && url.query_pairs().any(|(key, value)| {
                    key == "assignID"
                        && !value.is_empty()
                        && value.bytes().all(|byte| byte.is_ascii_digit())
                })
        }) {
            return MAX_JUDGE_DETAIL_BODY_BYTES;
        }
    }
    MAX_RESPONSE_BODY_BYTES
}

async fn collect_response_body(
    response: &mut reqwest::Response,
    started: Instant,
    limit: usize,
) -> Result<Vec<u8>> {
    if response
        .content_length()
        .is_some_and(|length| length > limit as u64)
    {
        diagnostic::record_known_failure(
            diagnostic::TransportStage::Receive,
            diagnostic::FailureReason::ResponseTooLarge,
            started.elapsed(),
        );
        return Err(response_too_large());
    }

    let mut body = Vec::new();
    loop {
        let chunk = response.chunk().await.map_err(|error| {
            diagnostic::record_reqwest_failure(
                diagnostic::TransportStage::Receive,
                &error,
                started.elapsed(),
            );
            transport_error(&error)
        })?;
        let Some(chunk) = chunk else {
            break;
        };
        if let Err(error) = append_bounded(&mut body, &chunk, limit) {
            diagnostic::record_known_failure(
                diagnostic::TransportStage::Receive,
                diagnostic::FailureReason::ResponseTooLarge,
                started.elapsed(),
            );
            return Err(error);
        }
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
    use std::collections::BTreeMap;
    use std::io::{Read, Write};
    use std::net::{SocketAddr, TcpListener};
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::sync::{Arc, Mutex, mpsc};

    use tracing::field::{Field, Visit};
    use tracing::span::{Attributes, Id, Record};
    use tracing::{Event, Metadata, Subscriber};

    use super::{HttpRequest, HttpTransport, ReqwestTransport, append_bounded};
    use crate::error::{ErrorCode, ErrorKind};

    #[derive(Debug)]
    struct CapturedEvent {
        level: String,
        fields: BTreeMap<String, String>,
    }

    #[derive(Default)]
    struct CapturingSubscriber {
        events: Arc<Mutex<Vec<CapturedEvent>>>,
        next_span_id: AtomicU64,
    }

    impl Subscriber for CapturingSubscriber {
        fn enabled(&self, metadata: &Metadata<'_>) -> bool {
            metadata.target() == "ubaa::transport"
        }

        fn new_span(&self, _attributes: &Attributes<'_>) -> Id {
            Id::from_u64(self.next_span_id.fetch_add(1, Ordering::Relaxed) + 1)
        }

        fn record(&self, _span: &Id, _values: &Record<'_>) {}

        fn record_follows_from(&self, _span: &Id, _follows: &Id) {}

        fn event(&self, event: &Event<'_>) {
            if event.metadata().target() != "ubaa::transport" {
                return;
            }
            let mut visitor = StringFieldVisitor::default();
            event.record(&mut visitor);
            self.events
                .lock()
                .expect("诊断事件锁不应中毒")
                .push(CapturedEvent {
                    level: event.metadata().level().as_str().to_owned(),
                    fields: visitor.fields,
                });
        }

        fn enter(&self, _span: &Id) {}

        fn exit(&self, _span: &Id) {}
    }

    #[derive(Default)]
    struct StringFieldVisitor {
        fields: BTreeMap<String, String>,
    }

    impl Visit for StringFieldVisitor {
        fn record_u64(&mut self, field: &Field, value: u64) {
            self.fields
                .insert(field.name().to_owned(), value.to_string());
        }

        fn record_str(&mut self, field: &Field, value: &str) {
            self.fields
                .insert(field.name().to_owned(), value.to_owned());
        }

        fn record_debug(&mut self, field: &Field, value: &dyn std::fmt::Debug) {
            self.fields
                .insert(field.name().to_owned(), format!("{value:?}"));
        }
    }

    fn runtime() -> tokio::runtime::Runtime {
        tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap()
    }

    fn direct_test_transport() -> ReqwestTransport {
        ReqwestTransport {
            fast_connect_client: reqwest::Client::builder().no_proxy().build().unwrap(),
            object_client: reqwest::Client::builder()
                .no_proxy()
                .redirect(reqwest::redirect::Policy::none())
                .gzip(false)
                .build()
                .unwrap(),
            client: reqwest::Client::builder()
                .no_proxy()
                .build()
                .expect("测试客户端应可构造"),
        }
    }

    fn capture_events<T>(run: impl FnOnce() -> T) -> (T, Vec<CapturedEvent>) {
        // tracing-core 0.1.36 的单 Dispatch 快路径会用首次触发记录点的线程
        // 判断 interest。并行测试的无订阅者线程可能因此把新记录点缓存为 never。
        // 保留一个不安装的 Dispatch，让整个捕获作用域使用已注册订阅者列表。
        // 上游缺陷：https://github.com/tokio-rs/tracing/issues/3611
        let _dispatcher_guard =
            tracing::Dispatch::new(tracing::subscriber::NoSubscriber::default());
        let subscriber = CapturingSubscriber::default();
        let events = Arc::clone(&subscriber.events);
        let result = tracing::subscriber::with_default(subscriber, run);
        let events = Arc::try_unwrap(events)
            .unwrap_or_else(|_| panic!("诊断事件不应再有其它持有者"))
            .into_inner()
            .expect("诊断事件锁不应中毒");
        (result, events)
    }

    fn serve_once(
        expected_body_len: usize,
        response: Vec<u8>,
    ) -> (
        SocketAddr,
        mpsc::Receiver<Vec<u8>>,
        std::thread::JoinHandle<()>,
    ) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let (request_sender, request_receiver) = mpsc::channel();
        let server = std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut request = Vec::new();
            let mut buffer = [0_u8; 4096];
            loop {
                let read = stream.read(&mut buffer).unwrap();
                if read == 0 {
                    break;
                }
                request.extend_from_slice(&buffer[..read]);
                let header_end = request
                    .windows(4)
                    .position(|window| window == b"\r\n\r\n")
                    .map(|position| position + 4);
                if header_end.is_some_and(|end| request.len() >= end + expected_body_len) {
                    break;
                }
            }
            request_sender.send(request).unwrap();
            stream.write_all(&response).unwrap();
        });
        (address, request_receiver, server)
    }

    fn event_for_stage<'a>(events: &'a [CapturedEvent], stage: &str) -> &'a CapturedEvent {
        events
            .iter()
            .find(|event| {
                event
                    .fields
                    .get("stage")
                    .is_some_and(|value| value == stage)
            })
            .unwrap_or_else(|| panic!("应捕获 {stage} 阶段诊断事件，实际为 {events:?}"))
    }

    #[test]
    fn capture_keeps_diagnostics_first_registered_without_subscriber() {
        const CHILD: &str = "UBAA_TRANSPORT_CAPTURE_CHILD";
        if std::env::var_os(CHILD).is_none() {
            // 独立进程保证记录点尚未注册，也没有其它测试留下的 Dispatch。
            let output = std::process::Command::new(std::env::current_exe().unwrap())
                .args([
                    "--exact",
                    "ports::reqwest_transport::tests::capture_keeps_diagnostics_first_registered_without_subscriber",
                    "--nocapture",
                ])
                .env(CHILD, "1")
                .output()
                .unwrap();
            assert!(
                output.status.success(),
                "独立进程的诊断捕获失败：\n{}\n{}",
                String::from_utf8_lossy(&output.stdout),
                String::from_utf8_lossy(&output.stderr),
            );
            return;
        }

        let record = || {
            super::diagnostic::record_known_failure(
                super::diagnostic::TransportStage::Receive,
                super::diagnostic::FailureReason::UnexpectedEof,
                std::time::Duration::ZERO,
            );
        };
        let ((), events) = capture_events(|| {
            // 捕获作用域已生效，但首次诊断发生在没有订阅者的线程上。
            std::thread::spawn(record).join().unwrap();
            record();
        });
        assert_eq!(events.len(), 1, "只应捕获当前线程的诊断：{events:?}");
        assert_eq!(
            event_for_stage(&events, "receive")
                .fields
                .get("reason")
                .map(String::as_str),
            Some("unexpected_eof"),
        );
    }

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

    #[test]
    fn reqwest_transport_preserves_get_response_contract() {
        let (address, request_receiver, server) = serve_once(
            0,
            b"HTTP/1.1 207 Multi-Status\r\nContent-Length: 7\r\nX-Result: first\r\nX-Result: second\r\nConnection: close\r\n\r\nget-ok!".to_vec(),
        );
        let url = format!("http://{address}/read?mode=local");
        let response = runtime()
            .block_on(
                direct_test_transport()
                    .execute(HttpRequest::get(url.clone()).with_header("X-Contract", "get-value")),
            )
            .unwrap();

        assert_eq!(response.status, 207);
        assert_eq!(response.final_url, url);
        assert_eq!(response.body, b"get-ok!");
        assert_eq!(
            response.headers.get("x-result"),
            Some(&vec!["first".to_owned(), "second".to_owned()])
        );
        let request = String::from_utf8(request_receiver.recv().unwrap()).unwrap();
        assert!(request.starts_with("GET /read?mode=local HTTP/1.1\r\n"));
        assert!(
            request
                .to_ascii_lowercase()
                .contains("x-contract: get-value\r\n")
        );
        server.join().unwrap();
    }

    #[test]
    fn reqwest_transport_preserves_post_request_and_response_contract() {
        let body = b"alpha=1&beta=two".to_vec();
        let (address, request_receiver, server) = serve_once(
            body.len(),
            b"HTTP/1.1 201 Created\r\nContent-Length: 8\r\nConnection: close\r\n\r\npost-ok!"
                .to_vec(),
        );
        let url = format!("http://{address}/submit");
        let response = runtime()
            .block_on(
                direct_test_transport().execute(
                    HttpRequest::post(url.clone(), body.clone())
                        .with_header("Content-Type", "application/x-www-form-urlencoded"),
                ),
            )
            .unwrap();

        assert_eq!(response.status, 201);
        assert_eq!(response.final_url, url);
        assert_eq!(response.body, b"post-ok!");
        let request = request_receiver.recv().unwrap();
        let header_end = request
            .windows(4)
            .position(|window| window == b"\r\n\r\n")
            .map(|position| position + 4)
            .unwrap();
        let headers = String::from_utf8(request[..header_end].to_vec()).unwrap();
        assert!(headers.starts_with("POST /submit HTTP/1.1\r\n"));
        assert!(
            headers
                .to_ascii_lowercase()
                .contains("content-type: application/x-www-form-urlencoded\r\n")
        );
        assert_eq!(&request[header_end..], body);
        server.join().unwrap();
    }

    #[test]
    fn send_failure_emits_redacted_diagnostic_and_preserves_public_error() {
        let request = HttpRequest::post(
            "http://127.0.0.1:0/private-path?token=query-secret",
            b"password=body-secret".to_vec(),
        )
        .with_header("Authorization", "Bearer header-secret");

        let ((error, _runtime), events) = capture_events(|| {
            let runtime = runtime();
            let error = runtime
                .block_on(direct_test_transport().execute(request))
                .expect_err("断开的本地端口必须连接失败");
            (error, runtime)
        });

        assert_eq!(error.code, ErrorCode::NetworkError);
        assert_eq!(error.kind, ErrorKind::Network);
        assert!(error.retryable);
        assert_eq!(error.message, "上游网络请求失败");
        let event = event_for_stage(&events, "send");
        assert_eq!(event.level, "DEBUG");
        assert_eq!(event.fields.len(), 4);
        assert_eq!(
            event.fields.get("message").map(String::as_str),
            Some("HTTP 传输失败")
        );
        assert!(matches!(
            event.fields.get("reason").map(String::as_str),
            Some("connection_refused" | "address_unavailable")
        ));
        assert!(event.fields.contains_key("elapsed_ms"));
        let rendered = format!("{events:?}");
        for forbidden in [
            "http://",
            "private-path",
            "query-secret",
            "body-secret",
            "header-secret",
            "Authorization",
        ] {
            assert!(!rendered.contains(forbidden), "诊断泄露了 {forbidden}");
        }
    }

    #[test]
    fn receive_failure_emits_stage_without_raw_response() {
        let (address, _request_receiver, server) = serve_once(
            0,
            b"HTTP/1.1 200 OK\r\nContent-Length: 12\r\nConnection: close\r\n\r\nsecret".to_vec(),
        );

        let ((error, _runtime), events) = capture_events(|| {
            let runtime = runtime();
            let error = runtime
                .block_on(
                    direct_test_transport()
                        .execute(HttpRequest::get(format!("http://{address}/truncated"))),
                )
                .expect_err("截断响应必须读取失败");
            (error, runtime)
        });

        assert_eq!(error.code, ErrorCode::NetworkError);
        assert_eq!(error.kind, ErrorKind::Network);
        assert!(error.retryable);
        assert_eq!(error.message, "上游网络请求失败");
        let event = event_for_stage(&events, "receive");
        assert!(matches!(
            event.fields.get("reason").map(String::as_str),
            Some("unexpected_eof" | "body")
        ));
        assert!(event.fields.contains_key("elapsed_ms"));
        assert!(!format!("{events:?}").contains("secret"));
        server.join().unwrap();
    }
}

#[path = "reqwest_object.rs"]
mod object;
