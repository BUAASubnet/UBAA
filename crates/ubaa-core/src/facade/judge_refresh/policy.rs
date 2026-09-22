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
    if options.full_refresh
        || options.current_assignment.as_ref().is_some_and(|key| {
            key.course_id == assignment.course_id && key.assignment_id == assignment.assignment_id
        })
        || detail.title != assignment.title
        || detail.course_name != assignment.course_name
    {
        return false;
    }
    record.is_fresh(
        now,
        if historical(detail, now) {
            7 * 86400
        } else {
            120
        },
    )
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
