//! 本地日程查询不持有 UbaaClient，不可能发起学校请求。
use super::{
    AgendaEntry, AgendaStore, AgendaTime, CacheCompleteness, CacheError, CachePayload, CacheQuery,
    CacheRecord, CacheResult, CacheScope, ConnectionMode, OfflineCache, ReadonlyFeature,
    SchoolAgendaContext, SchoolAgendaItem, Week, YgdkAgendaSettings,
};
use crate::cache::CachedSemesterSchedule;
use chrono::{Datelike, Duration, NaiveDate};

mod export;
pub use export::AgendaCachedExportResult;

#[derive(Clone, Debug)]
pub struct AgendaQuery {
    pub route: ConnectionMode,
    /// 课表与考试的明确学期；SPOC 和阳光沿现有缓存的当前选择。
    pub term: String,
    pub from: NaiveDate,
    pub to: NaiveDate,
    pub now: AgendaTime,
    pub include_hidden: bool,
    pub ygdk: YgdkAgendaSettings,
}
impl AgendaQuery {
    #[must_use]
    pub fn new(
        route: ConnectionMode,
        term: String,
        from: NaiveDate,
        to: NaiveDate,
        now: AgendaTime,
    ) -> Self {
        Self {
            route,
            term,
            from,
            to,
            now,
            include_hidden: false,
            ygdk: YgdkAgendaSettings::default(),
        }
    }
}
#[derive(Clone, Debug, PartialEq)]
pub struct AgendaCacheObservation {
    pub scope: CacheScope,
    pub fetched_at: i64,
    pub last_verified_at: i64,
    pub last_attempt_at: i64,
    pub last_attempt_succeeded: bool,
    pub completeness: CacheCompleteness,
}
impl AgendaCacheObservation {
    #[must_use]
    pub fn is_fresh(&self, now: i64, ttl_seconds: i64) -> bool {
        self.last_attempt_succeeded
            && self.completeness == CacheCompleteness::Complete
            && self.last_attempt_at == self.last_verified_at
            && ttl_seconds >= 0
            && now
                .checked_sub(self.last_verified_at)
                .is_some_and(|age| age >= 0 && age <= ttl_seconds)
    }
}
impl From<&CacheRecord> for AgendaCacheObservation {
    fn from(v: &CacheRecord) -> Self {
        Self {
            scope: v.scope.clone(),
            fetched_at: v.fetched_at,
            last_verified_at: v.last_verified_at,
            last_attempt_at: v.last_attempt_at,
            last_attempt_succeeded: v.last_attempt_succeeded,
            completeness: v.completeness,
        }
    }
}
#[derive(Clone, Debug, PartialEq)]
pub struct AgendaSourceAvailability {
    pub feature: ReadonlyFeature,
    pub observations: Vec<AgendaCacheObservation>,
    pub missing_scopes: Vec<CacheScope>,
    /// 仅课表有值；零散周缓存不能成为完整导入证明。
    pub semester_imported: Option<bool>,
    /// 字段缺失、无稳定键或教学周冲突导致无法投影的记录数。
    pub unprojectable_count: usize,
}
#[derive(Clone, Debug, PartialEq)]
pub struct AgendaQueryResult {
    pub entries: Vec<AgendaEntry>,
    pub sources: Vec<AgendaSourceAvailability>,
}
impl AgendaStore {
    /// 学校缓存未打开时仍可查询本机日程。空学期表示宿主尚不知道学期。
    /// 每个学校来源均返回无缓存状态，不推断学校内容或补造时间。
    ///
    /// # Errors
    /// 时间或范围无效、日程已退出、展开超限或日程文件损坏时返回本地错误。
    pub fn query_local_agenda(&self, query: &AgendaQuery) -> CacheResult<AgendaQueryResult> {
        if !query.now.valid() {
            return Err(CacheError::InvalidInput);
        }
        let entries = self.merge_school(query.from, query.to, Vec::new(), query.include_hidden)?;
        let sources = [
            ReadonlyFeature::Bykc,
            ReadonlyFeature::Spoc,
            ReadonlyFeature::Judge,
            ReadonlyFeature::Cgyy,
            ReadonlyFeature::Signin,
            ReadonlyFeature::Exam,
            ReadonlyFeature::Ygdk,
            ReadonlyFeature::Schedule,
        ]
        .into_iter()
        .map(|feature| AgendaSourceAvailability {
            feature,
            observations: Vec::new(),
            missing_scopes: Vec::new(),
            semester_imported: (feature == ReadonlyFeature::Schedule).then_some(false),
            unprojectable_count: 0,
        })
        .collect();
        Ok(AgendaQueryResult { entries, sources })
    }
}
impl OfflineCache {
    /// 仅比较本机随机账号别名，供宿主在学校缓存降级前排除串号。
    #[must_use]
    pub fn matches_agenda_account(&self, agenda: &AgendaStore) -> bool {
        self.account_alias() == agenda.account_alias()
    }
    /// 只读本地业务缓存与同账号日程，返回日期范围内的统一条目和逐范围缓存时间。
    ///
    /// # Errors
    /// 账号不符、退出、输入非法、记录损坏、展开或缓存页数超限时返回稳定本地错误。
    pub fn query_agenda(
        &self,
        agenda: &AgendaStore,
        query: &AgendaQuery,
    ) -> CacheResult<AgendaQueryResult> {
        if self.account_alias() != agenda.account_alias() {
            return Err(CacheError::InvalidInput);
        }
        let (school, sources) = self.school_agenda(query)?;
        let entries = agenda.merge_school(query.from, query.to, school, query.include_hidden)?;
        Ok(AgendaQueryResult { entries, sources })
    }
    fn school_agenda(
        &self,
        query: &AgendaQuery,
    ) -> CacheResult<(Vec<SchoolAgendaItem>, Vec<AgendaSourceAvailability>)> {
        if !query.now.valid()
            || query.from >= query.to
            || (query.to - query.from).num_days() > 3660
            || query.term.trim().is_empty()
        {
            return Err(CacheError::InvalidInput);
        }
        let mut records = Vec::new();
        let mut sources = Vec::new();
        for feature in [
            ReadonlyFeature::Bykc,
            ReadonlyFeature::Spoc,
            ReadonlyFeature::Judge,
            ReadonlyFeature::Cgyy,
            ReadonlyFeature::Signin,
            ReadonlyFeature::Exam,
            ReadonlyFeature::Ygdk,
            ReadonlyFeature::Schedule,
        ] {
            let mut state = AgendaSourceAvailability {
                feature,
                observations: Vec::new(),
                missing_scopes: Vec::new(),
                semester_imported: None,
                unprojectable_count: 0,
            };
            self.agenda_source(query, &mut state, &mut records)?;
            sources.push(state);
        }
        let current_week = records.iter().find_map(|r| match &r.payload {
            CachePayload::Weeks(weeks) => current_week(weeks, &query.term, query.now),
            _ => None,
        });
        let (school, unavailable) = crate::agenda::projection::project_with_diagnostics(
            &records,
            &SchoolAgendaContext {
                now: query.now,
                current_week,
                ygdk: query.ygdk,
            },
        )?;
        for state in &mut sources {
            state.unprojectable_count += unavailable.get(&state.feature).copied().unwrap_or(0);
        }
        Ok((school, sources))
    }
    fn agenda_source(
        &self,
        q: &AgendaQuery,
        state: &mut AgendaSourceAvailability,
        records: &mut Vec<CacheRecord>,
    ) -> CacheResult<()> {
        let scope = |query| CacheScope {
            route: q.route,
            query,
        };
        let now = q.now.datetime.timestamp();
        match state.feature {
            ReadonlyFeature::Spoc => {
                let record = super::home_cache::spoc::read(self, q.route, now)?;
                collect(record, scope(CacheQuery::SpocSelection), state, records);
            }
            ReadonlyFeature::Ygdk => {
                let day = q.now.datetime.date_naive();
                let monday = day - Duration::days(i64::from(day.weekday().num_days_from_monday()));
                let record = super::home_cache::ygdk::read(self, q.route, now)?;
                collect(
                    record,
                    scope(CacheQuery::YgdkOverviewSelection {
                        week_start: monday.to_string(),
                    }),
                    state,
                    records,
                );
            }
            ReadonlyFeature::Schedule => self.agenda_schedule(q, state, records)?,
            ReadonlyFeature::Cgyy => {
                let first_scope = scope(CacheQuery::CgyyOrders { page: 0, size: 20 });
                let first = self.read(&first_scope, now)?;
                let pages = match &first {
                    Some(CacheRecord {
                        payload: CachePayload::CgyyOrders(page),
                        ..
                    }) => page.total_pages.max(1),
                    _ => 1,
                };
                if pages > 1000 {
                    return Err(CacheError::Capacity);
                }
                collect(first, first_scope, state, records);
                for page in 1..pages {
                    let page_scope = scope(CacheQuery::CgyyOrders { page, size: 20 });
                    collect(self.read(&page_scope, now)?, page_scope, state, records);
                }
            }
            feature => {
                let query = match feature {
                    ReadonlyFeature::Bykc => CacheQuery::BykcChosen,
                    ReadonlyFeature::Judge => CacheQuery::JudgeSummaries {
                        include_expired: false,
                    },
                    ReadonlyFeature::Signin => CacheQuery::SigninToday {
                        date: q.now.datetime.format("%Y%m%d").to_string(),
                    },
                    ReadonlyFeature::Exam => CacheQuery::Exams {
                        term: q.term.clone(),
                    },
                    _ => return Err(CacheError::InvalidInput),
                };
                let scope = scope(query);
                collect(self.read(&scope, now)?, scope, state, records);
            }
        }
        Ok(())
    }
    fn agenda_schedule(
        &self,
        q: &AgendaQuery,
        state: &mut AgendaSourceAvailability,
        records: &mut Vec<CacheRecord>,
    ) -> CacheResult<()> {
        let now = q.now.datetime.timestamp();
        let imported_scope = CacheScope {
            route: q.route,
            query: CacheQuery::ImportedSchedules,
        };
        let imported = self.read(&imported_scope, now)?;
        state.semester_imported = Some(
            matches!(&imported, Some(CacheRecord { payload: CachePayload::ImportedSchedules(values), .. }) if values.iter().any(|s| s.term_code == q.term)),
        );
        let scope = CacheScope {
            route: q.route,
            query: CacheQuery::ScheduleWeeks {
                term: q.term.clone(),
            },
        };
        let weeks = self.agenda_schedule_record(&scope, now)?;
        let values = match &weeks {
            Some(CacheRecord {
                payload: CachePayload::Weeks(weeks),
                ..
            }) => {
                if let Ok(weeks) = CachedSemesterSchedule::normalized_weeks(&q.term, weeks.clone())
                {
                    weeks
                } else {
                    state.unprojectable_count += weeks.len().max(1);
                    Vec::new()
                }
            }
            _ => Vec::new(),
        };
        collect(weeks, scope, state, records);
        for week in values {
            let start = crate::agenda::projection::parse_date(&week.start_date);
            let end = crate::agenda::projection::parse_date(&week.end_date);
            if week.term != q.term
                || week.serial_number <= 0
                || start
                    .zip(end)
                    .is_none_or(|(a, b)| !(0..=6).contains(&(b - a).num_days()))
            {
                state.unprojectable_count += 1;
                continue;
            }
            if !start.zip(end).is_some_and(|(a, b)| a < q.to && b >= q.from) {
                continue;
            }
            let scope = CacheScope {
                route: q.route,
                query: CacheQuery::ScheduleWeek {
                    term: q.term.clone(),
                    week: week.serial_number,
                },
            };
            collect(
                self.agenda_schedule_record(&scope, now)?,
                scope,
                state,
                records,
            );
        }
        Ok(())
    }
    fn agenda_schedule_record(
        &self,
        scope: &CacheScope,
        now: i64,
    ) -> CacheResult<Option<CacheRecord>> {
        if let Some(record) = self.read(scope, now)? {
            return Ok(Some(record));
        }
        self.repository(|r| r.read_imported_schedule(scope.route, scope.query.clone(), now))
    }
}
fn collect(
    record: Option<CacheRecord>,
    missing: CacheScope,
    state: &mut AgendaSourceAvailability,
    records: &mut Vec<CacheRecord>,
) {
    if let Some(record) = record {
        state.observations.push((&record).into());
        records.push(record);
    } else {
        state.missing_scopes.push(missing);
    }
}
fn current_week(weeks: &[Week], term: &str, now: AgendaTime) -> Option<Week> {
    let weeks = CachedSemesterSchedule::normalized_weeks(term, weeks.to_vec()).ok()?;
    let day = now.datetime.date_naive();
    let candidates = weeks
        .iter()
        .filter(|w| {
            w.term == term
                && w.serial_number > 0
                && crate::agenda::projection::parse_date(&w.start_date).is_some_and(|s| s <= day)
                && crate::agenda::projection::parse_date(&w.end_date).is_some_and(|e| day <= e)
        })
        .collect::<Vec<_>>();
    let [week] = candidates.as_slice() else {
        return None;
    };
    let mut week = (*week).clone();
    week.cur_week = true;
    Some(week)
}
#[cfg(test)]
mod tests;
