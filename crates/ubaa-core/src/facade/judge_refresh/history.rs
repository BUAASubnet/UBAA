//! 历史课程只有限期复查状态，且必须与原索引修订完全匹配。
use super::{
    CacheCompleteness, CacheError, CachePayload, CacheQuery, CacheReadTicket, CacheScope,
    JudgeRefresh, JudgeScanKind, OfflineReadError, policy, read, remember_save,
};
use crate::cache::{CacheRecord, JudgeCourseReview};
pub(super) struct CourseProgress {
    course_id: String,
    ticket: CacheReadTicket,
    index_revision: i64,
    index_checked_at: i64,
    all_historical: bool,
    previous: Option<CacheRecord>,
    summaries: Vec<super::JudgeAssignmentSummary>,
}
pub(super) fn prepare(refresh: &mut JudgeRefresh, course_id: &str) -> Result<(), OfflineReadError> {
    let ticket = refresh
        .scan
        .cache
        .begin(CacheScope {
            route: refresh.scan.resolution.mode,
            query: CacheQuery::JudgeCourseReview {
                course_id: course_id.into(),
            },
        })
        .map_err(OfflineReadError::Cache)?;
    let previous = match refresh.scan.cache.read(
        &CacheScope {
            route: refresh.scan.resolution.mode,
            query: CacheQuery::JudgeCourseReview {
                course_id: course_id.into(),
            },
        },
        chrono::Utc::now().timestamp(),
    ) {
        Ok(record) => record,
        Err(error) => {
            remember_save(&mut refresh.save_error, Err::<(), _>(error))?;
            None
        }
    };
    refresh.history = Some(CourseProgress {
        previous,
        summaries: Vec::new(),
        course_id: course_id.into(),
        ticket,
        index_revision: 0,
        index_checked_at: 0,
        all_historical: true,
    });
    Ok(())
}
pub(super) fn cached_index(
    refresh: &mut JudgeRefresh,
    course_id: &str,
    now: i64,
) -> Result<Option<CacheRecord>, OfflineReadError> {
    if refresh.options.full_refresh
        || refresh.options.preferred_course.as_deref() == Some(course_id)
        || refresh
            .options
            .current_assignment
            .as_ref()
            .is_some_and(|key| key.course_id == course_id)
    {
        return Ok(None);
    }
    let result = refresh.scan.cache.repository(|repository| {
        let Some(review) = refresh
            .history
            .as_ref()
            .and_then(|progress| progress.previous.as_ref())
        else {
            return Ok(None);
        };
        if !review.last_attempt_succeeded {
            return Ok(None);
        }
        let CachePayload::JudgeCourseReview(metadata) = &review.payload else {
            return Ok(None);
        };
        if !metadata.all_items_historical
            || metadata.next_index_check_at <= now
            || metadata.index_checked_at > now
        {
            return Ok(None);
        }
        let index = repository.read(
            &CacheScope {
                route: refresh.scan.resolution.mode,
                query: CacheQuery::JudgeAssignments {
                    course_id: course_id.into(),
                },
            },
            now,
        )?;
        Ok(index.filter(|record| {
            record.revision == metadata.index_revision
                && record.last_verified_at == metadata.index_checked_at
                && record.is_fresh(now, 86400)
        }))
    });
    match result {
        Ok(record) => Ok(record),
        Err(error) => {
            remember_save(&mut refresh.save_error, Err::<(), _>(error))?;
            Ok(None)
        }
    }
}
pub(super) fn apply(
    refresh: &mut JudgeRefresh,
    step: &read::Step,
    now: i64,
) -> Result<(), OfflineReadError> {
    let Some(progress) = &mut refresh.history else {
        return Ok(());
    };
    if let Some(revision) = step.index_revision {
        progress.index_revision = revision;
        progress.index_checked_at = step.source_at;
    }
    if let Some(detail) = &step.batch.detail {
        progress.all_historical &= policy::historical(detail, now);
        progress
            .summaries
            .push(crate::features::judge::to_summary(detail));
    }
    if refresh
        .scan
        .courses
        .get(refresh.scan.course_index)
        .is_some_and(|course| course.course_id == progress.course_id)
    {
        return Ok(());
    }
    let progress = refresh
        .history
        .take()
        .ok_or(OfflineReadError::Cache(CacheError::Corrupt))?;
    let result = if step.batch.kind == JudgeScanKind::CourseFailure {
        refresh.scan.cache.repository(|repository| {
            repository.record_failure_guarded(&progress.ticket, &refresh.scan.ticket, now)
        })
    } else {
        refresh.scan.cache.repository(|repository| {
            repository
                .publish_guarded(
                    &progress.ticket,
                    &refresh.scan.ticket,
                    CachePayload::JudgeCourseReview(JudgeCourseReview {
                        index_revision: progress.index_revision,
                        index_checked_at: progress.index_checked_at,
                        next_index_check_at: progress
                            .index_checked_at
                            .saturating_add(if progress.all_historical { 86400 } else { 300 }),
                        all_items_historical: progress.all_historical,
                        summaries: progress.summaries,
                    }),
                    now,
                    CacheCompleteness::Complete,
                )
                .map(|_| ())
        })
    };
    remember_save(&mut refresh.save_error, result)
}

pub(super) fn renew(refresh: &mut JudgeRefresh) -> Result<(), OfflineReadError> {
    if let Some(progress) = &mut refresh.history {
        refresh
            .scan
            .cache
            .repository(|repository| repository.renew_read(&mut progress.ticket))
            .map_err(OfflineReadError::Cache)?;
    }
    Ok(())
}

pub(super) fn fail(refresh: &mut JudgeRefresh) {
    if let Some(progress) = refresh.history.take() {
        let _ = refresh.scan.cache.repository(|repository| {
            repository.record_failure_guarded(
                &progress.ticket,
                &refresh.scan.ticket,
                chrono::Utc::now().timestamp(),
            )
        });
    }
}

pub(super) fn known_summaries(refresh: &JudgeRefresh) -> &[super::JudgeAssignmentSummary] {
    match refresh
        .history
        .as_ref()
        .and_then(|progress| progress.previous.as_ref())
        .map(|record| &record.payload)
    {
        Some(CachePayload::JudgeCourseReview(review)) => &review.summaries,
        _ => &[],
    }
}
