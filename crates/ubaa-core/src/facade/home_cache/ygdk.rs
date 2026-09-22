//! 观察周期是本地日历分桶，不推断学校教学周或统计清零规则。
use crate::facade::{
    CacheCompleteness, CacheError, CachePayload, CachePublication, CacheQuery, CacheReadTicket,
    CacheRecord, CacheResult, CacheScope, CachedYgdkOverview, ConnectionMode, OfflineCache,
};
use chrono::{Datelike, FixedOffset, NaiveDate};
fn campus_day(now: i64) -> CacheResult<NaiveDate> {
    chrono::DateTime::from_timestamp(now, 0)
        .map(|date| {
            date.with_timezone(&FixedOffset::east_opt(8 * 3600).expect("固定校园时区"))
                .date_naive()
        })
        .ok_or(CacheError::InvalidInput)
}
pub(super) fn selection_scope(route: ConnectionMode, now: i64) -> CacheResult<CacheScope> {
    let day = campus_day(now)?;
    let monday = day
        .checked_sub_days(chrono::Days::new(u64::from(
            day.weekday().num_days_from_monday(),
        )))
        .ok_or(CacheError::InvalidInput)?;
    Ok(CacheScope {
        route,
        query: CacheQuery::YgdkOverviewSelection {
            week_start: monday.to_string(),
        },
    })
}
pub(super) fn period_scope(
    parent: &CacheScope,
    data: &CachedYgdkOverview,
) -> CacheResult<CacheScope> {
    let CacheQuery::YgdkOverviewSelection { week_start } = &parent.query else {
        return Err(CacheError::InvalidInput);
    };
    let scope = CacheScope {
        route: parent.route,
        query: CacheQuery::YgdkOverviewPeriod {
            classify_id: data.classify_id,
            term_id: data.summary.term_id,
            week_start: week_start.clone(),
        },
    };
    scope.validate()?;
    Ok(scope)
}
pub(super) fn publish(
    cache: &OfflineCache,
    parent: &CacheReadTicket,
    data: &CachedYgdkOverview,
    began_at: i64,
    fetched_at: i64,
    complete: bool,
) -> CacheResult<(CacheScope, CachePublication)> {
    // 组合网络请求跨校园日期时无法证明统计属于同一天，不混入周期缓存。
    if campus_day(began_at)? != campus_day(fetched_at)?
        || parent.scope() != &selection_scope(parent.scope().route, began_at)?
    {
        return Err(CacheError::Superseded);
    }
    let scope = period_scope(parent.scope(), data)?;
    let completeness = if complete && data.summary.term_id.is_some() {
        CacheCompleteness::Complete
    } else {
        CacheCompleteness::Partial
    };
    cache.repository(|repository| {
        let child = repository.begin_read_guarded(scope.clone(), parent)?;
        let publication = repository.publish_guarded(
            &child,
            parent,
            CachePayload::YgdkOverview(data.clone()),
            fetched_at,
            completeness,
        )?;
        repository.publish(
            parent,
            CachePayload::YgdkOverviewSelection {
                classify_id: data.classify_id,
                term_id: data.summary.term_id,
            },
            fetched_at,
            completeness,
        )?;
        Ok((scope, publication))
    })
}
pub(super) fn read(
    cache: &OfflineCache,
    route: ConnectionMode,
    now: i64,
) -> CacheResult<Option<CacheRecord>> {
    let parent = selection_scope(route, now)?;
    let Some(index) = cache.read(&parent, now)? else {
        return Ok(None);
    };
    let CachePayload::YgdkOverviewSelection {
        classify_id,
        term_id,
    } = index.payload
    else {
        return Err(CacheError::Corrupt);
    };
    let CacheQuery::YgdkOverviewSelection { week_start } = parent.query else {
        unreachable!()
    };
    let scope = CacheScope {
        route,
        query: CacheQuery::YgdkOverviewPeriod {
            classify_id,
            term_id,
            week_start,
        },
    };
    let Some(mut record) = cache.read(&scope, now)? else {
        return Ok(None);
    };
    let CachePayload::YgdkOverview(data) = &mut record.payload else {
        return Err(CacheError::Corrupt);
    };
    let today = campus_day(now)?;
    let source = campus_day(record.fetched_at)?;
    if source != today {
        data.summary.day_count = None;
    }
    if (source.year(), source.month()) != (today.year(), today.month()) {
        data.summary.month_count = None;
    }
    Ok(Some(record))
}
