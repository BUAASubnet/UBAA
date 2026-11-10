//! 一次遥测交付与删除重试。具体触发时机由宿主负责。

use super::{
    APP_SERVICE_SCHEMA_VERSION, AppService, AppServiceResult, BatchDisposition, Surface,
    transport::AppServiceTransport,
};
use crate::ports::{HttpRequest, HttpTransport, record_telemetry_rejection, same_url};
use serde::Serialize;
use std::{
    future::{Future, poll_fn},
    task::{Context, Poll},
    time::Duration,
};
use tokio::time::{Instant, timeout_at};
use url::Url;
use uuid::Uuid;

const TELEMETRY_PATH: &str = "/v1/telemetry";
const ERASE_PATH: &str = "/v1/telemetry/erase";
const GUI_TIMEOUT: Duration = Duration::from_secs(10);
const COMMAND_TIMEOUT: Duration = Duration::from_secs(2);

/// 本次尝试对待删除标记的处理结果。
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum EraseAttempt {
    #[default]
    NotAttempted,
    Completed,
    Pending,
}

/// 本次触发的发送摘要，不包含请求内容或标识。
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct UploadAttempt {
    pub erase: EraseAttempt,
    pub batches_sent: u8,
    pub last_batch: Option<BatchDisposition>,
}

#[derive(Serialize)]
struct ErasePayload {
    schema: u32,
    install_id: Uuid,
}

impl AppService {
    /// 根据打开时指定的宿主类型执行一次上传。若有可重试的删除，本次只发送删除。
    /// GUI 最多发送四批，每次请求十秒；命令模式最多一批，整次发送限时两秒。
    ///
    /// # Errors
    /// 无法使用存储或初始化独立传输时返回错误。请求失败保留数据和标记，
    /// 由返回值报告是否需要重试。宿主应保持原业务结果。
    pub async fn upload_once(&self) -> AppServiceResult<UploadAttempt> {
        let Some(endpoint) = self.endpoint() else {
            return Ok(UploadAttempt::default());
        };
        self.upload_with(&AppServiceTransport::new(endpoint)?).await
    }

    /// 从 GUI 发起或手动重试删除。先持久化标记，本次只发送删除。
    ///
    /// # Errors
    /// 非 GUI 宿主、存储失败或无法初始化独立传输时返回错误。
    /// 未收到 204 的删除标记保留，供下次重试。
    pub async fn erase_once(&self) -> AppServiceResult<EraseAttempt> {
        let Some(install) = self.begin_erase()? else {
            return Ok(EraseAttempt::NotAttempted);
        };
        let Some(endpoint) = self.endpoint() else {
            return Ok(EraseAttempt::NotAttempted);
        };
        let transport = AppServiceTransport::new(endpoint)?;
        self.send_erase(&transport, endpoint, Some(install), None)
            .await
    }

    async fn upload_with(&self, transport: &dyn HttpTransport) -> AppServiceResult<UploadAttempt> {
        let mut attempt = UploadAttempt::default();
        let Some(endpoint) = self.endpoint() else {
            return Ok(attempt);
        };
        let command_deadline =
            (self.surface == Surface::Command).then(|| Instant::now() + COMMAND_TIMEOUT);
        attempt.erase = self
            .send_erase(transport, endpoint, None, command_deadline)
            .await?;
        if attempt.erase != EraseAttempt::NotAttempted {
            return Ok(attempt);
        }
        let limit = if self.surface == Surface::Gui { 4 } else { 1 };
        for _ in 0..limit {
            if command_deadline.is_some_and(|end| Instant::now() >= end) {
                break;
            }
            let Some(batch) = self.freeze_next()? else {
                break;
            };
            let id = batch.id();
            let started = std::time::Instant::now();
            let handed_off = poll_fn(|cx| {
                Poll::Ready(
                    self.with_batch_for_send(id, |batch| {
                        start_request(
                            transport,
                            endpoint,
                            TELEMETRY_PATH,
                            batch.into_body(),
                            command_deadline,
                            cx,
                        )
                    })
                    .map(Option::flatten),
                )
            })
            .await?;
            let Some(response) = handed_off else { break };
            let status = response.await;
            let disposition = match status {
                Some(204) => BatchDisposition::Accepted,
                Some(410) => BatchDisposition::InstallErased,
                Some(400 | 413) => BatchDisposition::InvalidPayload,
                _ => BatchDisposition::Retry,
            };
            let finished = self.finish_batch(id, disposition)?;
            if let Some(status) = status.filter(|_| finished) {
                record_telemetry_rejection(status, started.elapsed());
            }
            attempt.batches_sent += 1;
            attempt.last_batch = Some(disposition);
            if matches!(
                disposition,
                BatchDisposition::Retry | BatchDisposition::InstallErased
            ) {
                break;
            }
        }
        Ok(attempt)
    }

    async fn send_erase(
        &self,
        transport: &dyn HttpTransport,
        endpoint: &Url,
        expected: Option<Uuid>,
        command_deadline: Option<Instant>,
    ) -> AppServiceResult<EraseAttempt> {
        let handed_off = poll_fn(|cx| {
            Poll::Ready(self.store.write(|tx| {
                let state = self.permissions(tx)?;
                let Some(install_id) = state.erasing_install_id.filter(|&id| {
                    state.can_erase() && expected.is_none_or(|expected| expected == id)
                }) else {
                    return Ok(None);
                };
                let body = serde_json::to_vec(&ErasePayload {
                    schema: APP_SERVICE_SCHEMA_VERSION,
                    install_id,
                })?;
                Ok(
                    start_request(transport, endpoint, ERASE_PATH, body, command_deadline, cx)
                        .map(|request| (install_id, request)),
                )
            }))
        })
        .await?;
        let Some((install_id, response)) = handed_off else {
            return Ok(EraseAttempt::NotAttempted);
        };
        if response.await == Some(204) {
            self.finish_erase(install_id)?;
            return Ok(EraseAttempt::Completed);
        }
        Ok(EraseAttempt::Pending)
    }
}

// 首次轮询与共享状态的复核在同一短事务中完成。事务结束后继续等待，
// 调用者取消时一起丢弃请求，不留下脱离宿主预算的后台任务。
fn start_request<'a>(
    transport: &'a dyn HttpTransport,
    endpoint: &Url,
    path: &str,
    body: Vec<u8>,
    command_deadline: Option<Instant>,
    cx: &mut Context<'_>,
) -> Option<impl Future<Output = Option<u16>> + use<'a>> {
    let deadline = command_deadline.unwrap_or_else(|| Instant::now() + GUI_TIMEOUT);
    if Instant::now() >= deadline {
        return None;
    }
    let mut url = endpoint.clone();
    url.set_path(path);
    let request =
        HttpRequest::post(url.to_string(), body).with_header("content-type", "application/json");
    let mut future = Box::pin(timeout_at(deadline, transport.execute(request)));
    let first = future.as_mut().poll(cx);
    Some(async move {
        let response = match first {
            Poll::Ready(response) => response,
            Poll::Pending => future.await,
        }
        .ok()?
        .ok()?;
        same_url(url.as_str(), &response.final_url).then_some(response.status)
    })
}

#[cfg(test)]
#[path = "tests/upload.rs"]
mod tests;
