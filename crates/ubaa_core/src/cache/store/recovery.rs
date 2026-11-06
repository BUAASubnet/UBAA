//! SPOC 选择和希冀摘要同查询竞争的完整结果复用与原子重读。
use super::{
    CacheCompleteness, CacheError, CacheReadTicket, CacheRecord, CacheResult, CacheScope,
    OfflineRepository, OptionalExtension, TransactionBehavior, invalidation, load_body,
    load_current_control, params, require_active, save_control,
};
use crate::cache::CacheQuery;

impl OfflineRepository {
    /// 核对同查询较新读取后，复用完整提交或原子分配一次重读票据。
    ///
    /// 仅用于没有学校写入失效操作的 SPOC 选择与希冀摘要查询。返回 `None`
    /// 表示较新读取尚未提交可复用结果，此时返回新票据。复用提交时返回原票据，
    /// 原票据始终保持失效。账号核对与新票据分配在同一事务内完成。
    pub(crate) fn recover_readonly_scan(
        &mut self,
        ticket: &CacheReadTicket,
    ) -> CacheResult<(CacheReadTicket, Option<CacheRecord>)> {
        let key = self.crypto.index(&(&self.account, &ticket.scope.query))?;
        let tx = self
            .db
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(CacheError::from)?;
        let mut control = load_current_control(&tx, &self.crypto, &self.account, self.generation)?;
        require_active(&control)?;
        if ticket.account != self.account
            || ticket.database_id != control.database_id
            || ticket.epoch != control.epoch
            || !matches!(
                ticket.scope.query,
                CacheQuery::SpocSelection | CacheQuery::JudgeSummaries { .. }
            )
        {
            return Err(CacheError::Superseded);
        }
        let request: Option<(i64, Vec<u8>)> = tx
            .query_row(
                "SELECT revision,scope FROM requests WHERE key=?1",
                [&key],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .optional()
            .map_err(CacheError::from)?;
        if let Some((_, body)) = &request {
            let scope: CacheScope = self.crypto.open(body, &invalidation::scope_aad(&key))?;
            if scope.query != ticket.scope.query {
                return Err(CacheError::Corrupt);
            }
        }
        let record = load_body(&tx, &key)?
            .map(|body| self.crypto.open::<CacheRecord>(&body, &key))
            .transpose()?;
        if record.as_ref().is_some_and(|record| {
            record.scope.query != ticket.scope.query || !record.payload.matches(&ticket.scope.query)
        }) {
            return Err(CacheError::Corrupt);
        }
        let request_revision = request.map(|(revision, _)| revision);
        let newer_record = record.filter(|record| record.revision > ticket.revision);
        if request_revision.is_none_or(|revision| revision <= ticket.revision)
            && newer_record.is_none()
        {
            return Err(CacheError::Superseded);
        }
        let reusable = newer_record.filter(|record| {
            record.completeness == CacheCompleteness::Complete
                && record.last_attempt_succeeded
                && request_revision.is_none_or(|revision| revision <= record.revision)
        });
        let next_ticket = if reusable.is_some() {
            ticket.clone()
        } else {
            control.revision = control
                .revision
                .checked_add(1)
                .ok_or(CacheError::Capacity)?;
            save_control(&tx, &self.crypto, &self.account, &control)?;
            let body = self
                .crypto
                .seal(&ticket.scope, &invalidation::scope_aad(&key))?;
            tx.execute(
                "INSERT INTO requests(key,revision,scope) VALUES(?1,?2,?3) ON CONFLICT(key) DO UPDATE SET revision=excluded.revision,scope=excluded.scope",
                params![key, control.revision, body],
            )
            .map_err(CacheError::from)?;
            CacheReadTicket {
                account: self.account.clone(),
                scope: ticket.scope.clone(),
                epoch: control.epoch,
                database_id: control.database_id,
                revision: control.revision,
            }
        };
        tx.commit().map_err(CacheError::from)?;
        Ok((next_ticket, reusable))
    }
}
