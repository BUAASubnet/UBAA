//! 批量详情逐项发布，复用原客户端与取消规则。
use super::{
    BridgeClient, BridgeError, BridgeJudgeAssignmentKey, BridgeJudgeProgress, BridgeOfflineCache,
    catch_panic, core, disposed_error, map_judge_summaries, map_scan_batch, offline_read_error,
};

pub struct BridgeJudgeDetailsTask {
    plan: tokio::sync::Mutex<core::JudgeDetailsRead>,
    cancellation: core::JudgeScanCancellation,
}
impl BridgeJudgeDetailsTask {
    /// 取消后续批次；在途响应仍由原客户端及缓存票据拒绝。
    #[flutter_rust_bridge::frb(sync)]
    pub fn cancel(&self) {
        self.cancellation.cancel();
    }
}
impl BridgeClient {
    /// 对明确批量目标创建独立缓存详情计划，不覆盖全量摘要。
    ///
    /// # Errors
    /// 目标、身份、存储或学校错误保持既有分类，待确认写意图禁止开始。
    pub async fn begin_judge_details(
        &self,
        cache: &BridgeOfflineCache,
        keys: Vec<BridgeJudgeAssignmentKey>,
    ) -> Result<BridgeJudgeDetailsTask, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            self.ensure_recovery_allowed().await?;
            let plan = client
                .begin_judge_details(
                    &cache.cache,
                    keys.into_iter()
                        .map(|key| core::JudgeAssignmentKey {
                            course_id: key.course_id,
                            assignment_id: key.assignment_id,
                        })
                        .collect(),
                )
                .await
                .map_err(offline_read_error)?;
            let cancellation = plan.cancellation();
            Ok(BridgeJudgeDetailsTask {
                plan: tokio::sync::Mutex::new(plan),
                cancellation,
            })
        })
        .await
    }
    /// 仅处理一批学校只读，在线完整度与本地保存分别返回。
    ///
    /// # Errors
    /// 清理、退出、取消、较新同目标读取和学校认证失败停止旧计划。
    pub async fn next_judge_details(
        &self,
        task: &BridgeJudgeDetailsTask,
    ) -> Result<BridgeJudgeProgress, BridgeError> {
        catch_panic(async {
            let mut plan = task.plan.lock().await;
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            self.ensure_recovery_allowed().await?;
            let value = client
                .next_judge_details(&mut plan)
                .await
                .map_err(offline_read_error)?;
            let progress = value.progress;
            Ok(BridgeJudgeProgress {
                batch: map_scan_batch(core::Routed {
                    data: progress.batch,
                    resolution: progress.resolution,
                }),
                summaries: map_judge_summaries(progress.summaries),
                summary_fetched_at: progress.fetched_at,
                source_fetched_at: Some(progress.fetched_at),
                summary_has_cached: false,
                reused: false,
                save_error: value.save_error.map(Into::into),
            })
        })
        .await
    }
}
