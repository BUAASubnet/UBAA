//! 绑定账号、路线与会话代次的希冀分段读取，不持有后台工作线程。
use super::{
    Assignment, Course, JudgeAssignmentDetail, OfflineCache, OfflineReadError, ReadonlyFeature,
    RouteResolution, Routed, UbaaClient, UbaaError,
};
use crate::{
    cache::{CacheError, CacheQuery, CacheReadTicket, CacheScope},
    features::{judge::scan, state::RouteFeatureState},
};
use std::sync::{
    Arc, Weak,
    atomic::{AtomicBool, Ordering},
};

/// 取消只阻止后续批次和迟到返回；不会中断已经发送的 HTTP 请求。
#[derive(Clone)]
pub struct JudgeScanCancellation(Arc<AtomicBool>);
impl JudgeScanCancellation {
    pub fn cancel(&self) {
        self.0.store(true, Ordering::Release);
    }
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum JudgeScanKind {
    Assignments,
    Detail,
    CourseFailure,
    Finished,
}
/// 渐进结果仅包含读取数据；不构成写资格或持久化成功证明。
pub struct JudgeScanBatch {
    pub kind: JudgeScanKind,
    pub course_id: Option<String>,
    pub assignments: Vec<Assignment>,
    pub detail: Option<JudgeAssignmentDetail>,
    pub error: Option<UbaaError>,
    pub finished: bool,
    pub complete: bool,
    pub failed_courses: usize,
}
/// 扫描计划不包含复制的会话或 Cookie；每次操作仍使用原客户端。
pub struct JudgeScan {
    pub(super) resolution: RouteResolution,
    owner: Weak<RouteFeatureState>,
    generation: u64,
    route_generation: u64,
    pub(super) cache: OfflineCache,
    pub(super) ticket: CacheReadTicket,
    pub(super) courses: Vec<Course>,
    pub(super) course_index: usize,
    pub(super) assignments: Option<Vec<Assignment>>,
    pub(super) detail_index: usize,
    pub(super) failed_courses: usize,
    cancellation: JudgeScanCancellation,
    force_fresh: bool,
    pub(super) course_ticket: Option<CacheReadTicket>,
}
impl JudgeScan {
    #[must_use]
    pub fn courses(&self) -> &[Course] {
        &self.courses
    }
    #[must_use]
    pub fn cancellation(&self) -> JudgeScanCancellation {
        self.cancellation.clone()
    }
    pub(super) fn advance_course(&mut self) {
        self.course_index += 1;
        self.assignments = None;
        self.detail_index = 0;
    }
}
impl UbaaClient {
    /// 核实本机账号后读取课程索引；不永久排除历史课程。
    ///
    /// # Errors
    /// 认证、缓存身份或索引读取失败时返回原错误分类。
    pub async fn begin_judge_scan(
        &mut self,
        cache: &OfflineCache,
        include_expired: bool,
        preferred_course: Option<&str>,
    ) -> Result<JudgeScan, OfflineReadError> {
        self.begin_judge_scan_with_freshness(cache, include_expired, preferred_course, false)
            .await
    }
    pub(super) async fn begin_judge_scan_with_freshness(
        &mut self,
        cache: &OfflineCache,
        include_expired: bool,
        preferred_course: Option<&str>,
        force_fresh: bool,
    ) -> Result<JudgeScan, OfflineReadError> {
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
        let ticket = cache
            .begin(CacheScope {
                route: resolution.mode,
                query: CacheQuery::JudgeSummaries { include_expired },
            })
            .map_err(OfflineReadError::Cache)?;
        let course_ticket = if force_fresh {
            Some(
                cache
                    .begin(CacheScope {
                        route: resolution.mode,
                        query: CacheQuery::JudgeCourses,
                    })
                    .map_err(OfflineReadError::Cache)?,
            )
        } else {
            None
        };
        let read = scan::courses(self.runtime_for(resolution.mode), force_fresh).await;
        let mut courses = match self.finish_routed(resolution, read.result) {
            Ok(result) => result.data,
            Err(error) => {
                if force_fresh {
                    cache.fail_scan(&ticket, course_ticket.as_ref());
                }
                return Err(OfflineReadError::Read(error));
            }
        };
        cache
            .validate_read(&ticket)
            .map_err(OfflineReadError::Cache)?;
        if let Some(index) = courses
            .iter()
            .position(|course| Some(course.course_id.as_str()) == preferred_course)
        {
            let course = courses.remove(index);
            courses.insert(0, course);
        }
        let owner = self.runtime_for(resolution.mode).feature_state();
        Ok(JudgeScan {
            resolution,
            force_fresh,
            course_ticket,
            generation: owner.judge.generation(),
            owner: Arc::downgrade(&owner),
            route_generation: self.route_generation,
            cache: cache.clone(),
            ticket,
            courses,
            course_index: 0,
            assignments: None,
            detail_index: 0,
            failed_courses: 0,
            cancellation: JudgeScanCancellation(Arc::new(AtomicBool::new(false))),
        })
    }
    pub(super) fn validate_judge_scan(&mut self, plan: &JudgeScan) -> Result<(), OfflineReadError> {
        self.guard_latest_routed().map_err(OfflineReadError::Read)?;
        let owner = self.runtime_for(plan.resolution.mode).feature_state();
        if plan.cancellation.0.load(Ordering::Acquire)
            || !Weak::ptr_eq(&Arc::downgrade(&owner), &plan.owner)
            || owner.judge.generation() != plan.generation
            || self.route_generation != plan.route_generation
        {
            return Err(OfflineReadError::Cache(CacheError::Superseded));
        }
        plan.cache
            .validate_read(&plan.ticket)
            .map_err(OfflineReadError::Cache)
    }
    /// 最多读取一个作业索引或一个详情；完整收尾后才返回让位。
    ///
    /// # Errors
    /// 取消、会话替换、路线切换或较新请求使旧计划失效；认证仲裁失败停止整个扫描。
    pub async fn next_judge_scan(
        &mut self,
        plan: &mut JudgeScan,
    ) -> Result<Routed<JudgeScanBatch>, OfflineReadError> {
        self.validate_judge_scan(plan)?;
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
        if let Some(course) = plan.courses.get(plan.course_index).cloned() {
            batch.course_id = Some(course.course_id.clone());
            let (result, fatal) = if let Some(assignments) = &plan.assignments {
                let read = scan::detail(
                    self.runtime_for(plan.resolution.mode),
                    &assignments[plan.detail_index],
                    plan.force_fresh,
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
                let read = scan::assignments(
                    self.runtime_for(plan.resolution.mode),
                    &course,
                    plan.force_fresh,
                )
                .await;
                (
                    read.result.map(|assignments| {
                        batch.kind = JudgeScanKind::Assignments;
                        batch.assignments = assignments;
                    }),
                    read.fatal,
                )
            };
            let result = self.finish_routed(plan.resolution, result);
            // 认证收尾本身会递增会话代次，必须保留其原始错误供宿主恢复。
            let result = match result {
                Err(error) if fatal || error.error.code == super::ErrorCode::InternalError => {
                    plan.cancellation.cancel();
                    return Err(OfflineReadError::Read(error));
                }
                result => result,
            };
            // 迟到内容在改变扫描游标或交给宿主之前丢弃。
            self.validate_judge_scan(plan)?;
            match result {
                Ok(_) => match batch.kind {
                    JudgeScanKind::Assignments => {
                        if batch.assignments.is_empty() {
                            plan.advance_course();
                        } else {
                            plan.assignments = Some(batch.assignments.clone());
                        }
                    }
                    JudgeScanKind::Detail => {
                        plan.detail_index += 1;
                        if plan
                            .assignments
                            .as_ref()
                            .is_some_and(|items| plan.detail_index == items.len())
                        {
                            plan.advance_course();
                        }
                    }
                    _ => unreachable!(),
                },
                Err(error) => {
                    batch.kind = JudgeScanKind::CourseFailure;
                    batch.error = Some(error.error);
                    plan.failed_courses += 1;
                    plan.advance_course();
                }
            }
        }
        batch.finished = plan.course_index >= plan.courses.len();
        batch.failed_courses = plan.failed_courses;
        batch.complete = batch.finished && plan.failed_courses == 0;
        Ok(Routed {
            data: batch,
            resolution: plan.resolution,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        config::FeatureRouteConfig,
        connection::{GatewayProbe, NetworkState, resolve_route},
        domain::RoutePolicy,
    };
    struct NoProbe;
    impl GatewayProbe for NoProbe {
        fn probe(&self, _: std::time::Duration) -> NetworkState {
            panic!("固定路线不应探测");
        }
    }
    #[test]
    fn returning_to_the_original_route_does_not_revive_an_old_plan() {
        let root =
            std::env::temp_dir().join(format!("ubaa-judge-scan-route-{}", std::process::id()));
        let mut client = UbaaClient::open(&root).unwrap();
        client
            .set_default_route_policy(RoutePolicy::Direct)
            .unwrap();
        let cache = OfflineCache::open(
            &root,
            "0123456789abcdef0123456789abcdef",
            "synthetic",
            super::super::CacheKey::new([9; 32]),
            super::super::CacheLimits::default(),
        )
        .unwrap();
        let ticket = cache
            .begin(CacheScope {
                route: super::super::ConnectionMode::Direct,
                query: CacheQuery::JudgeSummaries {
                    include_expired: false,
                },
            })
            .unwrap();
        let owner = client.direct_runtime.feature_state();
        let plan = JudgeScan {
            force_fresh: false,
            course_ticket: None,
            resolution: resolve_route(
                RoutePolicy::Direct,
                FeatureRouteConfig::SAFE_DEFAULT,
                &NoProbe,
            ),
            generation: owner.judge.generation(),
            owner: Arc::downgrade(&owner),
            route_generation: client.route_generation,
            cache: cache.clone(),
            ticket,
            courses: Vec::new(),
            course_index: 0,
            assignments: None,
            detail_index: 0,
            failed_courses: 0,
            cancellation: JudgeScanCancellation(Arc::new(AtomicBool::new(false))),
        };
        drop(owner);
        client.validate_judge_scan(&plan).unwrap();
        client
            .set_default_route_policy(RoutePolicy::WebVpn)
            .unwrap();
        client
            .set_default_route_policy(RoutePolicy::Direct)
            .unwrap();
        assert!(matches!(
            client.validate_judge_scan(&plan),
            Err(OfflineReadError::Cache(CacheError::Superseded))
        ));
        drop(client);
        assert!(
            plan.owner.upgrade().is_none(),
            "计划不得延长客户端私有状态的生命周期"
        );
        drop((plan, cache));
        let _ = std::fs::remove_dir_all(root);
    }
}
