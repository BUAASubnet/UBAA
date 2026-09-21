//! 逐批更新投影，完整覆盖后替换摘要；失败课程恢复旧投影。
use super::{
    CacheCompleteness, CachePayload, JudgeRefresh, JudgeRefreshBatch, JudgeScanKind,
    OfflineReadError, history, policy, read, remember_save, save_child,
};
pub(super) fn finish(
    refresh: &mut JudgeRefresh,
    step: read::Step,
    now: i64,
) -> Result<JudgeRefreshBatch, OfflineReadError> {
    let batch = &step.batch;
    refresh.oldest_source_at = refresh.oldest_source_at.min(step.source_at);
    apply_content(refresh, &step, now)?;
    history::apply(refresh, &step, now)?;
    if batch.finished && batch.complete {
        refresh.summaries.retain(|(course, _), _| {
            refresh
                .scan
                .courses
                .iter()
                .any(|item| item.course_id == *course)
        });
    }
    let mut summaries: Vec<_> = refresh
        .summaries
        .values()
        .filter(|item| refresh.options.include_expired || !policy::historical_summary(item, now))
        .cloned()
        .collect();
    summaries.sort_by(|a, b| {
        a.due_time
            .cmp(&b.due_time)
            .then_with(|| a.course_id.cmp(&b.course_id))
            .then_with(|| a.assignment_id.cmp(&b.assignment_id))
    });
    let summary_fetched_at = summaries
        .iter()
        .filter_map(|item| {
            refresh
                .source_times
                .get(&(item.course_id.clone(), item.assignment_id.clone()))
        })
        .copied()
        .min()
        .unwrap_or(refresh.oldest_source_at);
    let summary_has_cached = summaries.iter().any(|item| {
        refresh
            .cached_keys
            .contains(&(item.course_id.clone(), item.assignment_id.clone()))
    });
    refresh
        .scan
        .cache
        .validate_read(&refresh.scan.ticket)
        .map_err(OfflineReadError::Cache)?;
    if batch.finished {
        let completeness = if batch.complete {
            CacheCompleteness::Complete
        } else {
            CacheCompleteness::Partial
        };
        remember_save(
            &mut refresh.save_error,
            refresh.scan.cache.repository(|repository| {
                repository.publish_observed(
                    &refresh.scan.ticket,
                    CachePayload::JudgeSummaries(summaries.clone()),
                    crate::cache::CacheObservation {
                        source_at: summary_fetched_at,
                        attempted_at: now,
                    },
                    completeness,
                )
            }),
        )?;
    }
    Ok(JudgeRefreshBatch {
        resolution: refresh.scan.resolution,
        batch: step.batch,
        summaries,
        summary_fetched_at,
        summary_has_cached,
        reused: step.reused,
        fetched_at: Some(step.source_at),
        save_error: refresh.save_error,
    })
}

fn apply_content(
    refresh: &mut JudgeRefresh,
    step: &read::Step,
    now: i64,
) -> Result<(), OfflineReadError> {
    let batch = &step.batch;
    match batch.kind {
        JudgeScanKind::Assignments => {
            prioritize(refresh, now);
            if let Some(course_id) = &batch.course_id {
                refresh.summaries.retain(|(course, assignment), _| {
                    course != course_id
                        || batch
                            .assignments
                            .iter()
                            .any(|item| item.assignment_id == *assignment)
                });
            }
            save_child(
                refresh,
                step.child.as_ref(),
                CachePayload::JudgeAssignments(batch.assignments.clone()),
                step.source_at,
            )?;
        }
        JudgeScanKind::Detail => {
            if let Some(detail) = &batch.detail {
                let key = (detail.course_id.clone(), detail.assignment_id.clone());
                refresh.source_times.insert(key.clone(), step.source_at);
                if step.reused {
                    refresh.cached_keys.insert(key);
                } else {
                    refresh.cached_keys.remove(&key);
                }
                refresh.summaries.insert(
                    (detail.course_id.clone(), detail.assignment_id.clone()),
                    crate::features::judge::to_summary(detail),
                );
                if !step.reused {
                    save_child(
                        refresh,
                        step.child.as_ref(),
                        CachePayload::JudgeDetail(Box::new(detail.clone())),
                        step.source_at,
                    )?;
                }
            }
        }
        JudgeScanKind::CourseFailure => {
            if let Some(course_id) = &batch.course_id {
                refresh
                    .summaries
                    .retain(|(course, _), _| course != course_id);
                for item in refresh
                    .original
                    .iter()
                    .filter(|item| &item.course_id == course_id)
                {
                    let key = (item.course_id.clone(), item.assignment_id.clone());
                    refresh
                        .source_times
                        .insert(key.clone(), refresh.original_source_at);
                    refresh.cached_keys.insert(key);
                    refresh.summaries.insert(
                        (item.course_id.clone(), item.assignment_id.clone()),
                        item.clone(),
                    );
                }
            }
            if let Some(child) = &step.child {
                remember_save(
                    &mut refresh.save_error,
                    refresh.scan.cache.repository(|repository| {
                        repository.record_failure_guarded(child, &refresh.scan.ticket, now)
                    }),
                )?;
            }
        }
        JudgeScanKind::Finished => {}
    }
    Ok(())
}

fn prioritize(refresh: &mut JudgeRefresh, now: i64) {
    let Some(items) = refresh.scan.assignments.take() else {
        return;
    };
    let known: std::collections::HashMap<_, _> = history::known_summaries(refresh)
        .iter()
        .map(|item| (item.assignment_id.as_str(), item))
        .collect();
    let mut ranked = Vec::with_capacity(items.len());
    for item in items {
        let current = refresh
            .options
            .current_assignment
            .as_ref()
            .is_some_and(|key| {
                key.course_id == item.course_id && key.assignment_id == item.assignment_id
            });
        let summary = known.get(item.assignment_id.as_str()).copied().or_else(|| {
            refresh
                .summaries
                .get(&(item.course_id.clone(), item.assignment_id.clone()))
        });
        let rank = if current {
            0
        } else {
            match summary {
                Some(summary)
                    if summary.title == item.title && summary.course_name == item.course_name =>
                {
                    if policy::historical_summary(summary, now) {
                        3
                    } else {
                        2
                    }
                }
                _ => 1,
            }
        };
        ranked.push((rank, item));
    }
    ranked.sort_by_key(|(rank, _)| *rank);
    refresh.scan.assignments = Some(ranked.into_iter().map(|(_, item)| item).collect());
}
