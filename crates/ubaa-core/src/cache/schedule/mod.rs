//! 完整导入单独保存；不能将零散周缓存拼接成学期覆盖证明。
use super::{
    CacheCompleteness, CacheError, CachePayload, CachePublication, CacheQuery, CacheReadTicket,
    CacheRecord, CacheResult, CacheScope, OfflineRepository,
};
use crate::domain::{ConnectionMode, Term, TodayClass, Week, WeeklySchedule};
use chrono::{Datelike, NaiveDate};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

/// 一次完整导入取得的学期；时间属于本学期，不随其他学期导入更新。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CachedSemesterSchedule {
    pub term_code: String,
    pub terms: Vec<Term>,
    pub weeks: Vec<Week>,
    pub schedules: BTreeMap<i32, WeeklySchedule>,
    pub fetched_at: i64,
}
impl CachedSemesterSchedule {
    /// 沿冻结导入规则规范化日期并核对所有周次，不检查本科课表code等于学期。
    ///
    /// # Errors
    /// 学期、周次、日期覆盖或完整集合不可信时返回 `InvalidInput`。
    pub fn new(
        term_code: String,
        terms: Vec<Term>,
        mut weeks: Vec<Week>,
        schedules: BTreeMap<i32, WeeklySchedule>,
        fetched_at: i64,
    ) -> CacheResult<Self> {
        for week in &mut weeks {
            week.start_date = normalize_date(&week.start_date)?;
            week.end_date = normalize_date(&week.end_date)?;
        }
        let value = Self {
            term_code,
            terms,
            weeks,
            schedules,
            fetched_at,
        };
        if !value.is_valid() {
            return Err(CacheError::InvalidInput);
        }
        Ok(value)
    }
    pub(super) fn is_valid(&self) -> bool {
        if self.term_code.trim().is_empty()
            || self.term_code.len() > 1024
            || self.fetched_at < 0
            || self.weeks.is_empty()
            || !self
                .terms
                .iter()
                .any(|term| term.item_code == self.term_code)
        {
            return false;
        }
        let mut numbers = BTreeSet::new();
        let mut ranges = Vec::new();
        for week in &self.weeks {
            let (Some(start), Some(end)) = (date(&week.start_date), date(&week.end_date)) else {
                return false;
            };
            if week.term != self.term_code
                || week.serial_number <= 0
                || !numbers.insert(week.serial_number)
                || !(0..=6).contains(&(end - start).num_days())
            {
                return false;
            }
            ranges.push((start, end));
        }
        ranges.sort_unstable();
        numbers == self.schedules.keys().copied().collect()
            && ranges.windows(2).all(|pair| pair[0].1 < pair[1].0)
    }
    fn covering_week(&self, requested: NaiveDate) -> Option<&Week> {
        self.weeks.iter().find(|week| {
            date(&week.start_date).is_some_and(|start| start <= requested)
                && date(&week.end_date).is_some_and(|end| requested <= end)
        })
    }
    fn weeks_at(&self, now: i64) -> CacheResult<Vec<Week>> {
        let day = chrono::DateTime::<chrono::Utc>::from_timestamp(now, 0)
            .ok_or(CacheError::InvalidInput)?
            .with_timezone(
                &chrono::FixedOffset::east_opt(8 * 3600).ok_or(CacheError::InvalidInput)?,
            )
            .date_naive();
        Ok(self
            .weeks
            .iter()
            .cloned()
            .map(|mut week| {
                week.cur_week = date(&week.start_date)
                    .zip(date(&week.end_date))
                    .is_some_and(|(start, end)| start <= day && day <= end);
                week
            })
            .collect())
    }
    fn first_day(&self) -> Option<NaiveDate> {
        self.weeks
            .iter()
            .filter_map(|week| date(&week.start_date))
            .min()
    }
    /// 只有明确覆盖的日期能投影为空课表；未知星期不推断无课。
    ///
    /// # Errors
    /// 日期不规范或快照不完整时返回 `InvalidInput`。
    pub fn today(&self, requested: &str) -> CacheResult<Option<Vec<TodayClass>>> {
        let requested = date(requested).ok_or(CacheError::InvalidInput)?;
        if !self.is_valid() {
            return Err(CacheError::InvalidInput);
        }
        let Some(week) = self.covering_week(requested) else {
            return Ok(None);
        };
        let schedule = &self.schedules[&week.serial_number];
        if schedule
            .arranged_list
            .iter()
            .any(|course| !course.day_of_week.is_some_and(|day| (1..=7).contains(&day)))
        {
            return Ok(None);
        }
        let day = i32::try_from(requested.weekday().number_from_monday())
            .map_err(|_| CacheError::InvalidInput)?;
        let mut classes: Vec<_> = schedule
            .arranged_list
            .iter()
            .filter(|course| course.day_of_week == Some(day))
            .collect();
        classes.sort_by(|a, b| {
            a.begin_time
                .as_deref()
                .unwrap_or_default()
                .cmp(b.begin_time.as_deref().unwrap_or_default())
        });
        Ok(Some(
            classes
                .into_iter()
                .map(|course| TodayClass {
                    biz_name: course.course_name.clone(),
                    place: course.place_name.clone(),
                    time: Some(
                        [course.begin_time.as_deref(), course.end_time.as_deref()]
                            .into_iter()
                            .flatten()
                            .collect::<Vec<_>>()
                            .join("-"),
                    ),
                    short_name: Some(course.course_name.clone()),
                })
                .collect(),
        ))
    }
}
fn date(raw: &str) -> Option<NaiveDate> {
    let value = NaiveDate::parse_from_str(raw, "%Y-%m-%d").ok()?;
    (value.format("%Y-%m-%d").to_string() == raw).then_some(value)
}
fn normalize_date(raw: &str) -> CacheResult<String> {
    let raw = raw
        .trim()
        .split([' ', 'T'])
        .next()
        .ok_or(CacheError::InvalidInput)?;
    let fields: Vec<_> = raw.split('-').collect();
    if fields.len() != 3
        || fields[0].len() != 4
        || !(1..=2).contains(&fields[1].len())
        || !(1..=2).contains(&fields[2].len())
        || fields
            .iter()
            .any(|field| !field.bytes().all(|byte| byte.is_ascii_digit()))
    {
        return Err(CacheError::InvalidInput);
    }
    let value = NaiveDate::parse_from_str(raw, "%Y-%m-%d").map_err(|_| CacheError::InvalidInput)?;
    Ok(value.format("%Y-%m-%d").to_string())
}
pub(super) fn valid_collection(values: &[CachedSemesterSchedule]) -> bool {
    let mut terms = BTreeSet::new();
    values
        .iter()
        .all(|value| value.is_valid() && terms.insert(&value.term_code))
}
impl OfflineRepository {
    /// 合并完整学期后原子替换导入集合，失败保留所有既有学期。
    ///
    /// # Errors
    /// 旧票据、错误范围、不完整学期、容量或存储错误不发布新版本。
    pub fn publish_imported_semester(
        &mut self,
        ticket: &CacheReadTicket,
        value: CachedSemesterSchedule,
    ) -> CacheResult<CachePublication> {
        self.validate_read(ticket)?;
        if ticket.scope.query != CacheQuery::ImportedSchedules || !value.is_valid() {
            return Err(CacheError::InvalidInput);
        }
        let mut values = match self.read(&ticket.scope, value.fetched_at)? {
            Some(CacheRecord {
                payload: CachePayload::ImportedSchedules(values),
                ..
            }) => values,
            None => Vec::new(),
            Some(_) => return Err(CacheError::Corrupt),
        };
        values.retain(|existing| existing.term_code != value.term_code);
        let fetched_at = value.fetched_at;
        values.push(value);
        // publish事务再验证票据，跨连接竞争不能覆盖更新的集合。
        self.publish(
            ticket,
            CachePayload::ImportedSchedules(values),
            fetched_at,
            CacheCompleteness::Complete,
        )
    }
    /// 按明确学期/周次或日期投影；返回的时间仍属于原完整导入。
    ///
    /// # Errors
    /// 不支持的范围、非法日期、仓库或记录损坏时返回缓存错误。
    pub fn read_imported_schedule(
        &mut self,
        route: ConnectionMode,
        query: CacheQuery,
        now: i64,
    ) -> CacheResult<Option<CacheRecord>> {
        let scope = CacheScope { route, query };
        scope.validate()?;
        if !matches!(
            &scope.query,
            CacheQuery::ScheduleToday { .. }
                | CacheQuery::ScheduleWeek { .. }
                | CacheQuery::ScheduleWeeks { .. }
        ) {
            return Err(CacheError::InvalidInput);
        }
        let Some(mut record) = self.read(
            &CacheScope {
                route,
                query: CacheQuery::ImportedSchedules,
            },
            now,
        )?
        else {
            return Ok(None);
        };
        let CachePayload::ImportedSchedules(values) = &record.payload else {
            return Err(CacheError::Corrupt);
        };
        let value = match &scope.query {
            CacheQuery::ScheduleWeek { term, .. } | CacheQuery::ScheduleWeeks { term } => {
                values.iter().find(|value| value.term_code == *term)
            }
            CacheQuery::ScheduleToday { date: requested } => {
                let requested = date(requested).ok_or(CacheError::InvalidInput)?;
                values
                    .iter()
                    .filter(|value| value.covering_week(requested).is_some())
                    .max_by_key(|value| value.first_day())
            }
            _ => None,
        };
        let Some(value) = value else {
            return Ok(None);
        };
        let payload = match &scope.query {
            CacheQuery::ScheduleWeek { week, .. } => {
                value.schedules.get(week).cloned().map(CachePayload::Week)
            }
            CacheQuery::ScheduleWeeks { .. } => Some(CachePayload::Weeks(value.weeks_at(now)?)),
            CacheQuery::ScheduleToday { date } => value.today(date)?.map(CachePayload::Today),
            _ => None,
        };
        let Some(payload) = payload else {
            return Ok(None);
        };
        record.fetched_at = value.fetched_at;
        record.last_attempt_at = value.fetched_at;
        record.last_verified_at = value.fetched_at;
        record.last_attempt_succeeded = true;
        record.scope = scope;
        record.payload = payload;
        Ok(Some(record))
    }
}
#[cfg(test)]
mod tests;
