//! 跨仓库竞争只在本地收尾；同仓库沿用原摘要与指定详情恢复规则。
use super::{
    CacheError, CachePayload, JudgeRefresh, JudgeRefreshBatch, JudgeScanBatch, JudgeScanKind,
    OfflineReadError, UbaaClient,
};
use crate::cache::{
    CacheCompleteness, CacheObservation, CacheQuery, CacheReadTicket, CacheRecord,
    SharedReadRecovery,
};

impl UbaaClient {
    pub(super) async fn recover_judge_refresh(
        &mut self,
        refresh: &mut JudgeRefresh,
    ) -> Result<JudgeRefreshBatch, OfflineReadError> {
        self.validate_judge_owner(&refresh.scan)?;
        let cache = refresh.scan.cache.clone();
        if let Some(target) = &refresh.options.current_assignment {
            match cache.repository(|repo| repo.recover_shared_read(&refresh.scan.ticket, false)) {
                Ok(_) => {
                    let record = cache
                        .repository(|repo| {
                            repo.read_after_shared_superseded(
                                &refresh.scan.ticket,
                                &CacheQuery::JudgeDetail {
                                    course_id: target.course_id.clone(),
                                    assignment_id: target.assignment_id.clone(),
                                },
                            )
                        })
                        .map_err(OfflineReadError::Cache)?;
                    return finish_target(refresh, record);
                }
                Err(CacheError::Superseded) => {}
                Err(error) => return Err(OfflineReadError::Cache(error)),
            }
        } else {
            let final_at = refresh.final_summary_at.take();
            match cache.repository(|repo| {
                repo.recover_shared_read(&refresh.scan.ticket, final_at.is_some())
            }) {
                Ok(SharedReadRecovery::Reuse(record)) => {
                    return finish_shared(refresh, Some(record), false);
                }
                Ok(SharedReadRecovery::Superseded(record)) => {
                    return finish_shared(refresh, record, true);
                }
                Ok(SharedReadRecovery::Retry(ticket)) => {
                    let now = final_at.expect("仅已完成的摘要可以补发票据");
                    return retry_summary(refresh, &ticket, now);
                }
                Err(CacheError::Superseded) => {}
                Err(error) => return Err(OfflineReadError::Cache(error)),
            }
        }
        let (ticket, record) = cache
            .repository(|repo| repo.recover_readonly_scan(&refresh.scan.ticket))
            .map_err(OfflineReadError::Cache)?;
        // 指定作业的刷新必须交付该作业正文，不能用较新摘要代替。
        let wanted = refresh.options.current_assignment.clone();
        let (ticket, record) = match (record, &wanted) {
            (Some(_), Some(_)) => (None, None),
            (record, _) => (Some(ticket), record),
        };
        if let Some(record) = record {
            return finish_shared(refresh, Some(record), false);
        }
        let cancellation = refresh.scan.cancellation();
        let mut replacement = self
            .begin_judge_refresh_with_ticket(&cache, refresh.options.clone(), ticket)
            .await?;
        self.validate_judge_owner(&refresh.scan)?;
        replacement.scan.cancellation = cancellation;
        *refresh = replacement;
        loop {
            let batch = self.advance_judge_refresh(refresh).await?;
            let delivers_wanted = wanted.as_ref().is_some_and(|key| {
                batch.batch.detail.as_ref().is_some_and(|detail| {
                    detail.course_id == key.course_id && detail.assignment_id == key.assignment_id
                })
            });
            if batch.batch.finished || delivers_wanted {
                return Ok(batch);
            }
        }
    }
}

