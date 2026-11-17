//! 只为精确查询的跨仓库竞争补发本地票据。
use super::{
    CacheCompleteness, CacheError, CachePayload, CacheQuery, CacheReadTicket, CacheRecord,
    CacheResult, CacheScope, Connection, Crypto, OfflineRepository, OptionalExtension,
    TransactionBehavior, allocate_read, invalidation, load_body, load_current_control,
    require_active,
};
use serde::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    sync::{Arc, Weak},
};

pub(crate) enum SharedReadRecovery {
    Reuse(CacheRecord),
    Retry(CacheReadTicket),
    Superseded(Option<CacheRecord>),
}

#[derive(Default)]
pub(super) struct LocalReaders(HashMap<Vec<u8>, Weak<()>>);

impl LocalReaders {
    pub(super) fn register(&mut self, key: Vec<u8>, ticket: &mut CacheReadTicket) {
        if !eligible(&ticket.scope.query) {
            return;
        }
        self.0.retain(|_, reader| reader.strong_count() > 0);
        let marker = Arc::new(());
        self.0.insert(key, Arc::downgrade(&marker));
        ticket.local = Some(marker);
    }

    fn is_latest(&self, key: &[u8], ticket: &CacheReadTicket) -> bool {
        ticket.local.as_ref().is_some_and(|marker| {
            self.0
                .get(key)
                .is_some_and(|current| current.as_ptr() == Arc::as_ptr(marker))
        })
    }
}

fn eligible(query: &CacheQuery) -> bool {
    matches!(
        query,
        CacheQuery::ScheduleToday { .. }
            | CacheQuery::ScheduleTerms
            | CacheQuery::ScheduleWeeks { .. }
            | CacheQuery::ScheduleWeek { .. }
            | CacheQuery::ScheduleImport { .. }
            | CacheQuery::ExamTerms
            | CacheQuery::Exams { .. }
            | CacheQuery::Grades { .. }
            | CacheQuery::GradesOverview
            | CacheQuery::Classrooms { .. }
            | CacheQuery::SpocSelection
            | CacheQuery::SpocDetail { .. }
            | CacheQuery::JudgeSummaries { .. }
    ) || needs_lineage(query)
}

pub(super) fn needs_lineage(query: &CacheQuery) -> bool {
    matches!(
        query,
        CacheQuery::EvaluationCurrent
            | CacheQuery::SigninToday { .. }
            | CacheQuery::YgdkOverviewSelection { .. }
            | CacheQuery::BykcChosen
            | CacheQuery::CgyyOrders { .. }
    )
}

// 现有读取器仍可读取顶层 scope/record；旧实例改写后缺少世代时禁止恢复。
#[derive(Deserialize, Serialize)]
struct Scoped<T> {
    #[serde(flatten)]
    value: T,
    #[serde(flatten)]
    stamp: ReadStamp,
}

#[derive(Default, Deserialize, Serialize)]
pub(super) struct ReadStamp {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    read_lineage: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    last_read_revision: Option<i64>,
}

impl ReadStamp {
    pub(super) fn for_record(ticket: &CacheReadTicket, record: &CacheRecord) -> Self {
        Self {
            read_lineage: ticket.lineage,
            last_read_revision: (ticket.local.is_some() && ticket.revision > record.revision)
                .then_some(ticket.revision),
        }
    }
}

fn request(db: &Connection, key: &[u8]) -> CacheResult<Option<(i64, Vec<u8>)>> {
    db.query_row(
        "SELECT revision,scope FROM requests WHERE key=?1",
        [key],
        |row| Ok((row.get(0)?, row.get(1)?)),
    )
    .optional()
    .map_err(CacheError::from)
}

pub(super) fn scope_lineage(
    db: &Connection,
    crypto: &Crypto,
    key: &[u8],
    query: &CacheQuery,
) -> CacheResult<Option<i64>> {
    if !needs_lineage(query) {
        return Ok(None);
    }
    if let Some((_, body)) = request(db, key)? {
        return crypto
            .open::<Scoped<CacheScope>>(&body, &invalidation::scope_aad(key))
            .map(|value| value.stamp.read_lineage);
    }
    // 旧缓存或坏条目继续由原读取/发布路径处理。
    Ok(
        load_body(db, key)?
            .and_then(|body| crypto.open::<ReadStamp>(&body, key).ok()?.read_lineage),
    )
}

