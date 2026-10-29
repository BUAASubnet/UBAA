//! 详情前置按页让位，最后有界正文批次仍由原 Core 认证及会话仲裁管理。
use crate::api::{
    client::{BridgeClient, BridgeError, catch_panic, disposed_error, map_route},
    offline::{BridgeOfflineCache, offline_read_error},
    offline_home::BridgeHomeRefreshState,
    read::{BridgeRoutedSpocAssignmentDetail, map_spoc_detail},
};
use ubaa_core::facade as core;
pub struct BridgeSpocDetailScan {
    plan: tokio::sync::Mutex<core::SpocDetailScan>,
    cancellation: core::SpocScanCancellation,
}
impl BridgeSpocDetailScan {
    /// 只取消尚未开始的批次和迟到发布，不打断既有请求的会话收尾。
    #[flutter_rust_bridge::frb(sync)]
    pub fn cancel(&self) {
        self.cancellation.cancel();
    }
}
#[derive(Clone, Debug)]
pub struct BridgeSpocDetailScanBatch {
    pub result: Option<BridgeRoutedSpocAssignmentDetail>,
    pub state: BridgeHomeRefreshState,
    pub completed_pages: u32,
    pub finished: bool,
}
impl BridgeClient {
    async fn begin_spoc_detail_plan(
        &self,
        cache: Option<&BridgeOfflineCache>,
        expected_identity: Option<String>,
        assignment_id: String,
    ) -> Result<BridgeSpocDetailScan, BridgeError> {
        catch_panic(async {
            let mut guard = self
                .inner
                .read(Some(crate::api::read_pool::ReadGroup::Spoc))
                .await?;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            self.ensure_recovery_allowed().await?;
            let plan = client
                .begin_spoc_detail_scan(
                    cache.map(|cache| &cache.cache),
                    expected_identity.as_deref(),
                    &assignment_id,
                )
                .await
                .map_err(offline_read_error)?;
            let cancellation = plan.cancellation();
            Ok(BridgeSpocDetailScan {
                plan: tokio::sync::Mutex::new(plan),
                cancellation,
            })
        })
        .await
    }
    /// 建立精确作业的持久详情计划，前置读取分段推进。
    ///
    /// # Errors
    /// 目标、身份、已退出仓库与待确认写意图失败保持稳定分类。
    pub async fn begin_spoc_detail_scan(
        &self,
        cache: &BridgeOfflineCache,
        assignment_id: String,
    ) -> Result<BridgeSpocDetailScan, BridgeError> {
        self.begin_spoc_detail_plan(Some(cache), None, assignment_id)
            .await
    }
    /// 本地密钥不可用时仍核对本机身份，不退回长时间占锁的聚合入口。
    ///
    /// # Errors
    /// 无效目标、身份、所需会话或写意图冲突拒绝创建计划。
    pub async fn begin_spoc_detail_online(
        &self,
        expected_identity: Option<String>,
        assignment_id: String,
    ) -> Result<BridgeSpocDetailScan, BridgeError> {
        self.begin_spoc_detail_plan(None, expected_identity, assignment_id)
            .await
    }
    /// 一次完成单个前置或最终正文/提交状态补充；返回后释放原客户端锁。
    ///
    /// # Errors
    /// 取消、身份/路线失效、学校异常或写意图冲突拒绝继续。
    pub async fn next_spoc_detail_scan(
        &self,
        task: &BridgeSpocDetailScan,
    ) -> Result<BridgeSpocDetailScanBatch, BridgeError> {
        catch_panic(async {
            let mut plan = task.plan.lock().await;
            let mut guard = self
                .inner
                .read(Some(crate::api::read_pool::ReadGroup::Spoc))
                .await?;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            self.ensure_recovery_allowed().await?;
            let batch = client
                .next_spoc_detail_scan(&mut plan)
                .await
                .map_err(offline_read_error)?;
            Ok(BridgeSpocDetailScanBatch {
                result: batch.data.map(|data| BridgeRoutedSpocAssignmentDetail {
                    data: map_spoc_detail(data),
                    route: map_route(batch.resolution),
                }),
                state: BridgeHomeRefreshState {
                    fetched_at: batch.fetched_at,
                    complete: batch.complete,
                    saved_for_offline: batch.publication == Some(core::CachePublication::Stored),
                    preserved_previous: batch.publication
                        == Some(core::CachePublication::Preserved),
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
