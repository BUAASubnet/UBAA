//! 只用同一作业正文或已经取得的结果收尾，不重新推进学校读取。
use super::{
    CacheCompleteness, CacheError, CachePayload, CachePublication, CacheReadTicket, OfflineCache,
    OfflineReadError, SpocDetailScan, SpocDetailScanBatch, UbaaClient,
};
use crate::cache::{CacheRecord, CacheResult, SharedReadRecovery};

impl UbaaClient {
    pub(super) fn recover_spoc_detail(
        &mut self,
        plan: &mut SpocDetailScan,
    ) -> Result<SpocDetailScanBatch, OfflineReadError> {
        self.validate_spoc_owner(&plan.list)?;
        let lost = OfflineReadError::Cache(CacheError::Superseded);
        let (Some(cache), Some(ticket)) = (&plan.list.cache, &plan.ticket) else {
            return Err(lost);
        };
        let recovery = cache
            .repository(|repo| repo.recover_shared_read(ticket, plan.pending.is_some()))
            .map_err(OfflineReadError::Cache)?;
        match recovery {
            SharedReadRecovery::Reuse(record) => plan.finish_shared(Some(record), false),
            SharedReadRecovery::Superseded(record) => plan.finish_shared(record, true),
            SharedReadRecovery::Retry(ticket) => match plan.publish(cache, &ticket) {
                Ok(publication) => {
                    let (data, complete) = plan.pending.take().ok_or(lost)?;
                    plan.finished = true;
                    Ok(plan.batch(Some(data), complete, Some(publication)))
                }
                Err(CacheError::Superseded) => {
                    let outcome = cache
                        .repository(|repo| repo.recover_shared_read(&ticket, false))
                        .map_err(OfflineReadError::Cache)?;
                    match outcome {
                        SharedReadRecovery::Reuse(record) => plan.finish_shared(Some(record), true),
                        SharedReadRecovery::Superseded(record) => plan.finish_shared(record, true),
                        SharedReadRecovery::Retry(_) => Err(lost),
                    }
                }
                Err(error) => Err(OfflineReadError::Cache(error)),
            },
        }
    }
}

impl SpocDetailScan {
    pub(super) fn publish(
        &self,
        cache: &OfflineCache,
        ticket: &CacheReadTicket,
    ) -> CacheResult<CachePublication> {
        let (data, complete) = self.pending.as_ref().ok_or(CacheError::Corrupt)?;
        cache.repository(|repo| {
            repo.publish(
                ticket,
                CachePayload::SpocDetail(Box::new(data.clone())),
                self.list.fetched_at,
                if *complete {
                    CacheCompleteness::Complete
                } else {
                    CacheCompleteness::Partial
                },
            )
        })
    }

    fn finish_shared(
        &mut self,
        record: Option<CacheRecord>,
        superseded: bool,
    ) -> Result<SpocDetailScanBatch, OfflineReadError> {
        let (data, complete, publication) = if let Some(record) = record {
            let CachePayload::SpocDetail(data) = record.payload else {
                return Err(OfflineReadError::Cache(CacheError::Corrupt));
            };
            self.list.resolution.mode = record.scope.route;
            self.list.resolution.diagnostic.mode = record.scope.route;
            self.list.fetched_at = record.fetched_at;
            (
                Some(*data),
                !superseded && record.completeness == CacheCompleteness::Complete,
                Some(if superseded {
                    CachePublication::Preserved
                } else {
                    CachePublication::Stored
                }),
            )
        } else {
            let (data, complete) = self.pending.take().unzip();
            (data, complete.unwrap_or(false), None)
        };
        self.save_error = superseded.then_some(CacheError::Superseded);
        self.finished = true;
        Ok(self.batch(data, complete, publication))
    }
}
