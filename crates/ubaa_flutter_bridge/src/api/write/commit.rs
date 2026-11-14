//! 一次性写入意图的消费、提交前复核与 Core 写分派。

use super::BridgeWriteCommitResult;
use super::cache::{BridgeCachedWriteCommit, finish_cached_commit};
use super::support::{invalid_input, map_commit_error, now_seconds};
use crate::api::client::{
    BridgeClient, BridgeConnectionMode, BridgeError, BridgeErrorCode, BridgeErrorKind,
    disposed_error, panic_error,
};
use crate::api::offline::BridgeOfflineCache;
use futures_util::FutureExt;
use std::panic::AssertUnwindSafe;
use ubaa_core::facade as domain;

impl BridgeClient {
    pub(crate) async fn take_write_entry(
        &self,
        intent_id: &str,
    ) -> Result<super::PendingEntry, BridgeError> {
        if intent_id.trim().is_empty() {
            return Err(invalid_input("intent id is required"));
        }
        let entry = self
            .write_intents
            .lock()
            .await
            .remove(intent_id)
            .ok_or_else(|| {
                BridgeError::local(
                    BridgeErrorCode::IntentExpired,
                    BridgeErrorKind::Input,
                    false,
                    "write intent is expired or already used",
                )
            })?;
        if now_seconds() >= entry.expires_at {
            return Err(BridgeError::local(
                BridgeErrorCode::IntentExpired,
                BridgeErrorKind::Input,
                false,
                "write intent is expired",
            ));
        }
        Ok(entry)
    }
    pub async fn commit_write(
        &self,
        intent_id: String,
    ) -> Result<BridgeWriteCommitResult, BridgeError> {
        self.commit_write_scoped(None, intent_id)
            .await?
            .into_legacy()
    }

    #[flutter_rust_bridge::frb(ignore)]
    pub(super) async fn commit_write_scoped(
        &self,
        cache: Option<&BridgeOfflineCache>,
        intent_id: String,
    ) -> Result<BridgeCachedWriteCommit, BridgeError> {
        let mut panic_scope = None;
        let mut hint = None;
        let mut hint_start_error = None;
        let attempted = AssertUnwindSafe(async {
            if intent_id.trim().is_empty() {
                return Err(invalid_input("intent id is required"));
            }
            // 所有会清理写意图的路径都先持有 Core 锁；这样重新登录或重开路线
            // 不会在本次提交等待 Core 锁时失效后，仍让旧意图继续执行。
            let mut guard = self.inner.lock().await;
            let entry = self.take_write_entry(&intent_id).await?;
            let pending = entry.request;
            let operation = pending.operation();
            let impact = pending.cache_impact();
            let expected_route = entry.resolved_route;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let observation = client.observe_write_boundary();
            panic_scope = Some((observation, impact.clone(), expected_route));
            // 所有提交都在 Core 一次解析中绑定确认路线、fresh authority 和最终发送。
            // 博雅详情的唯一提交前复核也在 Core；Bridge 不再重复读取另一份 authority。
            let (started_hint, start_error) =
                super::readback::begin_hint(cache, operation, expected_route).await;
            hint = started_hint;
            hint_start_error = start_error;
            let raw = super::dispatch::dispatch(client, pending, expected_route.into()).await;
            let result = project_dispatch_result(raw, operation, expected_route);
            // 跨过发送边界后，提示必须等 Dart 投影成功才能清理。
            let sent = panic_scope
                .as_ref()
                .is_some_and(|(observation, _, _)| observation.may_have_been_sent());
            let hint_id = if sent {
                hint.as_ref().map(|ticket| ticket.id().to_owned())
            } else {
                None
            };
            let hint_finish_error = if sent {
                None
            } else {
                super::readback::finish_hint(cache, hint.take(), &result).await
            };
            let mut result = finish_cached_commit(cache, impact, expected_route, result).await;
            result.readback_hint_id = hint_id;
            result.cache_error = result
                .cache_error
                .or(hint_start_error)
                .or(hint_finish_error);
            drop(guard);
            Ok(result)
        })
        .catch_unwind()
        .await;
        match attempted {
            Ok(result) => result,
            Err(_) => {
                let Some((observation, impact, route)) = panic_scope else {
                    return Err(panic_error());
                };
                let mut error = panic_error();
                let mut hint_finish_error = None;
                if observation.may_have_been_sent() {
                    error.code = BridgeErrorCode::OutcomeUnknown;
                    error.message = "写入结果无法确认，请核对后再操作".into();
                    error.resolved_route = Some(route);
                } else {
                    hint_finish_error =
                        super::readback::finish_hint(cache, hint, &Err(error.clone())).await;
                }
                let mut result = finish_cached_commit(cache, impact, route, Err(error)).await;
                result.cache_error = result
                    .cache_error
                    .or(hint_start_error)
                    .or(hint_finish_error);
                Ok(result)
            }
        }
    }
}

