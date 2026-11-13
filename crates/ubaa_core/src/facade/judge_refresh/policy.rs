//! 客户端刷新期限不代表上游支持增量或内容版本号。
use super::JudgeRefreshOptions;
use crate::{
    cache::{CachePayload, CacheRecord},
    domain::{Assignment, JudgeAssignmentDetail, JudgeSubmissionStatus},
};
use chrono::{DateTime, Months, NaiveDateTime, Utc};

fn timestamp(value: Option<&str>) -> Option<i64> {
    let value = value?;
    let parsed = NaiveDateTime::parse_from_str(value, "%Y-%m-%d %H:%M:%S").ok()?;
    if parsed.format("%Y-%m-%d %H:%M:%S").to_string() != value {
        return None;
    }
    parsed.and_utc().timestamp().checked_sub(8 * 3600)
}
pub(super) fn historical(detail: &JudgeAssignmentDetail, now: i64) -> bool {
    let Some(now_date) = DateTime::<Utc>::from_timestamp(now.saturating_add(8 * 3600), 0) else {
        return false;
    };
    let Some(cutoff) = now_date.naive_utc().checked_sub_months(Months::new(6)) else {
        return false;
    };
    let cutoff = cutoff.and_utc().timestamp().saturating_sub(8 * 3600);
    detail.submission_status == JudgeSubmissionStatus::Submitted
        && timestamp(detail.start_time.as_deref()).is_some_and(|value| value < cutoff)
        && timestamp(detail.due_time.as_deref())
            .is_some_and(|value| value < now.saturating_sub(14 * 86400))
}
pub(in crate::facade) fn historical_summary(
    summary: &crate::domain::JudgeAssignmentSummary,
    now: i64,
) -> bool {
    historical(
        &JudgeAssignmentDetail {
            start_time: summary.start_time.clone(),
            due_time: summary.due_time.clone(),
            submission_status: summary.submission_status,
            ..Default::default()
        },
        now,
    )
}
pub(super) fn reusable(
    record: &CacheRecord,
    assignment: &Assignment,
    options: &JudgeRefreshOptions,
    now: i64,
) -> bool {
    let CachePayload::JudgeDetail(detail) = &record.payload else {
        return false;
    };
    // 列表只证明这些字段；截止、评分和提交状态来自详情，按下方期限复查。
    let fingerprint = (
        assignment.course_id.as_str(),
        assignment.assignment_id.as_str(),
        assignment.course_name.as_str(),
        assignment.title.as_str(),
    );
    let cached_fingerprint = (
        detail.course_id.as_str(),
        detail.assignment_id.as_str(),
        detail.course_name.as_str(),
        detail.title.as_str(),
    );
    if options.full_refresh
        || options.current_assignment.as_ref().is_some_and(|key| {
            key.course_id == assignment.course_id && key.assignment_id == assignment.assignment_id
        })
        || fingerprint != cached_fingerprint
    {
        return false;
    }
    record.is_fresh(
        now,
        if historical(detail, now) {
            7 * 86400
        } else if timestamp(detail.due_time.as_deref()).is_none_or(|due| now.abs_diff(due) <= 86400)
        {
            15 * 60
        } else {
            6 * 3600
        },
    )
}

pub(super) fn prioritize_courses(
    scan: &mut super::JudgeScan,
    options: &JudgeRefreshOptions,
    original: &[crate::domain::JudgeAssignmentSummary],
    now: i64,
) {
    let preferred = options
        .current_assignment
        .as_ref()
        .map(|key| key.course_id.as_str())
        .or(options.preferred_course.as_deref());
    scan.cursor.prioritize_courses(|course| {
        if preferred == Some(course.course_id.as_str()) {
            return (0, String::new());
        }
        let items: Vec<_> = original
            .iter()
            .filter(|item| item.course_id == course.course_id)
            .collect();
        let active_due = items
            .iter()
            .filter(|item| {
                item.submission_status != crate::domain::JudgeSubmissionStatus::Submitted
            })
            .map(|item| item.due_time.clone().unwrap_or_else(|| "9999".into()))
            .min();
        if let Some(due) = active_due {
            (1, due)
        } else if items.is_empty() {
            (2, String::new())
        } else if items.iter().all(|item| historical_summary(item, now)) {
            (4, String::new())
        } else {
            (3, String::new())
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn old_start_alone_never_hides_long_running_unknown_or_unfinished_work() {
        let now = timestamp(Some("2026-09-22 12:00:00")).unwrap();
        let mut detail = JudgeAssignmentDetail {
            start_time: Some("2025-01-01 00:00:00".into()),
            due_time: Some("2026-10-01 00:00:00".into()),
            submission_status: JudgeSubmissionStatus::Submitted,
            ..Default::default()
        };
        assert!(!historical(&detail, now));
        detail.due_time = Some("2025-02-01 00:00:00".into());
        assert!(historical(&detail, now));
        detail.submission_status = JudgeSubmissionStatus::Unknown;
        assert!(!historical(&detail, now));
        detail.submission_status = JudgeSubmissionStatus::Unsubmitted;
        assert!(!historical(&detail, now));
        detail.submission_status = JudgeSubmissionStatus::Submitted;
        detail.start_time = Some("2025-02-30 00:00:00".into());
        assert!(!historical(&detail, now));
    }
}
