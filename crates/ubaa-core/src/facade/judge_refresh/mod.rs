//! 持久索引和详情的渐进刷新；复用数据保留原时间，部分失败保护旧摘要。
mod history;
pub(super) mod policy;
mod progress;
mod read;
use super::{
    CacheCompleteness, CacheError, CachePayload, CacheQuery, CacheReadTicket, CacheScope,
    JudgeAssignmentKey, JudgeAssignmentSummary, JudgeScan, JudgeScanBatch, JudgeScanCancellation,
    JudgeScanKind, OfflineCache, OfflineReadError, UbaaClient,
};
use std::collections::{BTreeMap, HashSet};

#[derive(Clone, Default)]
pub struct JudgeRefreshOptions {
    pub include_expired: bool,
    pub full_refresh: bool,
    pub preferred_course: Option<String>,
    pub current_assignment: Option<JudgeAssignmentKey>,
}
/// 持久刷新仍由原客户端逐批推进，不自行启动学校请求。
pub struct JudgeRefresh {
    scan: JudgeScan,
    options: JudgeRefreshOptions,
    summaries: BTreeMap<(String, String), JudgeAssignmentSummary>,
    original: Vec<JudgeAssignmentSummary>,
    original_source_at: i64,
    source_times: BTreeMap<(String, String), i64>,
    cached_keys: HashSet<(String, String)>,
    oldest_source_at: i64,
    save_error: Option<CacheError>,
    history: Option<history::CourseProgress>,
}
impl JudgeRefresh {
    #[must_use]
    pub const fn resolution(&self) -> super::RouteResolution {
        self.scan.resolution
    }
    #[must_use]
    pub fn courses(&self) -> &[super::Course] {
        self.scan.courses()
    }
    #[must_use]
    pub fn cancellation(&self) -> JudgeScanCancellation {
        self.scan.cancellation()
    }
}
pub struct JudgeRefreshBatch {
    pub resolution: super::RouteResolution,
    pub batch: JudgeScanBatch,
    pub summaries: Vec<JudgeAssignmentSummary>,
    pub summary_fetched_at: i64,
    pub summary_has_cached: bool,
    pub reused: bool,
    pub fetched_at: Option<i64>,
    pub save_error: Option<CacheError>,
}
impl UbaaClient {
    /// 从新鲜课程索引开始，按项复用仍有效的持久详情。
    ///
    /// # Errors
    /// 身份、扫描栅栏或索引读取失败时返回原分类。
    pub async fn begin_judge_refresh(
        &mut self,
        cache: &OfflineCache,
        options: JudgeRefreshOptions,
    ) -> Result<JudgeRefresh, OfflineReadError> {
        let mut scan = self
            .begin_judge_scan_with_freshness(
                cache,
                options.include_expired,
                options
                    .current_assignment
                    .as_ref()
                    .map(|key| key.course_id.as_str())
                    .or(options.preferred_course.as_deref()),
                true,
            )
            .await?;
        let now = chrono::Utc::now().timestamp();
        let mut save_error = None;
        if let Some(ticket) = scan.course_ticket.take() {
            remember_save(
                &mut save_error,
                cache.repository(|repository| {
                    repository.publish_guarded(
                        &ticket,
                        &scan.ticket,
                        CachePayload::JudgeCourses(scan.courses.clone()),
                        now,
                        CacheCompleteness::Complete,
                    )
                }),
            )?;
        }
        let mut original_source_at = now;
        let original = match cache.read_judge(scan.resolution.mode, options.include_expired) {
            Ok(Some(record)) => match record.payload {
                CachePayload::JudgeSummaries(items) => {
                    original_source_at = record.fetched_at;
                    items
                }
                _ => Vec::new(),
            },
            Ok(None) => Vec::new(),
            Err(error) => {
                remember_save(&mut save_error, Err::<(), _>(error))?;
                Vec::new()
            }
        };
        let summaries: BTreeMap<_, _> = original
            .iter()
            .cloned()
            .map(|item| ((item.course_id.clone(), item.assignment_id.clone()), item))
            .collect();
        let source_times = summaries
            .keys()
            .cloned()
            .map(|key| (key, original_source_at))
            .collect();
        let cached_keys = summaries.keys().cloned().collect();
        Ok(JudgeRefresh {
            original_source_at,
            source_times,
            cached_keys,
            history: None,
            scan,
            options,
            summaries,
            original,
            oldest_source_at: now,
            save_error,
        })
    }
    /// 一批新读取或已保存详情立即返回；最后只以完整集合替换已保存摘要。
    ///
    /// # Errors
    /// 账号/路线、较新扫描、取消或主会话失败终止计划，不发布迟到内容。
    pub async fn next_judge_refresh(
        &mut self,
        refresh: &mut JudgeRefresh,
    ) -> Result<JudgeRefreshBatch, OfflineReadError> {
        self.validate_judge_scan(&refresh.scan)?;
        refresh
            .scan
            .cache
            .repository(|repository| repository.renew_read(&mut refresh.scan.ticket))
            .map_err(OfflineReadError::Cache)?;
        history::renew(refresh)?;
        let step = match self.read_judge_refresh_batch(refresh).await {
            Ok(step) => step,
            Err(error) => {
                history::fail(refresh);
                refresh.scan.cache.fail_scan(&refresh.scan.ticket, None);
                return Err(error);
            }
        };
        self.validate_judge_scan(&refresh.scan)?;
        progress::finish(refresh, step, chrono::Utc::now().timestamp())
    }
}
fn save_child(
    refresh: &mut JudgeRefresh,
    child: Option<&CacheReadTicket>,
    payload: CachePayload,
    now: i64,
) -> Result<(), OfflineReadError> {
    if let Some(child) = child {
        remember_save(
            &mut refresh.save_error,
            refresh.scan.cache.repository(|repository| {
                repository.publish_guarded(
                    child,
                    &refresh.scan.ticket,
                    payload,
                    now,
                    CacheCompleteness::Complete,
                )
            }),
        )?;
    }
    Ok(())
}
fn remember_save<T>(
    saved: &mut Option<CacheError>,
    result: Result<T, CacheError>,
) -> Result<(), OfflineReadError> {
    let error = match result {
        Ok(value) => {
            drop(value);
            return Ok(());
        }
        Err(error) => error,
    };
    if matches!(error, CacheError::Inactive | CacheError::Superseded) {
        return Err(OfflineReadError::Cache(error));
    }
    *saved = Some(error);
    Ok(())
}
