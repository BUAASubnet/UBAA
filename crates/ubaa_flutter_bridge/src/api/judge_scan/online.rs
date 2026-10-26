//! 无持久缓存计划仍在同一客户端锁中执行一批，返回后由宿主调度下一批。
use crate::api::client::{BridgeClient, BridgeError, catch_panic, disposed_error};
use crate::api::judge_scan::{BridgeJudgeScanBatch, map_scan_batch};
use crate::api::offline::offline_read_error;
use crate::api::read::{
    BridgeJudgeAssignmentKey, BridgeJudgeAssignmentSummary, map_judge_summaries,
};
use ubaa_core::facade as core;

#[derive(Clone, Default)]
pub struct BridgeJudgeOnlineOptions {
    pub include_expired: bool,
    pub expected_identity: Option<String>,
    pub preferred_course: Option<String>,
    pub keys: Option<Vec<BridgeJudgeAssignmentKey>>,
}
pub struct BridgeJudgeOnlineTask {
    plan: tokio::sync::Mutex<core::JudgeOnlineScan>,
    cancellation: core::JudgeScanCancellation,
}
impl BridgeJudgeOnlineTask {
    /// 只设置取消标记，不抢占已发送请求。
    #[flutter_rust_bridge::frb(sync)]
    pub fn cancel(&self) {
        self.cancellation.cancel();
    }
}
#[derive(Clone, Debug)]
pub struct BridgeJudgeOnlineProgress {
    pub batch: BridgeJudgeScanBatch,
    pub summaries: Vec<BridgeJudgeAssignmentSummary>,
    pub fetched_at: i64,
}
impl BridgeClient {
    /// 新计划不依赖数据库；可选本机身份仍由Core核对。
    ///
    /// # Errors
    /// 目标、身份、学校读取、待确认写意图与失效客户端返回既有稳定错误。
    pub async fn begin_judge_online(
        &self,
        options: BridgeJudgeOnlineOptions,
    ) -> Result<BridgeJudgeOnlineTask, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            self.ensure_recovery_allowed().await?;
            let plan = client
                .begin_judge_online(core::JudgeOnlineOptions {
                    include_expired: options.include_expired,
                    expected_identity: options.expected_identity,
                    preferred_course: options.preferred_course,
                    keys: options.keys.map(|keys| {
                        keys.into_iter()
                            .map(|key| core::JudgeAssignmentKey {
                                course_id: key.course_id,
                                assignment_id: key.assignment_id,
                            })
                            .collect()
                    }),
                })
                .await
                .map_err(offline_read_error)?;
            let cancellation = plan.cancellation();
            Ok(BridgeJudgeOnlineTask {
                plan: tokio::sync::Mutex::new(plan),
                cancellation,
            })
        })
        .await
    }
    /// 完整索引或详情步骤结束后释放原共享锁，不自动推进剩余请求。
    ///
    /// # Errors
    /// 原客户端/路线/会话代次失效、取消和写意图冲突时拒绝继续。
    pub async fn next_judge_online(
        &self,
        task: &BridgeJudgeOnlineTask,
    ) -> Result<BridgeJudgeOnlineProgress, BridgeError> {
        catch_panic(async {
            let mut plan = task.plan.lock().await;
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            self.ensure_recovery_allowed().await?;
            let value = client
                .next_judge_online(&mut plan)
                .await
                .map_err(offline_read_error)?;
            Ok(BridgeJudgeOnlineProgress {
                batch: map_scan_batch(core::Routed {
                    data: value.batch,
                    resolution: value.resolution,
                }),
                summaries: map_judge_summaries(value.summaries),
                fetched_at: value.fetched_at,
            })
        })
        .await
    }
}
