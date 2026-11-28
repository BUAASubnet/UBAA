//! 用户主动导出的原始学校响应，仅保存在当前客户端的内存中。
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use async_trait::async_trait;
use base64::Engine;
use serde_json::{Value, json};

use super::{HttpFileRange, HttpRequest, HttpResponse, HttpTransferObserver, HttpTransport};
use crate::{
    domain::{ConnectionMode, UserProfile},
    error::Result,
};
mod redact;

const MAX_BYTES: usize = 32 * 1024 * 1024;
const MAX_RECORDS: usize = 256;

/// 原始响应的本机内存缓冲；不实现 Debug，避免日志输出响应数据。
#[derive(Clone, Default)]
pub struct RawDiagnostics(Arc<Mutex<Journal>>);

#[derive(Default)]
struct Journal {
    enabled: bool,
    state: SessionState,
    started_ms: u64,
    generation: u64,
    expected_account: Option<String>,
    account: Option<VerifiedAccount>,
    attempt: u64,
    sequence: u64,
    dropped: u64,
    completed: u64,
    bytes: usize,
    records: VecDeque<Record>,
}

#[derive(Default, PartialEq, Eq)]
enum SessionState {
    #[default]
    Open,
    SignedOut,
    Closed,
}

struct VerifiedAccount {
    school_id: String,
    username: Option<String>,
}

impl VerifiedAccount {
    fn matches(&self, expected: &str) -> bool {
        self.school_id == expected || self.username.as_deref() == Some(expected)
    }
}

struct Record {
    id: CaptureId,
    text: String,
}

#[derive(Clone, Copy)]
struct CaptureId {
    generation: u64,
    attempt: Option<u64>,
    sequence: u64,
}

#[derive(Clone, Copy)]
pub(crate) struct ConfirmedOwner(u64);

#[derive(Clone)]
struct CaptureScope {
    diagnostics: RawDiagnostics,
    generation: u64,
    attempt: Option<u64>,
}

tokio::task_local! {
    static CAPTURE_SCOPE: CaptureScope;
}

/// 归属未核验的认证过程。Future 被取消或认证失败时随作用域丢弃。
pub(crate) struct DiagnosticAttempt(CaptureScope);

impl DiagnosticAttempt {
    pub(crate) async fn scope<T>(&self, future: impl Future<Output = T>) -> T {
        CAPTURE_SCOPE.scope(self.0.clone(), future).await
    }

    pub(crate) fn confirm(
        self,
        profile: &UserProfile,
        current: impl FnOnce() -> bool,
    ) -> Option<ConfirmedOwner> {
        let school_id = profile
            .school_id
            .as_deref()
            .or(profile.username.as_deref())?;
        let mut journal = self.0.diagnostics.lock();
        if !journal.accepts(self.0.generation)
            || journal
                .account
                .as_ref()
                .is_some_and(|bound| bound.school_id != school_id)
            || journal.expected_account.as_deref().is_some_and(|expected| {
                school_id != expected && profile.username.as_deref() != Some(expected)
            })
            || !current()
        {
            return None;
        }
        journal.account.get_or_insert_with(|| VerifiedAccount {
            school_id: school_id.to_owned(),
            username: profile.username.clone(),
        });
        for record in &mut journal.records {
            if self.0.owns(&record.id) {
                record.id.attempt = None;
            }
        }
        Some(ConfirmedOwner(self.0.generation))
    }
}

impl Drop for DiagnosticAttempt {
    fn drop(&mut self) {
        let mut journal = self.0.diagnostics.lock();
        if journal.generation != self.0.generation {
            return;
        }
        let mut bytes = 0;
        journal.records.retain(|record| {
            let discard = self.0.owns(&record.id);
            if discard {
                bytes += record.text.len();
            }
            !discard
        });
        journal.bytes -= bytes;
    }
}

impl CaptureScope {
    fn owns(&self, id: &CaptureId) -> bool {
        id.generation == self.generation && id.attempt == self.attempt
    }
}

impl Journal {
    fn accepts(&self, generation: u64) -> bool {
        generation == self.generation && self.state == SessionState::Open
    }

    fn next(&self, state: SessionState) -> Self {
        Self {
            enabled: self.enabled,
            started_ms: if self.enabled && state == SessionState::Open {
                now_ms()
            } else {
                0
            },
            state,
            generation: self.generation + 1,
            ..Self::default()
        }
    }
}

impl RawDiagnostics {
    fn lock(&self) -> std::sync::MutexGuard<'_, Journal> {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }

    /// 宿主装配时启用采集。不会发送请求或读取已有会话文件。
    pub fn enable(&self) {
        let mut journal = self.lock();
        if !journal.enabled && journal.state != SessionState::Closed {
            journal.started_ms = now_ms();
            journal.enabled = true;
        }
    }

    /// 只在用户主动导出时调用，内容可能包含个人数据和认证凭据。
    #[must_use]
    pub fn export_json(&self) -> String {
        let journal = self.lock();
        let records: Vec<Value> = journal
            .records
            .iter()
            .filter(|record| record.id.attempt.is_none() && journal.accepts(record.id.generation))
            .filter_map(|record| serde_json::from_str(&record.text).ok())
            .collect();
        json!({
            "capture_scope": "client_lifetime",
            "enabled": journal.enabled && journal.state == SessionState::Open,
            "started_at_unix_ms": journal.started_ms,
            "exported_at_unix_ms": now_ms(),
            "max_records": MAX_RECORDS,
            "max_bytes": MAX_BYTES,
            "dropped_records": journal.dropped,
            "started_requests": journal.sequence,
            "completed_requests": journal.completed,
            "unfinished_requests": journal.sequence.saturating_sub(journal.completed),
            "redacted": false,
            "redaction_scope": "selected_fields",
            "records": records,
        })
        .to_string()
    }

