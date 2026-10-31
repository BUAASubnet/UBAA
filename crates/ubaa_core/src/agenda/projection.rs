//! 时间解析和来源选择沿现有 Dart 首页规则，输入仅为公开持久读结果。
use crate::{
    cache::{CacheCompleteness, CacheError, CachePayload, CacheQuery, CacheRecord, CacheResult},
    domain::agenda::{
        AgendaNavigation, AgendaTime, AgendaTiming, SchoolAgendaItem, SchoolAgendaKey,
        SchoolAgendaStatus, YgdkAgendaSettings,
    },
    domain::{ReadonlyFeature, Week, WeeklySchedule},
};
use chrono::{Datelike, Duration, NaiveDate, NaiveDateTime, NaiveTime, TimeZone, Timelike};
use regex::Regex;
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::LazyLock,
};

#[derive(Clone, Debug)]
pub struct SchoolAgendaContext {
    pub now: AgendaTime,
    pub current_week: Option<Week>,
    pub ygdk: YgdkAgendaSettings,
}
/// 投影已明确范围的公开缓存，不读取文件、不调用网络。
/// 完整日程保留历史和已完成事项；`home_todo` 标记与 `buildHomeTodos` 一致。
///
/// # Errors
/// 时间非法时返回本地输入错误。
pub fn project_school_agenda(
    records: &[CacheRecord],
    context: &SchoolAgendaContext,
) -> CacheResult<Vec<SchoolAgendaItem>> {
    project_with_diagnostics(records, context).map(|(items, _)| items)
}
pub(crate) fn project_with_diagnostics(
    records: &[CacheRecord],
    context: &SchoolAgendaContext,
) -> CacheResult<(Vec<SchoolAgendaItem>, BTreeMap<ReadonlyFeature, usize>)> {
    if !context.now.valid() {
        return Err(CacheError::InvalidInput);
    }
    let mut items = Vec::new();
    let mut unavailable = BTreeMap::new();
    let now = context.now;
    // 顺序与 Dart 首页一致；Rust 稳定排序保留同时间的来源和响应顺序。
    for (source, feature) in [
        ("bykc", ReadonlyFeature::Bykc),
        ("spoc", ReadonlyFeature::Spoc),
        ("judge", ReadonlyFeature::Judge),
        ("cgyy", ReadonlyFeature::Cgyy),
        ("signin", ReadonlyFeature::Signin),
        ("exam", ReadonlyFeature::Exam),
        ("ygdk", ReadonlyFeature::Ygdk),
        ("schedule", ReadonlyFeature::Schedule),
    ] {
        for record in records {
            let mut add = |item: Option<SchoolAgendaItem>| {
                if let Some(item) = item {
                    items.push(item);
                } else if feature != ReadonlyFeature::Ygdk {
                    *unavailable.entry(feature).or_default() += 1;
                }
            };
            match (source, &record.scope.query, &record.payload) {
                ("bykc", CacheQuery::BykcChosen, CachePayload::BykcChosen(v)) => {
                    for v in &v.courses {
                        add(super::school::bykc(v, now));
                    }
                }
                ("spoc", CacheQuery::SpocTerm { .. }, CachePayload::SpocAssignments(v)) => {
                    for v in &v.assignments {
                        add(super::school::spoc(v, now));
                    }
                }
                ("judge", CacheQuery::JudgeSummaries { .. }, CachePayload::JudgeSummaries(v)) => {
                    for v in v {
                        add(super::school::judge(v, now));
                    }
                }
                ("cgyy", CacheQuery::CgyyOrders { .. }, CachePayload::CgyyOrders(v)) => {
                    for v in &v.content {
                        add(super::school::cgyy(v, now));
                    }
                }
                ("signin", CacheQuery::SigninToday { date }, CachePayload::SigninToday(v)) => {
                    if let Ok(date) = NaiveDate::parse_from_str(date, "%Y%m%d") {
                        for v in v {
                            add(super::school::signin(v, date, now));
                        }
                    }
                }
                ("exam", CacheQuery::Exams { term }, CachePayload::Exams(v)) => {
                    for v in &v.arranged {
                        add(super::school::exam(v, term, now));
                    }
                }
                (
                    "ygdk",
                    CacheQuery::YgdkOverviewPeriod { week_start, .. },
                    CachePayload::YgdkOverview(v),
                ) if record.completeness == CacheCompleteness::Complete
                    && parse_date(week_start).is_some_and(|monday| {
                        monday
                            == now.datetime.date_naive()
                                - Duration::days(i64::from(
                                    now.datetime.weekday().num_days_from_monday(),
                                ))
                    }) =>
                {
                    if let Some(week) = &context.current_week {
                        add(super::school::ygdk(v, week, now, context.ygdk));
                    }
                }
                (
                    "schedule",
                    CacheQuery::ScheduleWeek { term, week },
                    CachePayload::Week(schedule),
                ) => {
                    let (rows, skipped) = project_schedule(records, term, *week, schedule)?;
                    items.extend(rows);
                    *unavailable.entry(feature).or_default() += skipped;
                }
                _ => {}
            }
        }
    }
    remove_ambiguous_duplicates(&mut items, &mut unavailable);
    if items.len() > usize::from(u16::MAX) {
        return Err(CacheError::Capacity);
    }
    items.sort_by_key(|item| item.sort_time);
    Ok((items, unavailable))
}
fn project_schedule(
    records: &[CacheRecord],
    term: &str,
    week: i32,
    schedule: &WeeklySchedule,
) -> CacheResult<(Vec<SchoolAgendaItem>, usize)> {
    let weeks = records
        .iter()
        .find_map(|r| match (&r.scope.query, &r.payload) {
            (CacheQuery::ScheduleWeeks { term: t }, CachePayload::Weeks(w)) if t == term => Some(w),
            _ => None,
        });
    if let Some(weeks) = weeks {
        super::schedule::project_week(term, week, weeks, schedule)
    } else {
        Ok((Vec::new(), schedule.arranged_list.len()))
    }
}
fn remove_ambiguous_duplicates(
    items: &mut Vec<SchoolAgendaItem>,
    unavailable: &mut BTreeMap<ReadonlyFeature, usize>,
) {
    let mut seen = BTreeMap::new();
    let mut conflicts = BTreeSet::new();
    for item in items.iter() {
        let key = (item.key.source.as_str(), item.key.upstream_id.as_str());
        if let Some(previous) = seen.insert(key, item)
            && previous != item
        {
            conflicts.insert(key);
        }
    }
    let conflicts = conflicts
        .into_iter()
        .map(|(source, id)| (source.to_owned(), id.to_owned()))
        .collect::<BTreeSet<_>>();
    let mut unique = BTreeSet::new();
    items.retain(|item| {
        let key = (item.key.source.clone(), item.key.upstream_id.clone());
        let keep = !conflicts.contains(&key) && unique.insert(key);
        if !keep {
            *unavailable.entry(item.navigation.feature()).or_default() += 1;
        }
        keep
    });
}
pub(super) fn school_item(
    source: &str,
    upstream_id: String,
    title: &str,
    timing: AgendaTiming,
    upstream_status: SchoolAgendaStatus,
    navigation: AgendaNavigation,
) -> SchoolAgendaItem {
    SchoolAgendaItem {
        key: SchoolAgendaKey {
            source: source.into(),
            upstream_id,
        },
        sort_time: timing.sort_time(),
        timing,
        title: title.into(),
        subtitle: String::new(),
        location: None,
        status_label: String::new(),
        upstream_status,
        navigation,
        home_todo: false,
    }
}
pub(super) fn join(values: &[Option<&str>], fallback: &str, separator: &str) -> String {
    let text = values
        .iter()
        .flatten()
        .filter(|s| !s.trim().is_empty())
        .copied()
        .collect::<Vec<_>>()
        .join(separator);
    if text.is_empty() {
        fallback.into()
    } else {
        text
    }
}
pub(crate) fn parse_date(raw: &str) -> Option<NaiveDate> {
    let date = NaiveDate::parse_from_str(raw, "%Y-%m-%d").ok()?;
    (date.format("%Y-%m-%d").to_string() == raw).then_some(date)
}
pub(super) fn parse_time(raw: Option<&str>, today: Option<NaiveDate>) -> Option<AgendaTime> {
    static FULL: LazyLock<Regex> = LazyLock::new(|| {
        Regex::new(
            r"^[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}(?::[0-9]{2}(?:\.[0-9]{1,9})?)?$",
        )
        .expect("固定时间格式")
    });
    static CLOCK: LazyLock<Regex> =
        LazyLock::new(|| Regex::new(r"^[0-9]{1,2}:[0-9]{2}(?::[0-9]{2})?$").expect("固定钟点格式"));
    let text = raw?.trim();
    let datetime = if FULL.is_match(text) {
        let day = parse_date(&text[..10])?;
        let clock = &text[11..];
        let time = NaiveTime::parse_from_str(
            clock,
            if clock.len() == 5 {
                "%H:%M"
            } else {
                "%H:%M:%S%.f"
            },
        )
        .ok()?;
        day.and_time(time)
    } else {
        if !CLOCK.is_match(text) {
            return None;
        }
        let clock = NaiveTime::parse_from_str(
            text,
            if text.matches(':').count() == 1 {
                "%H:%M"
            } else {
                "%H:%M:%S"
            },
        )
        .ok()?;
        NaiveDateTime::new(today?, clock)
    };
    if datetime.nanosecond() >= 1_000_000_000 {
        return None;
    }
    Some(AgendaTime::new(
        chrono_tz::Asia::Shanghai
            .from_local_datetime(&datetime.with_nanosecond(0)?)
            .single()?
            .fixed_offset(),
    ))
}
