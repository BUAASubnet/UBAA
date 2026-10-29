//! SPOC 摘要每个完整步骤归还同一客户端锁，学校写意图始终优先受保护。
use crate::api::{
    client::{BridgeClient, BridgeError, catch_panic, disposed_error, map_route},
    offline::{BridgeOfflineCache, offline_read_error},
    offline_home::BridgeHomeRefreshState,
    read::{BridgeRoutedSpocAssignments, map_spoc_assignments},
};
use ubaa_core::facade as core;

pub struct BridgeSpocScan {
    plan: tokio::sync::Mutex<core::SpocScan>,
    cancellation: core::SpocScanCancellation,
}
impl BridgeSpocScan {
    /// 只设置取消标记，已发送的只读请求按原会话正常收尾。
    #[flutter_rust_bridge::frb(sync)]
    pub fn cancel(&self) {
        self.cancellation.cancel();
    }
}
#[derive(Clone, Debug)]
pub struct BridgeSpocScanBatch {
    pub result: BridgeRoutedSpocAssignments,
    pub state: BridgeHomeRefreshState,
    pub completed_pages: u32,
    pub finished: bool,
}
impl BridgeClient {
    async fn begin_spoc_plan(
        &self,
        cache: Option<&BridgeOfflineCache>,
        expected_identity: Option<String>,
    ) -> Result<BridgeSpocScan, BridgeError> {
        catch_panic(async {
            let mut guard = self
                .inner
                .read(Some(crate::api::read_pool::ReadGroup::Spoc))
                .await?;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            self.ensure_recovery_allowed().await?;
            let plan = client
                .begin_spoc_scan(
                    cache.map(|cache| &cache.cache),
                    expected_identity.as_deref(),
                )
                .await
                .map_err(offline_read_error)?;
            let cancellation = plan.cancellation();
            Ok(BridgeSpocScan {
                plan: tokio::sync::Mutex::new(plan),
                cancellation,
            })
        })
        .await
    }
    /// 缓存身份与当前会话核对后建立按页读取，不自动推进学校查询。
    ///
    /// # Errors
    /// 原身份、会话、已退出仓库与待确认写意图失败保持稳定分类。
    pub async fn begin_spoc_scan(
        &self,
        cache: &BridgeOfflineCache,
    ) -> Result<BridgeSpocScan, BridgeError> {
        self.begin_spoc_plan(Some(cache), None).await
    }
    /// 缺缓存密钥也能按本机账号核对并逐页读取，不复制认证材料。
    ///
    /// # Errors
    /// 原身份、会话与写意图保护仍有效。
    pub async fn begin_spoc_online(
        &self,
        expected_identity: Option<String>,
    ) -> Result<BridgeSpocScan, BridgeError> {
        self.begin_spoc_plan(None, expected_identity).await
    }
    /// 一次完成当前学期、课程补充或单页读取，返回后不持原客户端锁。
    ///
    /// # Errors
    /// 取消、账号/路线失效、学校异常或写意图冲突拒绝继续。
    pub async fn next_spoc_scan(
        &self,
        task: &BridgeSpocScan,
    ) -> Result<BridgeSpocScanBatch, BridgeError> {
        catch_panic(async {
            let mut plan = task.plan.lock().await;
            let mut guard = self
                .inner
                .read(Some(crate::api::read_pool::ReadGroup::Spoc))
                .await?;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            self.ensure_recovery_allowed().await?;
            let batch = client
                .next_spoc_scan(&mut plan)
                .await
                .map_err(offline_read_error)?;
            Ok(BridgeSpocScanBatch {
                result: BridgeRoutedSpocAssignments {
                    data: map_spoc_assignments(batch.data),
                    route: map_route(batch.resolution),
                },
                state: BridgeHomeRefreshState {
                    fetched_at: batch.fetched_at,
                    complete: batch.complete,
                    saved_for_offline: batch.publication == Some(core::CachePublication::Stored),
                    preserved_previous: !batch.complete,
                    save_error: batch.save_error.map(Into::into),
                    scope_date: None,
                },
                completed_pages: batch.completed_pages,
                finished: batch.finished,
            })
        })
        .await
    }
}

#[cfg(test)]
mod tests;

pub mod detail;
