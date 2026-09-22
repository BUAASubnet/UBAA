//! 当前选择只是指针；学期聚合与页分别保存，不将旧无范围记录推断为当前学期。
use crate::facade::{
    CacheCompleteness, CacheError, CachePayload, CachePublication, CacheQuery, CacheReadTicket,
    CacheRecord, CacheResult, CacheScope, ConnectionMode, OfflineCache, SpocAssignments,
};
pub(super) fn term_scope(route: ConnectionMode, term: &str) -> CacheScope {
    CacheScope {
        route,
        query: CacheQuery::SpocTerm { term: term.into() },
    }
}
pub(super) fn read(
    cache: &OfflineCache,
    route: ConnectionMode,
    now: i64,
) -> CacheResult<Option<CacheRecord>> {
    let Some(index) = cache.read(
        &CacheScope {
            route,
            query: CacheQuery::SpocSelection,
        },
        now,
    )?
    else {
        return Ok(None);
    };
    let CachePayload::SpocSelection { term } = index.payload else {
        return Err(CacheError::Corrupt);
    };
    cache.read(&term_scope(route, &term), now)
}
pub(super) fn publish(
    cache: &OfflineCache,
    parent: &CacheReadTicket,
    data: &SpocAssignments,
    fetched_at: i64,
    complete: bool,
) -> CacheResult<CachePublication> {
    let completeness = if complete {
        CacheCompleteness::Complete
    } else {
        CacheCompleteness::Partial
    };
    cache.repository(|repo| {
        let child =
            repo.begin_read_guarded(term_scope(parent.scope().route, &data.term_code), parent)?;
        let result = repo.publish_guarded(
            &child,
            parent,
            CachePayload::SpocAssignments(data.clone()),
            fetched_at,
            completeness,
        )?;
        repo.publish(
            parent,
            CachePayload::SpocSelection {
                term: data.term_code.clone(),
            },
            fetched_at,
            completeness,
        )?;
        Ok(result)
    })
}
