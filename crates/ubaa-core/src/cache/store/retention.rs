//! 容量压力下重新计算保留价值；业务时间不写入明文索引列。
use super::{
    CacheError, CacheLimits, CachePayload, CacheRecord, CacheResult, CacheScope, Connection,
    Crypto, load_body,
};
use crate::cache::CacheQuery;
use crate::domain::ConnectionMode;
use chrono::{DateTime, FixedOffset, NaiveDate, NaiveDateTime, TimeZone, Utc};

const DAY: i64 = 86_400;
#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
pub(super) enum Priority {
    Corrupt,
    Expired,
    Ordinary,
    Recent,
    Stable,
    Active,
    Imported,
}
#[derive(Default)]
pub(super) struct Context {
    terms: Vec<(ConnectionMode, String)>,
}
impl Context {
    pub(super) fn load(
        db: &Connection,
        crypto: &Crypto,
        account: &str,
        now: i64,
    ) -> CacheResult<Self> {
        let mut result = Self::default();
        for route in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
            let scope = CacheScope {
                route,
                query: CacheQuery::ScheduleTerms,
            };
            let key = crypto.index(&(account, &scope))?;
            let Some(body) = load_body(db, &key)? else {
                continue;
            };
            let Ok(record) = crypto.open::<CacheRecord>(&body, &key) else {
                continue;
            };
            if record.scope == scope {
                result.observe(&record, now);
            }
        }
        Ok(result)
    }
    fn observe(&mut self, record: &CacheRecord, now: i64) {
        if record.scope.query != CacheQuery::ScheduleTerms {
            return;
        }
        let route = record.scope.route;
        self.terms.retain(|(r, _)| *r != route);
        if !record.is_fresh(now, DAY) {
            return;
        }
        if let CachePayload::Terms(terms) = &record.payload {
            let selected: Vec<_> = terms.iter().filter(|v| v.selected).collect();
            if selected.len() == 1 && !selected[0].item_code.is_empty() {
                self.terms.push((route, selected[0].item_code.clone()));
            }
        }
    }
    fn academic(&self, route: ConnectionMode, term: &str) -> Priority {
        if self.terms.iter().any(|(r, t)| *r == route && t == term) {
            Priority::Active
        } else {
            Priority::Stable
        }
    }
}
fn campus_time(raw: &str) -> Option<i64> {
    let parsed = NaiveDateTime::parse_from_str(raw, "%Y-%m-%d %H:%M:%S").ok()?;
    if parsed.format("%Y-%m-%d %H:%M:%S").to_string() != raw {
        return None;
    }
    Some(
        FixedOffset::east_opt(8 * 3600)?
            .from_local_datetime(&parsed)
            .single()?
            .timestamp(),
    )
}
fn day(raw: &str) -> Option<NaiveDate> {
    let parsed = NaiveDate::parse_from_str(raw, "%Y-%m-%d").ok()?;
    (parsed.format("%Y-%m-%d").to_string() == raw).then_some(parsed)
}
fn day_end(raw: &str) -> Option<i64> {
    Some(
        FixedOffset::east_opt(8 * 3600)?
            .from_local_datetime(&day(raw)?.and_hms_opt(23, 59, 59)?)
            .single()?
            .timestamp(),
    )
}
fn ended(at: Option<i64>, now: i64, unknown: Priority) -> Priority {
    match at {
        Some(end) if end >= now => Priority::Active,
        Some(end) if now.saturating_sub(end) <= 90 * DAY => Priority::Recent,
        Some(_) => Priority::Expired,
        None => unknown,
    }
}
fn best(values: impl Iterator<Item = Priority>) -> Priority {
    values.max().unwrap_or(Priority::Ordinary)
}
pub(super) fn classify(record: &CacheRecord, context: &Context, now: i64) -> Priority {
    if matches!(&record.payload, CachePayload::ImportedSchedules(_)) {
        return Priority::Imported;
    }
    let Some(utc) = DateTime::<Utc>::from_timestamp(now, 0) else {
        return Priority::Recent;
    };
    if now < record.last_verified_at {
        return Priority::Recent;
    }
    let today = utc
        .with_timezone(&FixedOffset::east_opt(8 * 3600).expect("固定校园时区"))
        .date_naive();
    if let Some(priority) = query_priority(record, context, today) {
        return priority;
    }
    match &record.payload {
        CachePayload::JudgeDetail(v) => ended(
            v.due_time.as_deref().and_then(campus_time),
            now,
            Priority::Ordinary,
        ),
        CachePayload::JudgeSummaries(items) => best(items.iter().map(|v| {
            ended(
                v.due_time.as_deref().and_then(campus_time),
                now,
                Priority::Recent,
            )
        })),
        CachePayload::SpocDetail(v) => ended(
            v.due_time.as_deref().and_then(campus_time),
            now,
            Priority::Ordinary,
        ),
        CachePayload::SpocAssignments(v) => best(v.assignments.iter().map(|v| {
            ended(
                v.due_time.as_deref().and_then(campus_time),
                now,
                Priority::Recent,
            )
        })),
        CachePayload::CgyyDetail(v) => ended(
            v.reservation_date.as_deref().and_then(day_end),
            now,
            Priority::Recent,
        ),
        CachePayload::CgyyOrders(v) => best(v.content.iter().map(|v| {
            ended(
                v.reservation_date.as_deref().and_then(day_end),
                now,
                Priority::Recent,
            )
        })),
        CachePayload::LibBookBookings(v) => best(
            v.bookings
                .iter()
                .map(|v| ended(day_end(&v.day), now, Priority::Recent)),
        ),
        CachePayload::Grades(_)
        | CachePayload::GradeScoreBaseline(_)
        | CachePayload::Terms(_)
        | CachePayload::Weeks(_)
        | CachePayload::JudgeCourses(_)
        | CachePayload::JudgeAssignments(_)
        | CachePayload::JudgeCourseReview(_)
        | CachePayload::MaskedProfile(_)
        | CachePayload::BykcChosen(_)
        | CachePayload::BykcStatistics(_) => Priority::Stable,
        CachePayload::EvaluationCurrent(_) => Priority::Recent,
        _ => Priority::Ordinary,
    }
}

