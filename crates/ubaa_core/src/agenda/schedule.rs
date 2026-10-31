//! 日期沿 CachedSemesterSchedule.today 的真实周覆盖，节次沿 Dart scheduleSectionTimes。
use super::projection::{parse_date, parse_time, school_item};
use crate::cache::{CacheError, CacheResult};
use crate::domain::{
    CourseClass, Week, WeeklySchedule,
    agenda::{AgendaNavigation, AgendaTiming, SchoolAgendaItem, SchoolAgendaStatus},
};
use chrono::{Datelike, Duration, NaiveDate};

const STANDARD: [(&str, &str); 14] = [
    ("08:00", "08:45"),
    ("08:50", "09:35"),
    ("09:50", "10:35"),
    ("10:40", "11:25"),
    ("11:30", "12:15"),
    ("14:00", "14:45"),
    ("14:50", "15:35"),
    ("15:50", "16:35"),
    ("16:40", "17:25"),
    ("17:30", "18:15"),
    ("19:00", "19:45"),
    ("19:50", "20:35"),
    ("20:40", "21:25"),
    ("21:30", "22:15"),
];
fn single<'a>(values: impl Iterator<Item = &'a str>) -> Option<&'a str> {
    let values = values.collect::<std::collections::BTreeSet<_>>();
    (values.len() == 1).then(|| *values.first().expect("唯一值"))
}
fn boundary(schedule: &WeeklySchedule, section: i32, start: bool) -> Option<&str> {
    if let Some(index) = section.checked_sub(1).and_then(|n| usize::try_from(n).ok())
        && let Some((a, b)) = STANDARD.get(index)
    {
        return Some(if start { a } else { b });
    }
    let explicit = schedule
        .section_times
        .iter()
        .filter(|t| t.section == section)
        .filter_map(|t| {
            if start {
                t.start.as_deref()
            } else {
                t.end.as_deref()
            }
        })
        .collect::<Vec<_>>();
    if !explicit.is_empty() {
        return single(explicit.into_iter());
    }
    single(schedule.arranged_list.iter().filter(|c| if start { c.begin_section } else { c.end_section } == Some(section))
        .filter_map(|c| if start { c.begin_time.as_deref() } else { c.end_time.as_deref() }))
}
pub(super) fn project_week(
    term: &str,
    number: i32,
    weeks: &[Week],
    schedule: &WeeklySchedule,
) -> CacheResult<(Vec<SchoolAgendaItem>, usize)> {
    let Ok(normalized) =
        crate::cache::CachedSemesterSchedule::normalized_weeks(term, weeks.to_vec())
    else {
        return Ok((Vec::new(), schedule.arranged_list.len()));
    };
    let weeks = normalized.as_slice();
    let candidates = weeks
        .iter()
        .filter(|w| w.term == term && w.serial_number == number)
        .collect::<Vec<_>>();
    let [week] = candidates.as_slice() else {
        return Ok((Vec::new(), schedule.arranged_list.len()));
    };
    let (Some(start), Some(end)) = (parse_date(&week.start_date), parse_date(&week.end_date))
    else {
        return Ok((Vec::new(), schedule.arranged_list.len()));
    };
    if number <= 0
        || !(0..=6).contains(&(end - start).num_days())
        || schedule
            .arranged_list
            .iter()
            .any(|c| !c.day_of_week.is_some_and(|n| (1..=7).contains(&n)))
    {
        return Ok((Vec::new(), schedule.arranged_list.len()));
    }
    let mut items = Vec::new();
    let mut unavailable = 0;
    for course in &schedule.arranged_list {
        let Some(begin) = course.begin_section.filter(|s| *s > 0) else {
            unavailable += 1;
            continue;
        };
        let end_section = course.end_section.unwrap_or(begin);
        if end_section < begin || course.course_code.trim().is_empty() {
            unavailable += 1;
            continue;
        }
        if i64::from(end_section) - i64::from(begin) >= i64::from(u16::MAX) {
            return Err(CacheError::Capacity);
        }
        let Some(date) = course_date(term, course.day_of_week, weeks, start, end) else {
            unavailable += 1;
            continue;
        };
        let before = items.len();
        for section in begin..=end_section {
            if let Some(item) = project_course(term, number, schedule, course, date, section) {
                items.push(item);
                if items.len() > usize::from(u16::MAX) {
                    return Err(CacheError::Capacity);
                }
            }
        }
        if items.len() == before {
            unavailable += 1;
        }
    }
    Ok((items, unavailable))
}

fn course_date(
    term: &str,
    day: Option<i32>,
    weeks: &[Week],
    first: NaiveDate,
    last: NaiveDate,
) -> Option<NaiveDate> {
    let day = day?;
    let date = (0..=(last - first).num_days())
        .map(|n| first + Duration::days(n))
        .find(|d| i32::try_from(d.weekday().number_from_monday()).ok() == Some(day))?;
    // 元数据冲突时不选择任意教学周，也不将缺星期当成无课。
    if weeks
        .iter()
        .filter(|w| {
            w.term == term
                && parse_date(&w.start_date).is_some_and(|s| s <= date)
                && parse_date(&w.end_date).is_some_and(|e| date <= e)
        })
        .count()
        != 1
    {
        return None;
    }
    Some(date)
}
fn project_course(
    term: &str,
    week: i32,
    schedule: &WeeklySchedule,
    course: &CourseClass,
    date: NaiveDate,
    section: i32,
) -> Option<SchoolAgendaItem> {
    let day = course.day_of_week?;
    let start = parse_time(boundary(schedule, section, true), Some(date));
    let end = parse_time(
        course
            .end_section
            .and_then(|_| boundary(schedule, section, false)),
        Some(date),
    );
    let timing =
        if (start.is_none() && end.is_none()) || start.zip(end).is_some_and(|(a, b)| b <= a) {
            AgendaTiming::AllDay {
                from: date,
                to: date.succ_opt()?,
            }
        } else {
            AgendaTiming::Period { start, end }
        };
    let id = serde_json::to_string(&(
        term,
        &course.course_code,
        &course.course_serial_no,
        week,
        day,
        section,
    ))
    .ok()?;
    let mut item = school_item(
        "schedule",
        id,
        &course.course_name,
        timing,
        SchoolAgendaStatus::Schedule {
            begin_time: course.begin_time.clone(),
            end_time: course.end_time.clone(),
        },
        AgendaNavigation::Schedule {
            term: term.into(),
            week,
            course_code: course.course_code.clone(),
            serial: course.course_serial_no.clone(),
            day,
            section,
        },
    );
    item.location.clone_from(&course.place_name);
    item.subtitle = course.weeks_and_teachers.clone().unwrap_or_default();
    item.status_label = "课程".into();
    Some(item)
}
