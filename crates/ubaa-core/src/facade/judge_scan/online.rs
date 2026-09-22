//! 无持久缓存时也按完整选课步骤让位，不借用第二个会话或复制Cookie。
use super::{
    Arc, Assignment, AtomicBool, Course, JudgeScanBatch, JudgeScanCancellation, JudgeScanKind,
    OfflineReadError, Ordering, ReadonlyFeature, RouteFeatureState, RouteResolution, UbaaClient,
    Weak, scan,
};
use crate::facade::{
    CacheError, ErrorCode, ErrorKind, JudgeAssignmentKey, JudgeAssignmentSummary, RoutedError,
    UbaaError,
};
use std::collections::{BTreeMap, HashSet};

#[derive(Clone, Default)]
pub struct JudgeOnlineOptions {
    pub include_expired: bool,
    /// 本机账号仍存在而密钥不可用时也必须核对身份；不发送给学校。
    pub expected_identity: Option<String>,
    pub preferred_course: Option<String>,
    /// None读取全部；Some只读取明确目标，空集合或空标识拒绝。
    pub keys: Option<Vec<JudgeAssignmentKey>>,
}
/// 只持有索引/游标和原客户端弱标识，不持有磁盘仓库或认证材料。
pub struct JudgeOnlineScan {
    resolution: RouteResolution,
    owner: Weak<RouteFeatureState>,
    generation: u64,
    route_generation: u64,
    cancellation: JudgeScanCancellation,
    options: JudgeOnlineOptions,
    courses: Vec<Course>,
    course_index: usize,
    assignments: Option<Vec<Assignment>>,
    detail_index: usize,
    failed_courses: usize,
    summaries: BTreeMap<(String, String), JudgeAssignmentSummary>,
    fetched_at: i64,
}
pub struct JudgeOnlineProgress {
    pub resolution: RouteResolution,
    pub batch: JudgeScanBatch,
    pub summaries: Vec<JudgeAssignmentSummary>,
    /// 全部步骤强制在线读取；这是当前投影最早取得时间，不是持久保存证明。
    pub fetched_at: i64,
}
impl JudgeOnlineScan {
    #[must_use]
    pub fn courses(&self) -> &[Course] {
        &self.courses
    }
    #[must_use]
    pub fn cancellation(&self) -> JudgeScanCancellation {
        self.cancellation.clone()
    }
    fn advance(&mut self) {
        self.course_index += 1;
        self.assignments = None;
        self.detail_index = 0;
    }
    fn progress(&self, mut batch: JudgeScanBatch) -> JudgeOnlineProgress {
        batch.finished = self.course_index >= self.courses.len();
        batch.failed_courses = self.failed_courses;
        batch.complete = batch.finished && self.failed_courses == 0;
        let now = chrono::Utc::now().timestamp();
        let summaries = self
            .summaries
            .values()
            .filter(|item| {
                self.options.include_expired
                    || self.options.keys.is_some()
                    || !crate::facade::judge_refresh::policy::historical_summary(item, now)
            })
            .cloned()
            .collect();
        JudgeOnlineProgress {
            resolution: self.resolution,
            batch,
            summaries,
            fetched_at: self.fetched_at,
        }
    }
}
impl UbaaClient {
    /// 核实所需会话后读取索引，完全不依赖本机缓存密钥或数据库。
    ///
    /// # Errors
    /// 参数、学校索引、认证和会话仲裁失败保持稳定分类。
    pub async fn begin_judge_online(
        &mut self,
        mut options: JudgeOnlineOptions,
    ) -> Result<JudgeOnlineScan, OfflineReadError> {
        let expected_identity = options.expected_identity.take();
        if expected_identity
            .as_ref()
            .is_some_and(|id| id.trim().is_empty())
        {
            return Err(invalid_target(None));
        }
        if let Some(keys) = &mut options.keys {
            if keys.is_empty()
                || keys.iter().any(|key| {
                    key.course_id.trim().is_empty() || key.assignment_id.trim().is_empty()
                })
            {
                return Err(invalid_target(None));
            }
            let mut seen = HashSet::new();
            keys.retain(|key| seen.insert((key.course_id.clone(), key.assignment_id.clone())));
        }
        let authenticated = self
            .recover_required_session(ReadonlyFeature::Judge)
            .await
            .map_err(OfflineReadError::Read)?;
        let resolution = authenticated.resolution;
        if expected_identity.as_ref().is_some_and(|expected| {
            ![
                authenticated.data.user.username.as_deref(),
                authenticated.data.user.school_id.as_deref(),
            ]
            .into_iter()
            .flatten()
            .any(|value| value.trim() == expected.trim())
        }) {
            return Err(OfflineReadError::IdentityMismatch {
                resolution,
                cache_error: None,
            });
        }
        let read = scan::courses(self.runtime_for(resolution.mode), true).await;
        let courses = self
            .finish_routed(resolution, read.result)
            .map_err(OfflineReadError::Read)?
            .data;
        let courses = select_courses(courses, &options, resolution)?;
        let owner = self.runtime_for(resolution.mode).feature_state();
        Ok(JudgeOnlineScan {
            resolution,
            generation: owner.judge.generation(),
            owner: Arc::downgrade(&owner),
            route_generation: self.route_generation,
            cancellation: JudgeScanCancellation(Arc::new(AtomicBool::new(false))),
            options,
            courses,
            course_index: 0,
            assignments: None,
            detail_index: 0,
            failed_courses: 0,
            summaries: BTreeMap::new(),
            fetched_at: chrono::Utc::now().timestamp(),
        })
    }
    fn validate_judge_online(&mut self, plan: &JudgeOnlineScan) -> Result<(), OfflineReadError> {
        self.guard_latest_routed().map_err(OfflineReadError::Read)?;
        let owner = self.runtime_for(plan.resolution.mode).feature_state();
        if plan.cancellation.0.load(Ordering::Acquire)
            || !Weak::ptr_eq(&Arc::downgrade(&owner), &plan.owner)
            || owner.judge.generation() != plan.generation
            || self.route_generation != plan.route_generation
        {
            return Err(OfflineReadError::Cache(CacheError::Superseded));
        }
        Ok(())
    }
    /// 每次最多推进一个原子选课+索引/详情；不按旧项位置推断后续时间顺序。
    ///
    /// # Errors
    /// 取消、路线/会话替换、明确目标缺失或认证仲裁失败时拒绝迟到结果。
    pub async fn next_judge_online(
        &mut self,
        plan: &mut JudgeOnlineScan,
    ) -> Result<JudgeOnlineProgress, OfflineReadError> {
        self.validate_judge_online(plan)?;
        let mut batch = JudgeScanBatch {
            kind: JudgeScanKind::Finished,
            course_id: None,
            assignments: Vec::new(),
            detail: None,
            error: None,
            finished: false,
            complete: false,
            failed_courses: plan.failed_courses,
        };
        let Some(course) = plan.courses.get(plan.course_index).cloned() else {
            return Ok(plan.progress(batch));
        };
        batch.course_id = Some(course.course_id.clone());
        let (read, fatal) = if let Some(assignments) = &plan.assignments {
            let read = scan::detail(
                self.runtime_for(plan.resolution.mode),
                &assignments[plan.detail_index],
                true,
            )
            .await;
            (
                read.result.map(|detail| {
                    batch.kind = JudgeScanKind::Detail;
                    batch.detail = Some(detail);
                }),
                read.fatal,
            )
        } else {
            let read =
                scan::assignments(self.runtime_for(plan.resolution.mode), &course, true).await;
            (
                read.result.map(|assignments| {
                    batch.kind = JudgeScanKind::Assignments;
                    batch.assignments = assignments;
                }),
                read.fatal,
            )
        };
        let read = match self.finish_routed(plan.resolution, read) {
            Err(error) if fatal || error.error.code == ErrorCode::InternalError => {
                plan.cancellation.cancel();
                return Err(OfflineReadError::Read(error));
            }
            read => read,
        };
        self.validate_judge_online(plan)?;
        match read {
            Ok(_) => {
                plan.fetched_at = plan.fetched_at.min(chrono::Utc::now().timestamp());
                apply_batch(plan, &mut batch)?;
            }
            Err(error) => {
                batch.kind = JudgeScanKind::CourseFailure;
                batch.error = Some(error.error);
                plan.failed_courses += 1;
                plan.advance();
            }
        }
        Ok(plan.progress(batch))
    }
}
fn apply_batch(
    plan: &mut JudgeOnlineScan,
    batch: &mut JudgeScanBatch,
) -> Result<(), OfflineReadError> {
    match batch.kind {
        JudgeScanKind::Assignments => {
            if let Some(keys) = &plan.options.keys {
                let selected: Option<Vec<_>> = keys
                    .iter()
                    .filter(|key| Some(&key.course_id) == batch.course_id.as_ref())
                    .map(|key| {
                        batch
                            .assignments
                            .iter()
                            .find(|item| item.assignment_id == key.assignment_id)
                            .cloned()
                    })
                    .collect();
                let Some(selected) = selected else {
                    plan.cancellation.cancel();
                    return Err(invalid_target(Some(plan.resolution)));
                };
                batch.assignments = selected;
            }
            if batch.assignments.is_empty() {
                plan.advance();
            } else {
                plan.assignments = Some(batch.assignments.clone());
            }
        }
        JudgeScanKind::Detail => {
            if let Some(detail) = &batch.detail {
                plan.summaries.insert(
                    (detail.course_id.clone(), detail.assignment_id.clone()),
                    crate::features::judge::to_summary(detail),
                );
            }
            plan.detail_index += 1;
            if plan
                .assignments
                .as_ref()
                .is_some_and(|items| plan.detail_index == items.len())
            {
                plan.advance();
            }
        }
        _ => unreachable!(),
    }
    Ok(())
}
fn select_courses(
    mut courses: Vec<Course>,
    options: &JudgeOnlineOptions,
    resolution: RouteResolution,
) -> Result<Vec<Course>, OfflineReadError> {
    if let Some(keys) = &options.keys {
        let mut seen = HashSet::new();
        return keys
            .iter()
            .filter(|key| seen.insert(key.course_id.clone()))
            .map(|key| {
                courses
                    .iter()
                    .find(|course| course.course_id == key.course_id)
                    .cloned()
                    .ok_or_else(|| invalid_target(Some(resolution)))
            })
            .collect();
    }
    if let Some(index) = courses
        .iter()
        .position(|course| Some(&course.course_id) == options.preferred_course.as_ref())
    {
        let course = courses.remove(index);
        courses.insert(0, course);
    }
    Ok(courses)
}
fn invalid_target(resolution: Option<RouteResolution>) -> OfflineReadError {
    OfflineReadError::Read(RoutedError {
        error: UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "希冀目标为空或不在已核实索引中",
        ),
        resolution,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::FeatureRouteConfig;
    use crate::connection::{GatewayProbe, NetworkState, resolve_route};
    use crate::facade::RoutePolicy;
    struct NoProbe;
    impl GatewayProbe for NoProbe {
        fn probe(&self, _: std::time::Duration) -> NetworkState {
            panic!("固定路线不探测")
        }
    }
    #[test]
    fn 在线计划换路返回或清理会话后不可复活_不延长运行时寿命() {
        for clear in [false, true] {
            let root = std::env::temp_dir()
                .join(format!("ubaa-online-guard-{}-{clear}", std::process::id()));
            let mut client = UbaaClient::open(&root).unwrap();
            client
                .set_default_route_policy(RoutePolicy::Direct)
                .unwrap();
            let owner = client.direct_runtime.feature_state();
            let plan = JudgeOnlineScan {
                resolution: resolve_route(
                    RoutePolicy::Direct,
                    FeatureRouteConfig::SAFE_DEFAULT,
                    &NoProbe,
                ),
                generation: owner.judge.generation(),
                owner: Arc::downgrade(&owner),
                route_generation: client.route_generation,
                cancellation: JudgeScanCancellation(Arc::new(AtomicBool::new(false))),
                options: JudgeOnlineOptions::default(),
                courses: Vec::new(),
                course_index: 0,
                assignments: None,
                detail_index: 0,
                failed_courses: 0,
                summaries: BTreeMap::new(),
                fetched_at: 1,
            };
            drop(owner);
            client.validate_judge_online(&plan).unwrap();
            if clear {
                client.direct_runtime.clear_feature_state();
            } else {
                client
                    .set_default_route_policy(RoutePolicy::WebVpn)
                    .unwrap();
                client
                    .set_default_route_policy(RoutePolicy::Direct)
                    .unwrap();
            }
            assert!(matches!(
                client.validate_judge_online(&plan),
                Err(OfflineReadError::Cache(CacheError::Superseded))
            ));
            drop(client);
            assert!(plan.owner.upgrade().is_none());
            std::fs::remove_dir_all(root).unwrap();
        }
    }
}
