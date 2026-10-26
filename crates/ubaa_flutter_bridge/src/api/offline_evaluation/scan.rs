//! 评教只读逐批接线，不拆分 prepare/commit 所需的新鲜写授权事务。
use crate::api::{
    client::{BridgeClient, BridgeError, catch_panic, disposed_error, map_route},
    offline::{BridgeOfflineCache, offline_read_error},
    offline_evaluation::BridgeEvaluationRefresh,
    read::map_evaluation,
};
use ubaa_core::facade as core;
pub struct BridgeEvaluationScan {
    plan: tokio::sync::Mutex<core::EvaluationScan>,
    cancellation: core::EvaluationScanCancellation,
}
impl BridgeEvaluationScan {
    /// 拒绝后续批次和迟到发布，已发送请求按原会话收尾。
    #[flutter_rust_bridge::frb(sync)]
    pub fn cancel(&self) {
        self.cancellation.cancel();
    }
}
#[derive(Clone, Debug)]
pub struct BridgeEvaluationScanBatch {
    pub refresh: BridgeEvaluationRefresh,
    pub completed_course_lists: u32,
    pub finished: bool,
    pub error: Option<BridgeError>,
}
impl BridgeClient {
    async fn begin_evaluation_plan(
        &self,
        cache: Option<&BridgeOfflineCache>,
        expected_identity: Option<String>,
    ) -> Result<BridgeEvaluationScan, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            self.ensure_recovery_allowed().await?;
            let plan = client
                .begin_evaluation_scan(
                    cache.map(|cache| &cache.cache),
                    expected_identity.as_deref(),
                )
                .await
                .map_err(offline_read_error)?;
            let cancellation = plan.cancellation();
            Ok(BridgeEvaluationScan {
                plan: tokio::sync::Mutex::new(plan),
                cancellation,
            })
        })
        .await
    }
    /// 核实账号后登记当前任务固定页的只读缓存计划。
    ///
    /// # Errors
    /// 身份、会话、已退出缓存与待确认写意图保持原稳定错误。
    pub async fn begin_evaluation_scan(
        &self,
        cache: &BridgeOfflineCache,
    ) -> Result<BridgeEvaluationScan, BridgeError> {
        self.begin_evaluation_plan(Some(cache), None).await
    }
    /// 无缓存时也按已知本机账号核对身份，并在每个业务请求后让位。
    ///
    /// # Errors
    /// 账号、会话或待确认写意图失败不创建计划。
    pub async fn begin_evaluation_online(
        &self,
        expected_identity: Option<String>,
    ) -> Result<BridgeEvaluationScan, BridgeError> {
        self.begin_evaluation_plan(None, expected_identity).await
    }
    /// 仅推进激活或一个任务/问卷/课程请求，完成后释放同一客户端共享锁。
    ///
    /// # Errors
    /// 取消、会话/路线/客户端失效或写意图冲突时拒绝继续。
    pub async fn next_evaluation_scan(
        &self,
        task: &BridgeEvaluationScan,
    ) -> Result<BridgeEvaluationScanBatch, BridgeError> {
        catch_panic(async {
            let mut plan = task.plan.lock().await;
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            self.ensure_recovery_allowed().await?;
            let batch = client
                .next_evaluation_scan(&mut plan)
                .await
                .map_err(offline_read_error)?;
            Ok(BridgeEvaluationScanBatch {
                refresh: BridgeEvaluationRefresh {
                    data: map_evaluation(batch.data),
                    route: map_route(batch.resolution),
                    fetched_at: batch.fetched_at,
                    complete: batch.complete,
                    saved_for_offline: batch.publication == Some(core::CachePublication::Stored),
                    preserved_previous: !batch.finished
                        || batch.publication == Some(core::CachePublication::Preserved),
                    save_error: batch.save_error.map(Into::into),
                },
                completed_course_lists: batch.completed_course_lists,
                finished: batch.finished,
                error: batch.error.map(BridgeError::from_routed),
            })
        })
        .await
    }
}

#[cfg(test)]
mod tests;