    /// 本机退出立即清空、停采，并废弃此前已开始的请求。
    pub fn end_local_session(&self) {
        self.advance(SessionState::SignedOut, |_| true);
    }

    /// 后端开始关闭时永久废弃此缓冲，无需等待业务锁。
    pub fn close(&self) {
        self.advance(SessionState::Closed, |_| true);
    }

    /// 显式登录在等待会话文件锁之前更换归属代次。
    pub(crate) fn begin_explicit(&self, generation: u64, current: impl FnOnce() -> bool) -> u64 {
        self.advance(SessionState::Open, |observed| {
            observed == generation && current()
        })
        .unwrap_or(generation)
    }

    fn advance(&self, state: SessionState, current: impl FnOnce(u64) -> bool) -> Option<u64> {
        let mut journal = self.lock();
        if journal.state == SessionState::Closed || !current(journal.generation) {
            return None;
        }
        let next = journal.next(state);
        let generation = next.generation;
        let previous = std::mem::replace(&mut *journal, next);
        drop(journal);
        drop(previous);
        Some(generation)
    }

    /// 宿主转交固定共享账号的用户名，认证通过后仍需和上游身份比对。
    pub fn bind_expected_account(&self, username: String) {
        let mut journal = self.lock();
        if journal.state == SessionState::Closed {
            return;
        }
        if journal
            .account
            .as_ref()
            .is_some_and(|account| !account.matches(&username))
        {
            let next = journal.next(SessionState::Open);
            *journal = next;
        }
        journal.expected_account = Some(username);
    }

    pub(crate) fn generation(&self) -> u64 {
        self.lock().generation
    }

    pub(crate) fn pending(&self, generation: u64) -> DiagnosticAttempt {
        let mut journal = self.lock();
        journal.attempt += 1;
        DiagnosticAttempt(CaptureScope {
            diagnostics: self.clone(),
            generation,
            attempt: Some(journal.attempt),
        })
    }

    pub(crate) async fn capture_for<T>(
        &self,
        ConfirmedOwner(generation): ConfirmedOwner,
        future: impl Future<Output = T>,
    ) -> T {
        // 认证的待确认作用域优先于传输发起方原有的账号归属。
        if CAPTURE_SCOPE.try_with(|_| ()).is_err() {
            return CAPTURE_SCOPE
                .scope(
                    CaptureScope {
                        diagnostics: self.clone(),
                        generation,
                        attempt: None,
                    },
                    future,
                )
                .await;
        }
        future.await
    }

    fn begin(&self) -> Option<CaptureId> {
        CAPTURE_SCOPE
            .try_with(|scope| {
                if !Arc::ptr_eq(&self.0, &scope.diagnostics.0) {
                    return None;
                }
                let mut journal = self.lock();
                if !journal.enabled || !journal.accepts(scope.generation) {
                    return None;
                }
                journal.sequence += 1;
                Some(CaptureId {
                    generation: scope.generation,
                    attempt: scope.attempt,
                    sequence: journal.sequence,
                })
            })
            .ok()
            .flatten()
    }

    fn push(&self, id: &CaptureId, record: &Value) {
        let text = record.to_string();
        let mut journal = self.lock();
        if !journal.accepts(id.generation) {
            return;
        }
        journal.completed += 1;
        if text.len() > MAX_BYTES {
            journal.dropped += 1;
            return;
        }
        while journal.records.len() >= MAX_RECORDS || journal.bytes + text.len() > MAX_BYTES {
            // 待确认记录不能挤掉已确认的故障现场。预算由两类记录共用。
            let pending = journal
                .records
                .iter()
                .position(|record| record.id.attempt.is_some());
            let Some(index) = pending.or_else(|| id.attempt.is_none().then_some(0)) else {
                journal.dropped += 1;
                return;
            };
            let removed = journal
                .records
                .remove(index)
                .expect("超限时缓冲有可淘汰记录");
            journal.bytes -= removed.text.len();
            journal.dropped += 1;
        }
        journal.bytes += text.len();
        // 请求可以并发完成，按开始顺序导出，方便关联认证与后续查询。
        let position = journal
            .records
            .iter()
            .position(|record| record.id.sequence > id.sequence)
            .unwrap_or(journal.records.len());
        journal.records.insert(position, Record { id: *id, text });
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
                "request_id": id.sequence, "route": self.route,
                "method": method, "url": redact::url(&url),
                "started_at_unix_ms": started, "elapsed_ms": timer.elapsed().as_millis(),
            });
            match &result {
                Ok((response, capture)) => {
                    let masked = redact::body(&url, &response.body);
                    let capture = if masked.is_some() {
                        "redacted"
                    } else {
                        *capture
                    };
                    let (encoding, body) = if let Some(text) = masked {
                        ("utf8", text)
                    } else {
                        match std::str::from_utf8(&response.body) {
                            Ok(text) => ("utf8", text.to_owned()),
                            Err(_) => (
                                "base64",
                                base64::engine::general_purpose::STANDARD.encode(&response.body),
                            ),
                        }
                    };
                    record["response"] = json!({
                        "status": response.status, "url": redact::url(&response.final_url),
                        "headers": redact::headers(&url, response), "body": body, "body_encoding": encoding,
                        "body_bytes": response.body.len(),
                        "body_capture": capture,
                    });
                }
                Err(error) => {
                    record["transport_error"] =
                        json!({"code": error.code, "diagnostic": error.diagnostic()});
                }
            }
            self.diagnostics.push(&id, &record);
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
