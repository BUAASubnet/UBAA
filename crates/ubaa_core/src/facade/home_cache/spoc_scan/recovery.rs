//! 同查询读取竞争只恢复一次，账号和会话失效仍由原扫描栅栏拒绝。
use super::{
    CacheCompleteness, CacheError, CachePayload, CachePublication, OfflineReadError, SpocScan,
    SpocScanBatch, UbaaClient,
};

impl UbaaClient {
    pub(super) async fn recover_spoc_scan(
        &mut self,
        plan: &mut SpocScan,
    ) -> Result<SpocScanBatch, OfflineReadError> {
        self.validate_spoc_owner(plan)?;
        let cache = plan
            .cache
            .clone()
            .ok_or(OfflineReadError::Cache(CacheError::Superseded))?;
        let old = plan
            .ticket
            .as_ref()
            .ok_or(OfflineReadError::Cache(CacheError::Superseded))?;
        let (ticket, record) = cache
            .repository(|repo| repo.recover_readonly_scan(old))
            .map_err(OfflineReadError::Cache)?;
        if let Some(record) = record {
            let CachePayload::SpocSelection { term } = record.payload else {
                return Err(OfflineReadError::Cache(CacheError::Corrupt));
            };
            let aggregate = cache
                .read(
                    &super::super::spoc::term_scope(record.scope.route, &term),
                    chrono::Utc::now().timestamp(),
                )
                .map_err(OfflineReadError::Cache)?
                .ok_or(OfflineReadError::Cache(CacheError::Superseded))?;
            let CachePayload::SpocAssignments(data) = aggregate.payload else {
                return Err(OfflineReadError::Cache(CacheError::Corrupt));
            };
            plan.data = data;
            plan.fetched_at = aggregate.fetched_at;
            plan.complete = aggregate.completeness == CacheCompleteness::Complete;
            plan.finished = true;
            plan.resolution.mode = aggregate.scope.route;
            return Ok(plan.batch(Some(CachePublication::Stored)));
        }
        let cancellation = plan.cancellation.clone();
        let mut replacement = self
            .begin_spoc_scan_with_ticket(Some(&cache), None, Some(ticket))
            .await?;
        self.validate_spoc_owner(plan)?;
        replacement.cancellation = cancellation;
        *plan = replacement;
        // 一次调用内完成这次重读，避免两个正常调度的读取在批次间反复互相替代。
        loop {
            let batch = self.advance_spoc_scan(plan).await?;
            if batch.finished {
                return Ok(batch);
            }
        }
    }
}
