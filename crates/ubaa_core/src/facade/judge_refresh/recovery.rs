//! 较新同查询摘要优先复用；尚在途时在原账号生命周期内完整重读一次。
use super::{
    CacheError, CachePayload, JudgeRefresh, JudgeRefreshBatch, JudgeScanBatch, JudgeScanKind,
    OfflineReadError, UbaaClient,
};

impl UbaaClient {
    pub(super) async fn recover_judge_refresh(
        &mut self,
        refresh: &mut JudgeRefresh,
    ) -> Result<JudgeRefreshBatch, OfflineReadError> {
        self.validate_judge_owner(&refresh.scan)?;
        let cache = refresh.scan.cache.clone();
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
            let CachePayload::JudgeSummaries(summaries) = record.payload else {
                return Err(OfflineReadError::Cache(CacheError::Corrupt));
            };
            refresh.scan.cancellation().cancel();
            let mut resolution = refresh.scan.resolution;
            resolution.mode = record.scope.route;
            return Ok(JudgeRefreshBatch {
                resolution,
                batch: JudgeScanBatch {
                    kind: JudgeScanKind::Finished,
                    course_id: None,
                    assignments: Vec::new(),
                    detail: None,
                    error: None,
                    finished: true,
                    complete: true,
                    failed_courses: 0,
                },
                summaries,
                summary_fetched_at: record.fetched_at,
                summary_has_cached: true,
                reused: true,
                fetched_at: Some(record.fetched_at),
                save_error: None,
            });
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