fn query_priority(record: &CacheRecord, context: &Context, today: NaiveDate) -> Option<Priority> {
    match &record.scope.query {
        CacheQuery::ScheduleWeek { term, .. } => {
            return Some(context.academic(record.scope.route, term));
        }
        CacheQuery::ScheduleToday { date } => {
            return Some(if day(date).is_some_and(|date| date >= today) {
                Priority::Active
            } else {
                Priority::Ordinary
            });
        }
        CacheQuery::SigninToday { date } => {
            return Some(day(date).map_or(Priority::Ordinary, |date| {
                if date < today {
                    Priority::Expired
                } else {
                    Priority::Active
                }
            }));
        }
        CacheQuery::Exams { term } => {
            let mut priority = context.academic(record.scope.route, term);
            if let CachePayload::Exams(value) = &record.payload
                && value.arranged.iter().any(|exam| {
                    exam.exam_date
                        .as_deref()
                        .and_then(day)
                        .is_some_and(|date| date >= today)
                })
            {
                priority = Priority::Active;
            }
            return Some(priority);
        }
        CacheQuery::Classrooms { date, .. }
        | CacheQuery::CgyyDay { date, .. }
        | CacheQuery::LibBookSeats { day: date, .. }
        | CacheQuery::LibBookLibraries { day: date }
        | CacheQuery::LibBookAreas { day: date, .. } => {
            return Some(if day(date).is_some_and(|date| date < today) {
                Priority::Expired
            } else {
                Priority::Ordinary
            });
        }
        _ => {}
    }
    None
}

pub(super) struct Admission<'a> {
    pub db: &'a Connection,
    pub crypto: &'a Crypto,
    pub account: &'a str,
    pub limits: CacheLimits,
    pub now: i64,
}
impl Admission<'_> {
    pub fn reserve(&self, key: &[u8], record: &CacheRecord, bytes: usize) -> CacheResult<()> {
        let bytes = u64::try_from(bytes).map_err(|_| CacheError::Capacity)?;
        if bytes > self.limits.hard_bytes {
            return Err(CacheError::Capacity);
        }
        let existing: i64 = self
            .db
            .query_row(
                "SELECT COALESCE(SUM(length(body)),0) FROM (SELECT body FROM entries WHERE key != ?1 UNION ALL SELECT body FROM readback_hints)",
                [key],
                |r| r.get(0),
            )
            .map_err(CacheError::from)?;
        let mut total = u64::try_from(existing)
            .map_err(|_| CacheError::Corrupt)?
            .checked_add(bytes)
            .ok_or(CacheError::Capacity)?;
        if total <= self.limits.soft_bytes {
            return Ok(());
        }
        let mut context = Context::load(self.db, self.crypto, self.account, self.now)?;
        context.observe(record, self.now);
        let incoming = classify(record, &context, self.now);
        let mut statement = self
            .db
            .prepare("SELECT key, body, accessed FROM entries WHERE key != ?1")
            .map_err(CacheError::from)?;
        let mut rows = statement.query([key]).map_err(CacheError::from)?;
        let mut candidates = Vec::new();
        while let Some(row) = rows.next().map_err(CacheError::from)? {
            let key: Vec<u8> = row.get(0).map_err(CacheError::from)?;
            let body: Vec<u8> = row.get(1).map_err(CacheError::from)?;
            let accessed: i64 = row.get(2).map_err(CacheError::from)?;
            let priority = self
                .crypto
                .open::<CacheRecord>(&body, &key)
                .map_or(Priority::Corrupt, |record| {
                    classify(&record, &context, self.now)
                });
            candidates.push((priority, accessed.min(self.now), key, body.len()));
        }
        drop(rows);
        drop(statement);
        candidates.sort_unstable_by(|a, b| (&a.0, &a.1, &a.2).cmp(&(&b.0, &b.1, &b.2)));
        for (priority, _, victim, size) in candidates {
            if total <= self.limits.soft_bytes
                || (priority >= Priority::Recent && total <= self.limits.hard_bytes)
            {
                break;
            }
            // 当前保存请求不能强行挤掉更有价值的现存条目；失败由外层事务回滚。
            if priority == Priority::Imported || priority > incoming {
                break;
            }
            self.db
                .execute("DELETE FROM entries WHERE key=?1", [&victim])
                .map_err(CacheError::from)?;
            total = total.saturating_sub(u64::try_from(size).map_err(|_| CacheError::Corrupt)?);
        }
        if total > self.limits.hard_bytes {
            Err(CacheError::Capacity)
        } else {
            Ok(())
        }
    }
}