fn retry_summary(
    refresh: &JudgeRefresh,
    ticket: &CacheReadTicket,
    now: i64,
) -> Result<JudgeRefreshBatch, OfflineReadError> {
    let cache = &refresh.scan.cache;
    let summary = super::progress::summary(refresh, now);
    match cache.repository(|repo| {
        repo.publish_observed(
            ticket,
            CachePayload::JudgeSummaries(summary.0.clone()),
            CacheObservation {
                source_at: summary.1,
                attempted_at: now,
            },
            CacheCompleteness::Complete,
        )
    }) {
        Ok(_) => Ok(finish(
            refresh,
            refresh.scan.resolution,
            summary,
            true,
            false,
            refresh.save_error,
        )),
        Err(CacheError::Superseded) => match cache
            .repository(|repo| repo.recover_shared_read(ticket, false))
            .map_err(OfflineReadError::Cache)?
        {
            SharedReadRecovery::Reuse(record) => finish_shared(refresh, Some(record), true),
            SharedReadRecovery::Superseded(record) => finish_shared(refresh, record, true),
            SharedReadRecovery::Retry(_) => unreachable!("本地恢复最多补发一次票据"),
        },
        Err(error) => Err(OfflineReadError::Cache(error)),
    }
}

fn finish_target(
    refresh: &JudgeRefresh,
    record: Option<CacheRecord>,
) -> Result<JudgeRefreshBatch, OfflineReadError> {
    let mut resolution = refresh.scan.resolution;
    let mut fetched_at = chrono::Utc::now().timestamp();
    let mut save_error = Some(CacheError::Superseded);
    let mut detail = None;
    if let Some(record) = record.filter(|record| record.completeness == CacheCompleteness::Complete)
    {
        let CachePayload::JudgeDetail(value) = record.payload else {
            return Err(OfflineReadError::Cache(CacheError::Corrupt));
        };
        resolution.mode = record.scope.route;
        resolution.diagnostic.mode = record.scope.route;
        fetched_at = record.fetched_at;
        if record.revision > refresh.scan.ticket.request_revision() {
            save_error = None;
        }
        detail = Some(*value);
    }
    let mut terminal = finish(
        refresh,
        resolution,
        (Vec::new(), fetched_at, false),
        detail.is_some(),
        detail.is_some(),
        save_error,
    );
    if let Some(detail) = detail {
        terminal.batch.kind = JudgeScanKind::Detail;
        terminal.batch.course_id = Some(detail.course_id.clone());
        terminal.batch.detail = Some(detail);
    }
    Ok(terminal)
}

fn finish_shared(
    refresh: &JudgeRefresh,
    record: Option<CacheRecord>,
    superseded: bool,
) -> Result<JudgeRefreshBatch, OfflineReadError> {
    let mut resolution = refresh.scan.resolution;
    let reused = record.is_some();
    let summary = if let Some(record) = record {
        let CachePayload::JudgeSummaries(mut summaries) = record.payload else {
            return Err(OfflineReadError::Cache(CacheError::Corrupt));
        };
        if let Some(semester) = refresh.semester {
            summaries.retain(|item| semester.contains(item));
        }
        resolution.mode = record.scope.route;
        resolution.diagnostic.mode = record.scope.route;
        (summaries, record.fetched_at, true)
    } else {
        super::progress::summary(refresh, chrono::Utc::now().timestamp())
    };
    Ok(finish(
        refresh,
        resolution,
        summary,
        !superseded,
        reused,
        superseded.then_some(CacheError::Superseded),
    ))
}

fn finish(
    refresh: &JudgeRefresh,
    resolution: super::super::RouteResolution,
    (summaries, fetched_at, has_cached): (Vec<super::JudgeAssignmentSummary>, i64, bool),
    complete: bool,
    reused: bool,
    save_error: Option<CacheError>,
) -> JudgeRefreshBatch {
    refresh.scan.cancellation().cancel();
    JudgeRefreshBatch {
        resolution,
        batch: JudgeScanBatch {
            kind: JudgeScanKind::Finished,
            course_id: None,
            assignments: Vec::new(),
            detail: None,
            error: None,
            finished: true,
            complete,
            failed_courses: 0,
        },
        summaries,
        summary_fetched_at: fetched_at,
        summary_has_cached: has_cached,
        reused,
        fetched_at: Some(fetched_at),
        save_error,
    }
}
