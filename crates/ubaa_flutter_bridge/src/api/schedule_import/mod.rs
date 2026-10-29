//! 整学期导入逐批归还原客户端共享锁，不复制 Cookie 或持久会话。
use super::client::{
    BridgeClient, BridgeError, BridgeRouteDecision, catch_panic, disposed_error, map_route,
};
use super::offline::{BridgeCacheFailure, BridgeOfflineCache, cache_error, offline_read_error};
use ubaa_core::facade as core;

pub struct BridgeScheduleImportTask {
    plan: tokio::sync::Mutex<core::ScheduleImport>,
    cancellation: core::ScheduleImportCancellation,
}
impl BridgeScheduleImportTask {
    /// 阻止后续批次和保存；正在进行的只读请求仍完成原会话收尾。
    #[flutter_rust_bridge::frb(sync)]
    pub fn cancel(&self) {
        self.cancellation.cancel();
    }
}
#[derive(Clone, Debug)]
pub struct BridgeScheduleImportProgress {
    pub term_code: String,
    pub completed_weeks: u32,
    pub total_weeks: Option<u32>,
    pub finished: bool,
    pub save_error: Option<BridgeCacheFailure>,
    pub route: BridgeRouteDecision,
}
impl BridgeClient {
    /// 核实原会话身份并登记指定学期导入，不自动开始逐周读取。
    ///
    /// # Errors
    /// 账号、仓库、学校认证或待确认写意图冲突时拒绝创建计划。
    pub async fn begin_schedule_import(
        &self,
        cache: &BridgeOfflineCache,
        term: String,
    ) -> Result<BridgeScheduleImportTask, BridgeError> {
        catch_panic(async {
            let mut guard = self
                .inner
                .read(Some(crate::api::read_pool::ReadGroup::Academic))
                .await?;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            self.ensure_recovery_allowed().await?;
            let plan = client
                .begin_schedule_import(&cache.cache, &term)
                .await
                .map_err(offline_read_error)?;
            let cancellation = plan.cancellation();
            Ok(BridgeScheduleImportTask {
                plan: tokio::sync::Mutex::new(plan),
                cancellation,
            })
        })
        .await
    }
    /// 返回学期索引、周次索引或单周进度后释放共享锁。
    ///
    /// # Errors
    /// 取消、退出、路线/会话变化、学校读取或当前写活动冲突时返回稳定错误。
    pub async fn next_schedule_import(
        &self,
        task: &BridgeScheduleImportTask,
    ) -> Result<BridgeScheduleImportProgress, BridgeError> {
        catch_panic(async {
            let mut plan = task.plan.lock().await;
            let mut guard = self
                .inner
                .read(Some(crate::api::read_pool::ReadGroup::Academic))
                .await?;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            self.ensure_recovery_allowed().await?;
            let result = client
                .next_schedule_import(&mut plan)
                .await
                .map_err(offline_read_error)?;
            let data = result.data;
            let count = |value| {
                u32::try_from(value).map_err(|_| cache_error(core::CacheError::InvalidInput))
            };
            Ok(BridgeScheduleImportProgress {
                term_code: data.term_code,
                completed_weeks: count(data.completed_weeks)?,
                total_weeks: data.total_weeks.map(count).transpose()?,
                finished: data.finished,
                save_error: data.save_error.map(Into::into),
                route: map_route(result.resolution),
            })
        })
        .await
    }
}
#[cfg(test)]
mod tests;
