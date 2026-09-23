//! 最小重启核对线索；不恢复 opaque 意图或学校提交资格。
use super::{BridgeWriteCommitResult, BridgeWriteOperation};
use crate::api::client::{BridgeConnectionMode, BridgeError, BridgeErrorCode};
use crate::api::offline::{BridgeCacheFailure, BridgeOfflineCache, cache_error, local_task};
use ubaa_core::facade as core;

#[derive(Clone, Debug)]
pub struct BridgeWriteReadbackHint {
    pub id: String,
    pub operation: BridgeWriteOperation,
    pub route: BridgeConnectionMode,
    pub started_at: i64,
}

impl BridgeOfflineCache {
    /// 本地核对提示不检查学校会话，也不产生写意图。
    pub async fn write_readback_hints(&self) -> Result<Vec<BridgeWriteReadbackHint>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .write_readback_hints()
                .map(|values| {
                    values
                        .into_iter()
                        .map(|v| BridgeWriteReadbackHint {
                            id: v.id,
                            operation: v.operation.into(),
                            route: v.route.into(),
                            started_at: v.started_at,
                        })
                        .collect()
                })
                .map_err(cache_error)
        })
        .await
    }

    /// 用户核对后移除本地提示，不将学校结果升级为成功。
    pub async fn dismiss_write_readback(&self, id: String) -> Result<(), BridgeError> {
        let cache = self.cache.clone();
        local_task(move || cache.dismiss_write_readback(&id).map_err(cache_error)).await
    }
}

pub(super) async fn begin_hint(
    cache: Option<&BridgeOfflineCache>,
    operation: BridgeWriteOperation,
    route: BridgeConnectionMode,
) -> (
    Option<core::WriteReadbackTicket>,
    Option<BridgeCacheFailure>,
) {
    let Some(cache) = cache else {
        return (None, None);
    };
    let cache = cache.cache.clone();
    match tokio::task::spawn_blocking(move || {
        cache.begin_write_readback(
            operation.into(),
            route.into(),
            super::support::now_seconds(),
        )
    })
    .await
    {
        Ok(Ok(ticket)) => (Some(ticket), None),
        Ok(Err(error)) => (None, Some(error.into())),
        Err(_) => (None, Some(BridgeCacheFailure::Unavailable)),
    }
}

pub(super) async fn finish_hint(
    cache: Option<&BridgeOfflineCache>,
    ticket: Option<core::WriteReadbackTicket>,
    result: &Result<BridgeWriteCommitResult, BridgeError>,
) -> Option<BridgeCacheFailure> {
    let unknown = match result {
        Ok(value) => {
            value.outcome_unknown
                || value.evaluation_result.as_ref().is_some_and(|batch| {
                    batch.items.iter().any(|item| {
                        matches!(
                            item.outcome,
                            super::BridgeEvaluationCourseOutcome::OutcomeUnknown
                        )
                    })
                })
        }
        Err(error) => error.code == BridgeErrorCode::OutcomeUnknown,
    };
    if unknown {
        return None;
    }
    let (Some(cache), Some(ticket)) = (cache, ticket) else {
        return None;
    };
    let cache = cache.cache.clone();
    match tokio::task::spawn_blocking(move || cache.finish_write_readback(&ticket)).await {
        Ok(Ok(())) => None,
        Ok(Err(error)) => Some(error.into()),
        Err(_) => Some(BridgeCacheFailure::Unavailable),
    }
}

impl From<BridgeWriteOperation> for core::WriteReadbackOperation {
    fn from(value: BridgeWriteOperation) -> Self {
        match value {
            BridgeWriteOperation::BykcSelectCourse => Self::BykcSelectCourse,
            BridgeWriteOperation::BykcDeselectCourse => Self::BykcDeselectCourse,
            BridgeWriteOperation::BykcSignCourse => Self::BykcSignCourse,
            BridgeWriteOperation::SigninPerform => Self::SigninPerform,
            BridgeWriteOperation::LibbookReserve => Self::LibbookReserve,
            BridgeWriteOperation::LibbookCancelBooking => Self::LibbookCancelBooking,
            BridgeWriteOperation::YgdkSubmit => Self::YgdkSubmit,
            BridgeWriteOperation::CgyySubmitReservation => Self::CgyySubmitReservation,
            BridgeWriteOperation::CgyyCancelOrder => Self::CgyyCancelOrder,
            BridgeWriteOperation::EvaluationSubmitCourses => Self::EvaluationSubmitCourses,
        }
    }
}
impl From<core::WriteReadbackOperation> for BridgeWriteOperation {
    fn from(value: core::WriteReadbackOperation) -> Self {
        match value {
            core::WriteReadbackOperation::BykcSelectCourse => Self::BykcSelectCourse,
            core::WriteReadbackOperation::BykcDeselectCourse => Self::BykcDeselectCourse,
            core::WriteReadbackOperation::BykcSignCourse => Self::BykcSignCourse,
            core::WriteReadbackOperation::SigninPerform => Self::SigninPerform,
            core::WriteReadbackOperation::LibbookReserve => Self::LibbookReserve,
            core::WriteReadbackOperation::LibbookCancelBooking => Self::LibbookCancelBooking,
            core::WriteReadbackOperation::YgdkSubmit => Self::YgdkSubmit,
            core::WriteReadbackOperation::CgyySubmitReservation => Self::CgyySubmitReservation,
            core::WriteReadbackOperation::CgyyCancelOrder => Self::CgyyCancelOrder,
            core::WriteReadbackOperation::EvaluationSubmitCourses => Self::EvaluationSubmitCourses,
        }
    }
}