pub(super) fn evaluation_commit_message(
    batch: &super::BridgeEvaluationBatchResult,
) -> &'static str {
    if batch.outcome_unknown {
        "评教结果未确认，请刷新后查看"
    } else if batch.success {
        "评教成功"
    } else {
        "部分课程评教失败，请重试"
    }
}

pub(super) fn finish_commit_success(
    operation: super::BridgeWriteOperation,
    resolved_route: BridgeConnectionMode,
    success: bool,
    message: String,
    cgyy_receipt: Option<super::BridgeCgyyReservationReceipt>,
    ygdk_receipt: Option<super::BridgeYgdkSubmitReceipt>,
    evaluation_result: Option<super::BridgeEvaluationBatchResult>,
) -> Result<BridgeWriteCommitResult, BridgeError> {
    if matches!(operation, super::BridgeWriteOperation::CgyyCancelOrder) && !success {
        return Err(BridgeError {
            auth_stage: None,
            auth_reason: None,
            cache_failure: None,
            code: BridgeErrorCode::UpstreamChanged,
            kind: BridgeErrorKind::Upstream,
            retryable: false,
            message: "研讨室订单取消响应未确认成功".to_owned(),
            resolved_route: Some(resolved_route),
        });
    }
    if matches!(operation, super::BridgeWriteOperation::YgdkSubmit) && !success {
        return Err(BridgeError {
            auth_stage: None,
            auth_reason: None,
            cache_failure: None,
            code: BridgeErrorCode::UpstreamChanged,
            kind: BridgeErrorKind::Upstream,
            retryable: false,
            message: "阳光打卡响应未确认成功".to_owned(),
            resolved_route: Some(resolved_route),
        });
    }
    Ok(BridgeWriteCommitResult {
        operation,
        success,
        message,
        outcome_unknown: evaluation_result
            .as_ref()
            .is_some_and(|result| result.outcome_unknown),
        resolved_route: Some(resolved_route),
        cgyy_receipt,
        ygdk_receipt,
        evaluation_result,
    })
}

fn map_dispatch_error(
    operation: super::BridgeWriteOperation,
    expected_route: BridgeConnectionMode,
    error: domain::RoutedError,
) -> BridgeError {
    if error.error.code == domain::ErrorCode::InvalidInput
        && error
            .resolution()
            .is_some_and(|resolution| resolution.mode != expected_route.into())
    {
        return BridgeError {
            auth_stage: None,
            auth_reason: None,
            cache_failure: None,
            code: BridgeErrorCode::OperationConflict,
            kind: BridgeErrorKind::Input,
            retryable: true,
            message: "route changed; prepare the write again".to_owned(),
            resolved_route: error.resolution().map(|resolution| resolution.mode.into()),
        };
    }
    map_commit_error(operation, error)
}

pub(crate) fn project_dispatch_result(
    result: domain::RoutedResult<super::dispatch::WriteReceipt>,
    operation: super::BridgeWriteOperation,
    expected: BridgeConnectionMode,
) -> Result<BridgeWriteCommitResult, BridgeError> {
    match result {
        Ok(value) => {
            let (resolution, success, message, cgyy, ygdk, evaluation) =
                super::dispatch::project(value, operation);
            finish_commit_success(
                operation,
                resolution.mode.into(),
                success,
                message,
                cgyy,
                ygdk,
                evaluation,
            )
        }
        Err(error) => Err(map_dispatch_error(operation, expected, error)),
    }
}
