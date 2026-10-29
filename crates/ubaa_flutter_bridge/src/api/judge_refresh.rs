//! 持久刷新计划逐批穿过 FFI；不在 Bridge 内自动启动下一批。
pub mod details;
use super::client::{BridgeClient, BridgeError, catch_panic, disposed_error};
use super::judge_scan::{BridgeJudgeScanBatch, map_scan_batch};
use super::offline::{BridgeCacheFailure, BridgeOfflineCache, offline_read_error};
use super::read::{BridgeJudgeAssignmentKey, BridgeJudgeAssignmentSummary, map_judge_summaries};
use ubaa_core::facade as core;

#[derive(Clone, Debug, Default)]
pub struct BridgeJudgeRefreshOptions {
    pub include_expired: bool,
    pub full_refresh: bool,
    pub preferred_course: Option<String>,
    pub current_assignment: Option<BridgeJudgeAssignmentKey>,
}
pub struct BridgeJudgeRefreshTask {
    plan: tokio::sync::Mutex<core::JudgeRefresh>,
    cancellation: core::JudgeScanCancellation,
}
impl BridgeJudgeRefreshTask {
    /// 设置取消标记；不声明已中止正在进行的学校请求。
    #[flutter_rust_bridge::frb(sync)]
    pub fn cancel(&self) {
        self.cancellation.cancel();
    }
}
#[derive(Clone, Debug)]
pub struct BridgeJudgeProgress {
    pub batch: BridgeJudgeScanBatch,
    pub summaries: Vec<BridgeJudgeAssignmentSummary>,
    pub summary_fetched_at: i64,
    pub summary_has_cached: bool,
    pub source_fetched_at: Option<i64>,
    pub reused: bool,
    pub save_error: Option<BridgeCacheFailure>,
}
impl BridgeClient {
    /// 创建持久刷新计划；仅执行身份核实与课程索引步骤。
    ///
    /// # Errors
    /// 学校读取、账号栅栏、待确认写意图或客户端失效时返回稳定错误。
    pub async fn begin_judge_refresh(
        &self,
        cache: &BridgeOfflineCache,
        options: BridgeJudgeRefreshOptions,
    ) -> Result<BridgeJudgeRefreshTask, BridgeError> {
        catch_panic(async {
            let mut guard = self
                .inner
                .read(Some(crate::api::read_pool::ReadGroup::Judge))
                .await?;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            self.ensure_recovery_allowed().await?;
            let requested_course = options
                .current_assignment
                .as_ref()
                .map(|key| key.course_id.clone());
            let plan = client
                .begin_judge_refresh(
                    &cache.cache,
                    core::JudgeRefreshOptions {
                        include_expired: options.include_expired,
                        full_refresh: options.full_refresh,
                        preferred_course: options.preferred_course,
                        current_assignment: options.current_assignment.map(|key| {
                            core::JudgeAssignmentKey {
                                course_id: key.course_id,
                                assignment_id: key.assignment_id,
                            }
                        }),
                    },
                )
                .await
                .map_err(offline_read_error)?;
            if requested_course
                .as_ref()
                .is_some_and(|id| !plan.courses().iter().any(|course| &course.course_id == id))
            {
                return Err(BridgeError::from_core(
                    core::UbaaError::new(
                        core::ErrorCode::InvalidInput,
                        core::ErrorKind::Input,
                        false,
                        "当前课程列表未找到目标课程",
                    ),
                    Some(plan.resolution().mode.into()),
                ));
            }
            let cancellation = plan.cancellation();
            Ok(BridgeJudgeRefreshTask {
                plan: tokio::sync::Mutex::new(plan),
                cancellation,
            })
        })
        .await
    }
    /// 返回一批渐进结果后归还共享锁；缓存来源时间与同步完整度独立传递。
    ///
    /// # Errors
    /// 取消、账号/路线变化、写活动冲突或认证仲裁失败时停止旧计划。
    pub async fn next_judge_refresh(
        &self,
        task: &BridgeJudgeRefreshTask,
    ) -> Result<BridgeJudgeProgress, BridgeError> {
        catch_panic(async {
            let mut plan = task.plan.lock().await;
            let mut guard = self
                .inner
                .read(Some(crate::api::read_pool::ReadGroup::Judge))
                .await?;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            self.ensure_recovery_allowed().await?;
            let value = client
                .next_judge_refresh(&mut plan)
                .await
                .map_err(offline_read_error)?;
            Ok(BridgeJudgeProgress {
                batch: map_scan_batch(core::Routed {
                    data: value.batch,
                    resolution: value.resolution,
                }),
                summaries: map_judge_summaries(value.summaries),
                summary_fetched_at: value.summary_fetched_at,
                summary_has_cached: value.summary_has_cached,
                source_fetched_at: value.fetched_at,
                reused: value.reused,
                save_error: value.save_error.map(Into::into),
            })
        })
        .await
    }
}
