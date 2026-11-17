//! 同查询读取竞争只恢复一次，账号和会话失效仍由原扫描栅栏拒绝。
use super::{
    CacheCompleteness, CacheError, CachePayload, CachePublication, OfflineReadError, SpocScan,
    SpocScanBatch, UbaaClient,
};
use crate::cache::SharedReadRecovery;

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
        match cache
            .repository(|repo| repo.recover_shared_read(old, plan.last_page_read && plan.complete))
        {
            Ok(SharedReadRecovery::Reuse(record)) => {
                return finish_shared(plan, Some(record), false);
            }
            Ok(SharedReadRecovery::Superseded(record)) => {
                return finish_shared(plan, record, true);
            }
            Ok(SharedReadRecovery::Retry(ticket)) => {
                plan.ticket = Some(ticket.clone());
                match super::super::spoc::publish(
                    &cache,
                    &ticket,
                    &plan.data,
                    plan.fetched_at,
                    plan.complete,
                ) {
                    Ok(publication) => {
                        plan.finished = true;
                        return Ok(plan.batch(Some(publication)));
                    }
                    Err(CacheError::Superseded) => {
                        let recovery = cache
                            .repository(|repo| repo.recover_shared_read(&ticket, false))
                            .map_err(OfflineReadError::Cache)?;
                        return match recovery {
                            SharedReadRecovery::Reuse(record) => {
                                finish_shared(plan, Some(record), true)
                            }
                            SharedReadRecovery::Superseded(record) => {
                                finish_shared(plan, record, true)
                            }
                            SharedReadRecovery::Retry(_) => {
                                unreachable!("本地恢复最多补发一次票据")
                            }
                        };
                    }
                    Err(error) => return Err(OfflineReadError::Cache(error)),
                }
            }
            Err(CacheError::Superseded) => {}
            Err(error) => return Err(OfflineReadError::Cache(error)),
        }
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
            plan.resolution.diagnostic.mode = aggregate.scope.route;
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

fn finish_shared(
    plan: &mut SpocScan,
    aggregate: Option<crate::cache::CacheRecord>,
    superseded: bool,
) -> Result<SpocScanBatch, OfflineReadError> {
    let had_saved = aggregate.is_some();
    if let Some(record) = aggregate {
        let CachePayload::SpocAssignments(data) = record.payload else {
            return Err(OfflineReadError::Cache(CacheError::Corrupt));
        };
        plan.data = data;
        plan.fetched_at = record.fetched_at;
        plan.complete = !superseded && record.completeness == CacheCompleteness::Complete;
        plan.resolution.mode = record.scope.route;
        plan.resolution.diagnostic.mode = record.scope.route;
    } else {
        plan.complete = false;
    }
    plan.finished = true;
    plan.save_error = superseded.then_some(CacheError::Superseded);
    Ok(plan.batch(had_saved.then_some(if superseded {
        CachePublication::Preserved
    } else {
        CachePublication::Stored
    })))
}
