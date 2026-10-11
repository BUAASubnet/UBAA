//! 学校结果与本地失效结果分别返回；不改变一次性提交和原资格读取。
use super::{BridgeEvaluationCourseOutcome, BridgeWriteCommitResult, PendingWrite};
use crate::api::client::{
    BridgeClient, BridgeConnectionMode, BridgeError, BridgeErrorCode, BridgeErrorKind,
};
use crate::api::offline::{BridgeCacheFailure, BridgeOfflineCache};
use ubaa_core::facade as core;

/// result/error恰有一项；本地错误不替代学校成功、失败或未知结果。
#[derive(Clone, Debug)]
pub struct BridgeCachedWriteCommit {
    pub result: Option<BridgeWriteCommitResult>,
    pub error: Option<BridgeError>,
    pub cache_error: Option<BridgeCacheFailure>,
    /// 结果投影完成后才确认此提示；未知结果不得自动清理。
    pub readback_hint_id: Option<String>,
}
impl BridgeClient {
    /// 复用原意图消费、实时资格与单次发送；释放原客户端锁前完成关联本地失效。
    ///
    /// # Errors
    /// 发送前意图、路线、客户端或资格验证错误保持原错误；提交结果与本地故障分列。
    pub async fn commit_write_cached(
        &self,
        cache: &BridgeOfflineCache,
        intent_id: String,
    ) -> Result<BridgeCachedWriteCommit, BridgeError> {
        self.commit_write_scoped(Some(cache), intent_id).await
    }
}
impl PendingWrite {
    pub(super) fn cache_impact(&self) -> core::CacheInvalidation {
        match self {
            Self::BykcSelect(v) | Self::BykcDeselect(v) => core::CacheInvalidation::Bykc {
                course_id: v.course_id,
            },
            Self::BykcSign(v) => core::CacheInvalidation::Bykc {
                course_id: v.course_id,
            },
            Self::Signin(_) => core::CacheInvalidation::signin_today(),
            Self::LibbookReserve(v) => core::CacheInvalidation::LibBook {
                day: Some(v.day.clone()),
                area_id: Some(v.area_id.clone()),
            },
            Self::LibbookCancel(_) => core::CacheInvalidation::LibBook {
                day: None,
                area_id: None,
            },
            Self::CgyyReserve(v) => core::CacheInvalidation::Cgyy {
                site_id: Some(v.venue_site_id),
                date: Some(v.reservation_date.clone()),
                order_id: None,
            },
            Self::CgyyCancel(v) => core::CacheInvalidation::Cgyy {
                site_id: None,
                date: None,
                order_id: Some(v.order_id),
            },
            Self::Ygdk(v) => core::CacheInvalidation::Ygdk {
                classify_id: v.target.classify_id,
            },
            Self::Evaluation(_) => core::CacheInvalidation::Evaluation,
        }
    }
}

pub(super) fn may_have_changed(value: &Result<BridgeWriteCommitResult, BridgeError>) -> bool {
    match value {
        Ok(result) => {
            result.success
                || result.outcome_unknown
                || result.evaluation_result.as_ref().is_some_and(|batch| {
                    batch.items.iter().any(|item| {
                        matches!(
                            item.outcome,
                            BridgeEvaluationCourseOutcome::Success
                                | BridgeEvaluationCourseOutcome::OutcomeUnknown
                        )
                    })
                })
        }
        Err(error) => error.code == BridgeErrorCode::OutcomeUnknown,
    }
}

pub(super) async fn finish_cached_commit(
    cache: Option<&BridgeOfflineCache>,
    impact: core::CacheInvalidation,
    prepared_route: BridgeConnectionMode,
    result: Result<BridgeWriteCommitResult, BridgeError>,
) -> BridgeCachedWriteCommit {
    let route = match &result {
        Ok(value) => value.resolved_route,
        Err(error) => error.resolved_route,
    }
    .unwrap_or(prepared_route);
    let cache_error = if may_have_changed(&result)
        && let Some(cache) = cache
    {
        let cache = cache.cache.clone();
        // 原客户端锁由调用方继续持有，SQLite在阻塞池中完成，不阻塞运行时线程。
        match tokio::task::spawn_blocking(move || cache.invalidate(route.into(), &impact)).await {
            Ok(Ok(_)) => None,
            Ok(Err(error)) => Some(error.into()),
            Err(_) => Some(BridgeCacheFailure::Unavailable),
        }
    } else {
        None
    };
    match result {
        Ok(result) => BridgeCachedWriteCommit {
            result: Some(result),
            error: None,
            cache_error,
            readback_hint_id: None,
        },
        Err(error) => BridgeCachedWriteCommit {
            result: None,
            error: Some(error),
            cache_error,
            readback_hint_id: None,
        },
    }
}

impl BridgeCachedWriteCommit {
    #[flutter_rust_bridge::frb(ignore)]
    pub(super) fn into_legacy(self) -> Result<BridgeWriteCommitResult, BridgeError> {
        match (self.result, self.error) {
            (Some(result), None) => Ok(result),
            (None, Some(error)) => Err(error),
            _ => Err(BridgeError::local(
                BridgeErrorCode::OutcomeUnknown,
                BridgeErrorKind::Internal,
                false,
                "写入结果无法确认",
            )),
        }
    }
}