pub(super) fn seal_scope(
    crypto: &Crypto,
    key: &[u8],
    scope: &CacheScope,
    lineage: Option<i64>,
) -> CacheResult<Vec<u8>> {
    let aad = invalidation::scope_aad(key);
    if lineage.is_some() {
        crypto.seal(
            &Scoped {
                value: scope,
                stamp: ReadStamp {
                    read_lineage: lineage,
                    ..ReadStamp::default()
                },
            },
            &aad,
        )
    } else {
        crypto.seal(scope, &aad)
    }
}

pub(super) fn seal_record(
    crypto: &Crypto,
    key: &[u8],
    record: &CacheRecord,
    stamp: ReadStamp,
) -> CacheResult<Vec<u8>> {
    if stamp.read_lineage.is_some() || stamp.last_read_revision.is_some() {
        crypto.seal(
            &Scoped {
                value: record,
                stamp,
            },
            key,
        )
    } else {
        crypto.seal(record, key)
    }
}

impl OfflineRepository {
    /// 父查询被跨仓库替代后，按原账号代次读取指定的子查询；不补发任何票据。
    pub(crate) fn read_after_shared_superseded(
        &mut self,
        ticket: &CacheReadTicket,
        query: &CacheQuery,
    ) -> CacheResult<Option<CacheRecord>> {
        let parent_key = self.crypto.index(&(&self.account, &ticket.scope.query))?;
        let key = self.crypto.index(&(&self.account, query))?;
        let tx = self.db.transaction().map_err(CacheError::from)?;
        let control = load_current_control(&tx, &self.crypto, &self.account, self.generation)?;
        require_active(&control)?;
        if ticket.account != self.account
            || ticket.database_id != control.database_id
            || ticket.epoch != control.epoch
            || ticket.generation != control.generation
            || !self.shared_reads.is_latest(&parent_key, ticket)
        {
            return Err(CacheError::Superseded);
        }
        let record = load_body(&tx, &key)?
            .map(|body| self.crypto.open::<CacheRecord>(&body, &key))
            .transpose()?;
        if record
            .as_ref()
            .is_some_and(|record| record.scope.query != *query || !record.payload.matches(query))
        {
            return Err(CacheError::Corrupt);
        }
        tx.commit().map_err(CacheError::from)?;
        Ok(record)
    }

    pub(crate) fn recover_shared_read(
        &mut self,
        ticket: &CacheReadTicket,
        retry: bool,
    ) -> CacheResult<SharedReadRecovery> {
        self.recover_shared_read_with(ticket, retry, &ticket.scope.query, |record| {
            Ok(Some(record))
        })
    }

    /// 检查旧票据生命周期及跨仓库竞争证据，再选择已提交内容或补发一次本地票据。
    pub(crate) fn recover_shared_read_with(
        &mut self,
        ticket: &CacheReadTicket,
        retry: bool,
        record_query: &CacheQuery,
        select: impl FnOnce(CacheRecord) -> CacheResult<Option<CacheRecord>>,
    ) -> CacheResult<SharedReadRecovery> {
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
            || ticket.generation != control.generation
            || !self.shared_reads.is_latest(&key, ticket)
        {
            return Err(CacheError::Superseded);
        }

        let mut competing_request = false;
        if let Some((revision, body)) = request(&tx, &key)? {
            // 复合查询可能在父票据仍有效时因子票据失败，不能在这里恢复父票据。
            if revision <= ticket.revision {
                return Err(CacheError::Superseded);
            }
            let scope: Scoped<CacheScope> =
                self.crypto.open(&body, &invalidation::scope_aad(&key))?;
            if scope.value.query != ticket.scope.query {
                return Err(CacheError::Corrupt);
            }
            if scope.stamp.read_lineage != ticket.lineage {
                return Err(CacheError::Superseded);
            }
            competing_request = true;
        }
        let record_key = if *record_query == ticket.scope.query {
            key.clone()
        } else {
            self.crypto.index(&(&self.account, record_query))?
        };
        let mut record = None;
        if let Some((saved, stamp)) =
            read_saved_record(&tx, &self.crypto, &record_key, record_query)?
        {
            let lineage = stamp.read_lineage;
            if *record_query == ticket.scope.query && lineage == ticket.lineage {
                competing_request |= stamp
                    .last_read_revision
                    .is_some_and(|revision| revision > ticket.revision);
            }
            // 发票前的旧格式记录可以作为保留值；只能用同世代的新记录证明竞争。
            record = if lineage == ticket.lineage {
                select(saved)?
            } else if competing_request && saved.revision < ticket.lineage.unwrap_or_default() {
                select(saved)?.filter(|record| record.revision < ticket.revision)
            } else {
                None
            };
        }
        if *record_query == ticket.scope.query
            && let Some(imported) =
                read_imported_candidate(&tx, &self.crypto, &self.account, &ticket.scope)?
            && record
                .as_ref()
                .is_none_or(|current| current.revision < imported.revision)
        {
            record = Some(imported);
        }
        let competing_record = record
            .as_ref()
            .is_some_and(|record| record.revision > ticket.revision);
        let record = record
            .map(|value| project_shared_record(&tx, &self.crypto, &self.account, value))
            .transpose()?
            .flatten();
        let newer = record
            .as_ref()
            .is_some_and(|record| record.revision > ticket.revision);
        if !competing_request && !competing_record {
            return Err(CacheError::Superseded);
        }
        let mut result = if newer
            && record
                .as_ref()
                .is_some_and(|record| record.completeness == CacheCompleteness::Complete)
        {
            SharedReadRecovery::Reuse(record.ok_or(CacheError::Corrupt)?)
        } else if retry {
            SharedReadRecovery::Retry(allocate_read(
                &tx,
                &self.crypto,
                &self.account,
                &mut control,
                &key,
                ticket.scope.clone(),
                ticket.lineage,
            )?)
        } else {
            SharedReadRecovery::Superseded(record)
        };
        tx.commit().map_err(CacheError::from)?;
        if let SharedReadRecovery::Retry(next) = &mut result {
            self.shared_reads.register(key, next);
        }
        Ok(result)
    }
}

