//! 当前目标详情复用前置扫描；独立票据约束从开始到正文完成的整个读取。
use super::{
    CacheCompleteness, CacheError, CachePayload, CachePublication, CacheQuery, CacheReadTicket,
    CacheScope, ErrorKind, HomeReadData, HomeRefresh, OfflineCache, OfflineReadError,
    OfflineRefresh, RouteResolution, SpocScan, SpocScanCancellation, UbaaClient,
};
use crate::facade::{ErrorCode, RoutedError, SpocAssignmentDetail, UbaaError};
pub struct SpocDetailScan {
    list: SpocScan,
    assignment_id: String,
    ticket: Option<CacheReadTicket>,
    save_error: Option<CacheError>,
    finished: bool,
}
pub struct SpocDetailScanBatch {
    pub resolution: RouteResolution,
    pub data: Option<SpocAssignmentDetail>,
    pub completed_pages: u32,
    pub fetched_at: i64,
    pub finished: bool,
    pub complete: bool,
    pub publication: Option<CachePublication>,
    pub save_error: Option<CacheError>,
}
impl SpocDetailScan {
    #[must_use]
    pub fn cancellation(&self) -> SpocScanCancellation {
        self.list.cancellation()
    }
    fn scope(&self) -> CacheScope {
        CacheScope {
            route: self.list.resolution.mode,
            query: CacheQuery::SpocDetail {
                assignment_id: self.assignment_id.clone(),
            },
        }
    }
    fn storage<T>(
        &mut self,
        result: crate::facade::CacheResult<T>,
    ) -> Result<Option<T>, OfflineReadError> {
        match result {
            Ok(value) => Ok(Some(value)),
            Err(error @ (CacheError::Inactive | CacheError::Superseded)) => {
                Err(OfflineReadError::Cache(error))
            }
            Err(error) => {
                self.save_error = Some(error);
                self.ticket = None;
                Ok(None)
            }
        }
    }
    fn batch(
        &self,
        data: Option<SpocAssignmentDetail>,
        complete: bool,
        publication: Option<CachePublication>,
    ) -> SpocDetailScanBatch {
        SpocDetailScanBatch {
            resolution: self.list.resolution,
            data,
            completed_pages: self.list.next_page - 1,
            fetched_at: self.list.fetched_at,
            finished: self.finished,
            complete,
            publication,
            save_error: self.save_error,
        }
    }
}
impl UbaaClient {
    /// 先核对本机身份，再以独立详情票据建立已观察列表的分段前置。
    ///
    /// # Errors
    /// 无效目标、身份、已退出仓库或所需会话失败拒绝创建计划。
    pub async fn begin_spoc_detail_scan(
        &mut self,
        cache: Option<&OfflineCache>,
        expected_identity: Option<&str>,
        assignment_id: &str,
    ) -> Result<SpocDetailScan, OfflineReadError> {
        CacheScope {
            route: crate::facade::ConnectionMode::Direct,
            query: CacheQuery::SpocDetail {
                assignment_id: assignment_id.into(),
            },
        }
        .validate()
        .map_err(OfflineReadError::Cache)?;
        let list = self.begin_spoc_scan(cache, expected_identity).await?;
        let mut plan = SpocDetailScan {
            list,
            assignment_id: assignment_id.into(),
            ticket: None,
            save_error: None,
            finished: false,
        };
        if let Some(cache) = cache {
            plan.ticket = plan.storage(cache.begin(plan.scope()))?;
        }
        Ok(plan)
    }
    fn validate_spoc_detail(&mut self, plan: &mut SpocDetailScan) -> Result<(), OfflineReadError> {
        self.validate_spoc_owner(&plan.list)?;
        if plan.finished {
            return Err(OfflineReadError::Cache(CacheError::Superseded));
        }
        if let Some(cache) = &plan.list.cache {
            let result = if let Some(ticket) = &plan.ticket {
                cache.validate_read(ticket)
            } else {
                cache.check_read_generation()
            };
            plan.storage(result)?;
        }
        Ok(())
    }
    /// 每次推进一个列表前置；最后一次只读正文及可选提交状态，不重复全量扫描。
    ///
    /// # Errors
    /// 目标缺失、必需正文失败、取消或任何绑定失效终止计划且不覆盖旧完整详情。
    pub async fn next_spoc_detail_scan(
        &mut self,
        plan: &mut SpocDetailScan,
    ) -> Result<SpocDetailScanBatch, OfflineReadError> {
        let result = self.advance_spoc_detail(plan).await;
        if result.is_err() {
            plan.cancellation().cancel();
            if let (Some(cache), Some(ticket)) = (&plan.list.cache, &plan.ticket) {
                cache.failure(ticket, chrono::Utc::now().timestamp());
            }
        }
        result
    }
    async fn advance_spoc_detail(
        &mut self,
        plan: &mut SpocDetailScan,
    ) -> Result<SpocDetailScanBatch, OfflineReadError> {
        self.validate_spoc_detail(plan)?;
        if let (Some(cache), Some(ticket)) = (&plan.list.cache, &mut plan.ticket) {
            let result = cache.repository(|repo| repo.renew_read(ticket));
            plan.storage(result)?;
        }
        if !plan.list.finished {
            self.next_spoc_scan(&mut plan.list).await?;
            self.validate_spoc_detail(plan)?;
            return Ok(plan.batch(None, false, None));
        }
        let resolution = plan.list.resolution;
        let base = plan
            .list
            .data
            .assignments
            .iter()
            .find(|row| row.assignment_id == plan.assignment_id)
            .ok_or_else(|| {
                OfflineReadError::Read(RoutedError {
                    resolution: Some(resolution),
                    error: UbaaError::new(
                        ErrorCode::UpstreamChanged,
                        ErrorKind::Upstream,
                        false,
                        "未找到 SPOC 作业",
                    ),
                })
            })?;
        let result = crate::features::spoc::get_assignment_detail_for_base(
            self.runtime_for(resolution.mode),
            base,
        )
        .await;
        let (data, detail_complete) = self
            .finish_routed(resolution, result)
            .map_err(OfflineReadError::Read)?
            .data;
        self.validate_spoc_detail(plan)?;
        let complete = plan.list.complete && detail_complete;
        let mut publication = None;
        if let (Some(cache), Some(ticket)) = (&plan.list.cache, &plan.ticket) {
            let result = cache.repository(|repo| {
                repo.publish(
                    ticket,
                    CachePayload::SpocDetail(Box::new(data.clone())),
                    plan.list.fetched_at,
                    if complete {
                        CacheCompleteness::Complete
                    } else {
                        CacheCompleteness::Partial
                    },
                )
            });
            publication = plan.storage(result)?;
        }
        plan.finished = true;
        Ok(plan.batch(Some(data), complete, publication))
    }
    pub(in crate::facade) async fn refresh_spoc_detail_scan(
        &mut self,
        cache: &OfflineCache,
        assignment_id: &str,
    ) -> Result<HomeRefresh, OfflineReadError> {
        let mut plan = self
            .begin_spoc_detail_scan(Some(cache), None, assignment_id)
            .await?;
        loop {
            let value = self.next_spoc_detail_scan(&mut plan).await?;
            if let Some(data) = value.data {
                return Ok(HomeRefresh {
                    result: OfflineRefresh {
                        data: HomeReadData::SpocDetail(data),
                        scope: plan.scope(),
                        resolution: value.resolution,
                        fetched_at: value.fetched_at,
                        save_error: value.save_error,
                    },
                    complete: value.complete,
                    publication: value.publication,
                });
            }
        }
    }
}
