//! 用户主动导出的原始学校响应，仅保存在当前客户端的内存中。
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use async_trait::async_trait;
use base64::Engine;
use serde_json::{Value, json};

use super::{HttpFileRange, HttpRequest, HttpResponse, HttpTransferObserver, HttpTransport};
use crate::{domain::ConnectionMode, error::Result};

const MAX_BYTES: usize = 32 * 1024 * 1024;
const MAX_RECORDS: usize = 256;

/// 原始响应的本机内存缓冲；不实现 Debug，避免日志输出响应数据。
#[derive(Clone, Default)]
pub struct RawDiagnostics(Arc<Mutex<Journal>>);

#[derive(Default)]
struct Journal {
    enabled: bool,
    started_ms: u64,
    sequence: u64,
    dropped: u64,
    completed: u64,
    bytes: usize,
    records: VecDeque<(u64, String)>,
}

impl RawDiagnostics {
    /// 宿主装配时启用采集。不会发送请求或读取已有会话文件。
    pub fn enable(&self) {
        let mut journal = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if !journal.enabled {
            journal.started_ms = now_ms();
            journal.enabled = true;
        }
    }

    /// 只在用户主动导出时调用，内容可能包含个人数据和认证凭据。
    #[must_use]
    pub fn export_json(&self) -> String {
        let journal = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let records: Vec<Value> = journal
            .records
            .iter()
            .filter_map(|(_, text)| serde_json::from_str(text).ok())
            .collect();
        json!({
            "capture_scope": "client_lifetime",
            "enabled": journal.enabled,
            "started_at_unix_ms": journal.started_ms,
            "exported_at_unix_ms": now_ms(),
            "max_records": MAX_RECORDS,
            "max_bytes": MAX_BYTES,
            "dropped_records": journal.dropped,
            "started_requests": journal.sequence,
            "completed_requests": journal.completed,
            "unfinished_requests": journal.sequence.saturating_sub(journal.completed),
            "redacted": false,
            "records": records,
        })
        .to_string()
    }

    fn begin(&self) -> Option<u64> {
        let mut journal = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if !journal.enabled {
            return None;
        }
        journal.sequence += 1;
        Some(journal.sequence)
    }

    fn push(&self, id: u64, record: &Value) {
        let text = record.to_string();
        let mut journal = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        journal.completed += 1;
        if text.len() > MAX_BYTES {
            journal.dropped += 1;
            return;
        }
        while journal.records.len() >= MAX_RECORDS || journal.bytes + text.len() > MAX_BYTES {
            if let Some((_, removed)) = journal.records.pop_front() {
                journal.bytes -= removed.len();
                journal.dropped += 1;
            } else {
                break;
            }
        }
        journal.bytes += text.len();
        // 请求可以并发完成，按开始顺序导出，方便关联认证与后续查询。
        let position = journal
            .records
            .iter()
            .position(|(other, _)| *other > id)
            .unwrap_or(journal.records.len());
        journal.records.insert(position, (id, text));
    }
}

fn now_ms() -> u64 {
    u64::try_from(
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis(),
    )
    .unwrap_or(u64::MAX)
}

pub(crate) struct RecordingTransport<T> {
    pub inner: T,
    pub diagnostics: RawDiagnostics,
    pub route: ConnectionMode,
}

impl<T: HttpTransport> RecordingTransport<T> {
    async fn capture<F>(
        &self,
        method: super::HttpMethod,
        url: String,
        streamed: bool,
        pending: F,
    ) -> Result<HttpResponse>
    where
        F: std::future::Future<Output = Result<HttpResponse>> + Send,
    {
        self.capture_response(method, url, async move {
            let response = pending.await?;
            let capture = if streamed && response.status == 200 {
                "delivered_to_file"
            } else {
                "complete"
            };
            Ok((response, capture))
        })
        .await
    }

    async fn capture_response(
        &self,
        method: super::HttpMethod,
        url: String,
        pending: impl std::future::Future<Output = Result<(HttpResponse, &'static str)>> + Send,
    ) -> Result<HttpResponse> {
        let id = self.diagnostics.begin();
        let started = now_ms();
        let timer = Instant::now();
        let result = pending.await;
        if let Some(id) = id {
            let mut record = json!({
                "request_id": id, "route": self.route,
                "method": method, "url": url,
                "started_at_unix_ms": started, "elapsed_ms": timer.elapsed().as_millis(),
            });
            match &result {
                Ok((response, capture)) => {
                    let (encoding, body) = match std::str::from_utf8(&response.body) {
                        Ok(text) => ("utf8", text.to_owned()),
                        Err(_) => (
                            "base64",
                            base64::engine::general_purpose::STANDARD.encode(&response.body),
                        ),
                    };
                    record["response"] = json!({
                        "status": response.status, "url": response.final_url,
                        "headers": response.headers, "body": body, "body_encoding": encoding,
                        "body_bytes": response.body.len(),
                        "body_capture": capture,
                    });
                }
                Err(error) => {
                    record["transport_error"] =
                        json!({"code": error.code, "diagnostic": error.diagnostic()});
                }
            }
            self.diagnostics.push(id, &record);
        }
        result.map(|(response, _)| response)
    }
}

#[async_trait]
impl<T: HttpTransport> HttpTransport for RecordingTransport<T> {
    async fn download_stream(
        &self,
        request: HttpRequest,
        sink: &mut super::StreamSink,
    ) -> Result<HttpResponse> {
        self.capture_response(request.method, request.url.clone(), async {
            let response = self.inner.download_stream(request, sink).await?;
            Ok((response, sink.capture_kind()))
        })
        .await
    }
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.capture(
            request.method,
            request.url.clone(),
            false,
            self.inner.execute(request),
        )
        .await
    }
    async fn execute_with_fast_connect(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.capture(
            request.method,
            request.url.clone(),
            false,
            self.inner.execute_with_fast_connect(request),
        )
        .await
    }
    async fn upload(
        &self,
        request: HttpRequest,
        body: Option<HttpFileRange>,
        observer: Arc<dyn HttpTransferObserver>,
    ) -> Result<HttpResponse> {
        self.capture(
            request.method,
            request.url.clone(),
            false,
            self.inner.upload(request, body, observer),
        )
        .await
    }
    async fn download(
        &self,
        request: HttpRequest,
        destination: std::fs::File,
        observer: Arc<dyn HttpTransferObserver>,
    ) -> Result<HttpResponse> {
        self.capture(
            request.method,
            request.url.clone(),
            true,
            self.inner.download(request, destination, observer),
        )
        .await
    }
}

#[cfg(test)]
mod tests;