fn read_saved_record(
    db: &Connection,
    crypto: &Crypto,
    key: &[u8],
    query: &CacheQuery,
) -> CacheResult<Option<(CacheRecord, ReadStamp)>> {
    let Some(body) = load_body(db, key)? else {
        return Ok(None);
    };
    let plaintext = crypto.open_json(&body, key)?;
    let record: CacheRecord =
        serde_json::from_slice(&plaintext).map_err(|_| CacheError::Corrupt)?;
    if record.scope.query != *query || !record.payload.matches(query) {
        return Err(CacheError::Corrupt);
    }
    let stamp = serde_json::from_slice(&plaintext).map_err(|_| CacheError::Corrupt)?;
    Ok(Some((record, stamp)))
}

fn read_imported_candidate(
    db: &Connection,
    crypto: &Crypto,
    account: &str,
    scope: &CacheScope,
) -> CacheResult<Option<CacheRecord>> {
    if !matches!(
        scope.query,
        CacheQuery::ScheduleTerms
            | CacheQuery::ScheduleWeeks { .. }
            | CacheQuery::ScheduleWeek { .. }
    ) {
        return Ok(None);
    }
    let query = CacheQuery::ImportedSchedules;
    let key = crypto.index(&(account, &query))?;
    let Some(body) = load_body(db, &key)? else {
        return Ok(None);
    };
    let record = crypto.open::<CacheRecord>(&body, &key)?;
    if record.scope.query != query || !record.payload.matches(&query) {
        return Err(CacheError::Corrupt);
    }
    crate::cache::schedule::project_imported_schedule(
        record,
        scope.clone(),
        chrono::Utc::now().timestamp(),
    )
}

// 选择索引和实际展示的聚合必须从同一个快照读取。
fn project_shared_record(
    db: &Connection,
    crypto: &Crypto,
    account: &str,
    index: CacheRecord,
) -> CacheResult<Option<CacheRecord>> {
    let query = match (&index.scope.query, &index.payload) {
        (CacheQuery::SpocSelection, CachePayload::SpocSelection { term }) => {
            CacheQuery::SpocTerm { term: term.clone() }
        }
        (
            CacheQuery::YgdkOverviewSelection { week_start },
            CachePayload::YgdkOverviewSelection {
                classify_id,
                term_id,
            },
        ) => CacheQuery::YgdkOverviewPeriod {
            classify_id: *classify_id,
            term_id: *term_id,
            week_start: week_start.clone(),
        },
        _ => return Ok(Some(index)),
    };
    let key = crypto.index(&(account, &query))?;
    let Some(body) = load_body(db, &key)? else {
        return Ok(None);
    };
    let mut child = crypto.open::<CacheRecord>(&body, &key)?;
    if child.scope.query != query || !child.payload.matches(&query) {
        return Err(CacheError::Corrupt);
    }
    child.revision = index.revision;
    if index.completeness != CacheCompleteness::Complete {
        child.completeness = CacheCompleteness::Partial;
    }
    if let CachePayload::YgdkOverview(value) = &mut child.payload {
        value.trim_to_source_date(child.fetched_at, chrono::Utc::now().timestamp())?;
    }
    Ok(Some(child))
}

#[cfg(test)]
mod tests;
