//! 学期导入在同一事务内合并完整快照，保留其他学期。
use super::{
    CacheCompleteness, CacheError, CachePayload, CachePublication, CacheQuery, CacheReadTicket,
    CacheRecord, CacheResult, CacheScope, OfflineRepository, TransactionBehavior, load_body,
    load_current_control, retention, save_control, validate_ticket, write_record,
};
use crate::cache::{CachedSemesterSchedule, schedule::valid_collection};

impl OfflineRepository {
    /// 按学期核对票据、合并并保存完整学期，保留所有其他学期。
    ///
    /// # Errors
    /// 旧票据、错误范围、不完整学期、容量或存储错误不发布新版本。
    pub fn publish_imported_semester(
        &mut self,
        ticket: &CacheReadTicket,
        mut value: CachedSemesterSchedule,
    ) -> CacheResult<CachePublication> {
        let tx = self
            .db
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(CacheError::from)?;
        let ticket_key = self.crypto.index(&(&self.account, &ticket.scope.query))?;
        validate_ticket(
            &tx,
            &self.crypto,
            &self.account,
            ticket,
            &ticket_key,
            self.generation,
        )?;
        let is_collection = match &ticket.scope.query {
            CacheQuery::ImportedSchedules => true,
            CacheQuery::ScheduleImport { term } if term == &value.term_code => false,
            _ => return Err(CacheError::InvalidInput),
        };
        if !value.is_valid() {
            return Err(CacheError::InvalidInput);
        }
        let query = CacheQuery::ImportedSchedules;
        let key = self.crypto.index(&(&self.account, &query))?;
        let mut values = if let Some(body) = load_body(&tx, &key)? {
            match self.crypto.open::<CacheRecord>(&body, &key) {
                Ok(CacheRecord {
                    scope,
                    payload: CachePayload::ImportedSchedules(values),
                    ..
                }) if scope.query == query && valid_collection(&values) => values,
                _ => {
                    tx.execute("DELETE FROM entries WHERE key=?1", [&key])
                        .map_err(CacheError::from)?;
                    tx.commit().map_err(CacheError::from)?;
                    return Err(CacheError::Corrupt);
                }
            }
        } else {
            Vec::new()
        };
        let revision = if is_collection {
            ticket.revision
        } else {
            let mut control =
                load_current_control(&tx, &self.crypto, &self.account, self.generation)?;
            control.revision = control
                .revision
                .checked_add(1)
                .ok_or(CacheError::Capacity)?;
            save_control(&tx, &self.crypto, &self.account, &control)?;
            control.revision
        };
        values.retain(|existing| existing.term_code != value.term_code);
        let fetched_at = value.fetched_at;
        value.import_revision = Some(ticket.revision);
        values.push(value);
        write_record(
            &retention::Admission {
                db: &tx,
                crypto: &self.crypto,
                account: &self.account,
                limits: self.limits,
                now: fetched_at,
            },
            &key,
            &CacheRecord {
                scope: CacheScope {
                    route: ticket.scope.route,
                    query,
                },
                payload: CachePayload::ImportedSchedules(values),
                fetched_at,
                last_attempt_at: fetched_at,
                last_verified_at: fetched_at,
                last_attempt_succeeded: true,
                revision,
                completeness: CacheCompleteness::Complete,
            },
            super::shared_read::ReadStamp::default(),
        )?;
        tx.commit().map_err(CacheError::from)?;
        Ok(CachePublication::Stored)
    }
}
