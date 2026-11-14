//! 使用已保存校历限定默认刷新；完整往期课程不再自动检查索引。
use super::{
    CacheCompleteness, CachePayload, CacheQuery, CacheScope, JudgeRefresh, OfflineReadError,
};
use crate::domain::JudgeAssignmentSummary;
use chrono::NaiveDate;

#[derive(Clone, Copy)]
pub(super) struct Semester {
    start: i64,
    end: i64,
}
impl Semester {
    pub(super) fn covers(self, now: i64) -> bool {
        self.start <= now && now <= self.end
    }
    fn dates(item: &JudgeAssignmentSummary) -> Option<(i64, i64)> {
        let start = super::policy::timestamp(item.start_time.as_deref())?;
        let end = super::policy::timestamp(item.due_time.as_deref())?;
        (start <= end).then_some((start, end))
    }
    pub(super) fn contains(self, item: &JudgeAssignmentSummary) -> bool {
        Self::dates(item).is_none_or(|(start, end)| start <= self.end && end >= self.start)
    }
    fn past(self, item: &JudgeAssignmentSummary) -> bool {
        Self::dates(item).is_some_and(|(_, end)| end < self.start)
    }
}

pub(super) fn load(
    cache: &super::OfflineCache,
    route: crate::domain::ConnectionMode,
    now: i64,
) -> Result<Option<Semester>, super::CacheError> {
    use crate::facade::AcademicQuery;
    let Some(terms) = cache.read_academic(route, &AcademicQuery::Terms)? else {
        return Ok(None);
    };
    let CachePayload::Terms(terms) = terms.payload else {
        return Ok(None);
    };
    let Some(term) = terms.iter().find(|t| t.selected) else {
        return Ok(None);
    };
    let Some(weeks) = cache.read_academic(
        route,
        &AcademicQuery::Weeks {
            term: term.item_code.clone(),
        },
    )?
    else {
        return Ok(None);
    };
    if weeks.completeness != CacheCompleteness::Complete {
        return Ok(None);
    }
    let CachePayload::Weeks(weeks) = weeks.payload else {
        return Ok(None);
    };
    let Ok(weeks) = crate::facade::CachedSemesterSchedule::normalized_weeks(&term.item_code, weeks)
    else {
        return Ok(None);
    };
    let dates: Option<Vec<_>> = weeks
        .iter()
        .map(|week| {
            let start = NaiveDate::parse_from_str(&week.start_date, "%Y-%m-%d").ok()?;
            let end = NaiveDate::parse_from_str(&week.end_date, "%Y-%m-%d").ok()?;
            Some((start, end))
        })
        .collect();
    let Some(dates) = dates else { return Ok(None) };
    let Some(start) = dates.iter().map(|(start, _)| start).min() else {
        return Ok(None);
    };
    let Some(end) = dates.iter().map(|(_, end)| end).max() else {
        return Ok(None);
    };
    let range = Semester {
        start: start
            .and_hms_opt(0, 0, 0)
            .expect("合法时间")
            .and_utc()
            .timestamp()
            - 8 * 3600,
        end: end
            .and_hms_opt(23, 59, 59)
            .expect("合法时间")
            .and_utc()
            .timestamp()
            - 8 * 3600,
    };
    Ok((range.start <= now).then_some(range))
}

pub(super) fn skip_past_courses(refresh: &mut JudgeRefresh) -> Result<(), OfflineReadError> {
    let Some(semester) = refresh.known_semester else {
        return Ok(());
    };
    while refresh.scan.cursor.current_assignment().is_none() {
        let Some(course) = refresh.scan.cursor.current_course() else {
            break;
        };
        if explicit_course(refresh, &course.course_id) {
            break;
        }
        let record = refresh.scan.cache.read(
            &CacheScope {
                route: refresh.scan.resolution.mode,
                query: CacheQuery::JudgeCourseReview {
                    course_id: course.course_id.clone(),
                },
            },
            chrono::Utc::now().timestamp(),
        );
        let record = match record {
            Ok(Some(record)) => record,
            Ok(None) => break,
            Err(error) => {
                super::remember_save(&mut refresh.save_error, Err::<(), _>(error))?;
                break;
            }
        };
        let CachePayload::JudgeCourseReview(review) = record.payload else {
            break;
        };
        if record.completeness != CacheCompleteness::Complete
            || review.summaries.is_empty()
            || !review.summaries.iter().all(|s| semester.past(s))
        {
            break;
        }
        // 已确认往期整课从当前投影移除，原课程摘要和详情继续保存在各自缓存中。
        refresh
            .summaries
            .retain(|(id, _), _| id != &course.course_id);
        refresh.scan.cursor.accept_assignments(Vec::new());
    }
    Ok(())
}

pub(super) fn select_assignments(refresh: &mut JudgeRefresh) {
    let Some(semester) = refresh.semester else {
        return;
    };
    if refresh
        .scan
        .cursor
        .current_course()
        .is_some_and(|course| explicit_course(refresh, &course.course_id))
    {
        return;
    }
    let known = super::history::known_summaries(refresh.history.as_ref());
    let mut selected = Vec::new();
    let mut excluded = Vec::new();
    for item in refresh.scan.cursor.pending_assignments() {
        let summary = known.iter().find(|s| {
            s.assignment_id == item.assignment_id
                && s.course_id == item.course_id
                && s.title == item.title
                && s.course_name == item.course_name
        });
        if let Some(summary) = summary.filter(|s| !semester.contains(s)) {
            excluded.push(summary.clone());
        } else {
            selected.push(item.clone());
        }
    }
    for item in &excluded {
        refresh.summaries.insert(
            (item.course_id.clone(), item.assignment_id.clone()),
            item.clone(),
        );
    }
    super::history::preserve_excluded(refresh, excluded);
    refresh.scan.cursor.accept_assignments(selected);
}

fn explicit_course(refresh: &JudgeRefresh, course_id: &str) -> bool {
    refresh.options.full_refresh
        || refresh.options.preferred_course.as_deref() == Some(course_id)
        || refresh
            .options
            .current_assignment
            .as_ref()
            .is_some_and(|key| key.course_id == course_id)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn 学期区间包含跨学期和边界作业并保留未知日期() {
        let parse = |s| super::super::policy::timestamp(Some(s)).unwrap();
        let term = Semester {
            start: parse("2026-09-07 00:00:00"),
            end: parse("2027-01-17 23:59:59"),
        };
        for (start, end, included, past) in [
            ("2026-08-01 00:00:00", "2026-09-07 00:00:00", true, false),
            ("2027-01-17 23:59:59", "2027-02-01 00:00:00", true, false),
            ("2026-08-01 00:00:00", "2026-09-06 23:59:59", false, true),
            ("2027-01-18 00:00:00", "2027-02-01 00:00:00", false, false),
            ("未知", "2026-08-01 00:00:00", true, false),
            ("2026-09-01 00:00:00", "2026-08-01 00:00:00", true, false),
        ] {
            let summary = JudgeAssignmentSummary {
                start_time: Some(start.into()),
                due_time: Some(end.into()),
                ..Default::default()
            };
            assert_eq!(term.contains(&summary), included, "{start} / {end}");
            assert_eq!(term.past(&summary), past, "{start} / {end}");
        }
    }
}
