//! 明确批量详情复用在线扫描，每项独立完整发布，不覆盖摘要范围。
use super::{
    CacheError, CachePayload, CacheQuery, CacheReadTicket, CacheScope, OfflineCache,
    OfflineReadError, UbaaClient, remember_save,
};
use crate::facade::{
    JudgeAssignmentKey, JudgeOnlineOptions, JudgeOnlineProgress, JudgeOnlineScan,
    JudgeScanCancellation, ReadonlyFeature,
};
use std::collections::{BTreeMap, HashSet};

pub struct JudgeDetailsRead {
    scan: JudgeOnlineScan,
    cache: OfflineCache,
    pending: BTreeMap<(String, String), CacheReadTicket>,
    save_error: Option<CacheError>,
    finished: bool,
}
pub struct JudgeDetailsReadBatch {
    pub progress: JudgeOnlineProgress,
    pub save_error: Option<CacheError>,
}
impl JudgeDetailsRead {
    #[must_use]
    pub fn cancellation(&self) -> JudgeScanCancellation {
        self.scan.cancellation()
    }
    fn validate(&self) -> Result<(), OfflineReadError> {
        if self.finished {
            return Err(OfflineReadError::Cache(CacheError::Superseded));
        }
        self.cache
            .check_read_generation()
            .map_err(OfflineReadError::Cache)?;
        if let Some(ticket) = self.pending.values().next() {
            self.cache
                .validate_read(ticket)
                .map_err(OfflineReadError::Cache)?;
        }
        Ok(())
    }
}
impl UbaaClient {
    /// 对明确目标建立独立详情票据；只使用原客户端的同路线会话。
    ///
    /// # Errors
    /// 无效目标、身份/生命周期冲突、本地票据或原学校读取失败保持分类。
    pub async fn begin_judge_details(
        &mut self,
        cache: &OfflineCache,
        mut keys: Vec<JudgeAssignmentKey>,
    ) -> Result<JudgeDetailsRead, OfflineReadError> {
        if keys.is_empty() {
            return Err(OfflineReadError::Cache(CacheError::InvalidInput));
        }
        let mut seen = HashSet::new();
        keys.retain(|key| seen.insert((key.course_id.clone(), key.assignment_id.clone())));
        // 为其他任务保留租约预算；超大批次可沿无缓存路径读取，不截断目标。
        if keys.len() > 2048 {
            return Err(OfflineReadError::Cache(CacheError::Capacity));
        }
        for key in &keys {
            detail_scope(crate::facade::ConnectionMode::Direct, key)
                .validate()
                .map_err(OfflineReadError::Cache)?;
        }
        cache
            .check_read_generation()
            .map_err(OfflineReadError::Cache)?;
        let authenticated = self
            .recover_required_session(ReadonlyFeature::Judge)
            .await
            .map_err(OfflineReadError::Read)?;
        let resolution = authenticated.resolution;
        if !cache.matches(&authenticated.data.user) {
            return Err(OfflineReadError::IdentityMismatch {
                resolution,
                cache_error: cache.deactivate().err(),
            });
        }
        let mut pending = BTreeMap::new();
        for key in &keys {
            let ticket = cache
                .begin(detail_scope(resolution.mode, key))
                .map_err(OfflineReadError::Cache)?;
            pending.insert((key.course_id.clone(), key.assignment_id.clone()), ticket);
        }
        let result = self
            .begin_judge_online_on_route(
                JudgeOnlineOptions {
                    keys: Some(keys),
                    ..JudgeOnlineOptions::default()
                },
                resolution,
            )
            .await;
        let scan = match result {
            Ok(scan) => scan,
            Err(error) => {
                for ticket in pending.values() {
                    cache.failure(ticket, chrono::Utc::now().timestamp());
                }
                return Err(error);
            }
        };
        let plan = JudgeDetailsRead {
            scan,
            cache: cache.clone(),
            pending,
            save_error: None,
            finished: false,
        };
        plan.validate()?;
        Ok(plan)
    }

    /// 每次读取一个原子选课/详情批次，成功项单独落盘后返回调度器。
    ///
    /// # Errors
    /// 取消、退出、清理或较新同目标读取拒绝迟到发布；学校错误不伪装存储错误。
    pub async fn next_judge_details(
        &mut self,
        plan: &mut JudgeDetailsRead,
    ) -> Result<JudgeDetailsReadBatch, OfflineReadError> {
        let result = self.advance_judge_details(plan).await;
        if result.is_err() {
            plan.cancellation().cancel();
            for ticket in plan.pending.values() {
                plan.cache.failure(ticket, chrono::Utc::now().timestamp());
            }
        }
        result
    }

    async fn advance_judge_details(
        &mut self,
        plan: &mut JudgeDetailsRead,
    ) -> Result<JudgeDetailsReadBatch, OfflineReadError> {
        plan.validate()?;
        if let Some(ticket) = plan.pending.values_mut().next() {
            plan.cache
                .repository(|repository| repository.renew_read(ticket))
                .map_err(OfflineReadError::Cache)?;
        }
        let progress = self.next_judge_online(&mut plan.scan).await?;
        plan.validate()?;
        if let Some(detail) = &progress.batch.detail {
            let ticket = plan
                .pending
                .remove(&(detail.course_id.clone(), detail.assignment_id.clone()))
                .ok_or(OfflineReadError::Cache(CacheError::InvalidInput))?;
            remember_save(
                &mut plan.save_error,
                plan.cache.publish(
                    &ticket,
                    CachePayload::JudgeDetail(Box::new(detail.clone())),
                    chrono::Utc::now().timestamp(),
                ),
            )?;
        }
        if progress.batch.finished {
            plan.finished = true;
            for ticket in plan.pending.values() {
                plan.cache.failure(ticket, chrono::Utc::now().timestamp());
            }
        }
        Ok(JudgeDetailsReadBatch {
            progress,
            save_error: plan.save_error,
        })
    }
}
fn detail_scope(route: crate::facade::ConnectionMode, key: &JudgeAssignmentKey) -> CacheScope {
    CacheScope {
        route,
        query: CacheQuery::JudgeDetail {
            course_id: key.course_id.clone(),
            assignment_id: key.assignment_id.clone(),
        },
    }
}
