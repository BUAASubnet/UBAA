//! SPOC 页读取绑定原客户端与生命周期；宿主在 next 调用之间释放原客户端锁。
use crate::facade::{
    CacheCompleteness, CacheError, CachePayload, CachePublication, CacheQuery, CacheReadTicket,
    CacheScope, ErrorKind, HomeReadData, HomeRefresh, OfflineCache, OfflineReadError,
    OfflineRefresh, ReadonlyFeature, RouteResolution, SpocAssignments, UbaaClient,
};
use crate::{features::spoc::scan, internal::route_state::RouteFeatureState};
use std::{
    collections::HashSet,
    sync::{
        Arc, Weak,
        atomic::{AtomicBool, Ordering},
    },
};

#[derive(Clone)]
pub struct SpocScanCancellation(Arc<AtomicBool>);
impl SpocScanCancellation {
    /// 不打断原认证事务，只拒绝后续步骤和持久发布。
    pub fn cancel(&self) {
        self.0.store(true, Ordering::Release);
    }
}
#[derive(Clone, Copy)]
enum Stage {
    Term,
    Courses,
    Page,
}
/// 仅含只读领域数据及弱客户端标识，不包含会话凭据。
pub struct SpocScan {
    resolution: RouteResolution,
    owner: Weak<RouteFeatureState>,
    generation: u64,
    route_generation: u64,
    cancellation: SpocScanCancellation,
    cache: Option<OfflineCache>,
    ticket: Option<CacheReadTicket>,
    save_error: Option<CacheError>,
    stage: Stage,
    data: SpocAssignments,
    courses: scan::Courses,
    seen: HashSet<String>,
    next_page: u32,
    complete: bool,
    fetched_at: i64,
    finished: bool,
}
pub struct SpocScanBatch {
    pub resolution: RouteResolution,
    pub data: SpocAssignments,
    pub fetched_at: i64,
    pub completed_pages: u32,
    pub finished: bool,
    pub complete: bool,
    pub publication: Option<CachePublication>,
    pub save_error: Option<CacheError>,
}
impl SpocScanBatch {
    pub(super) fn into_home(self) -> HomeRefresh {
        HomeRefresh {
            result: OfflineRefresh {
                scope: super::spoc::term_scope(self.resolution.mode, &self.data.term_code),
                data: HomeReadData::SpocAssignments(self.data),
                resolution: self.resolution,
                fetched_at: self.fetched_at,
                save_error: self.save_error,
            },
            complete: self.complete,
            publication: self.publication,
        }
    }
}
impl SpocScan {
    #[must_use]
    pub fn cancellation(&self) -> SpocScanCancellation {
        self.cancellation.clone()
    }
    fn apply_page(
        &mut self,
        mut page: scan::Page,
    ) -> Result<Option<CachePublication>, OfflineReadError> {
        let mut publication = None;
        for row in &page.data.assignments {
            if !self.seen.insert(row.assignment_id.clone()) {
                page.complete = false;
            }
        }
        self.complete &= page.complete;
        if let (Some(cache), Some(ticket)) = (&self.cache, &self.ticket) {
            let result = cache.repository(|repo| {
                let child = repo.begin_read_guarded(
                    CacheScope {
                        route: self.resolution.mode,
                        query: CacheQuery::SpocPage {
                            term: self.data.term_code.clone(),
                            page: self.next_page,
                            size: 15,
                        },
                    },
                    ticket,
                )?;
                repo.publish_guarded(
                    &child,
                    ticket,
                    CachePayload::SpocPage {
                        data: page.data.clone(),
                        page: self.next_page,
                        size: 15,
                        has_next: page.has_next,
                        pages: page.pages,
                    },
                    chrono::Utc::now().timestamp(),
                    if page.complete && self.complete {
                        CacheCompleteness::Complete
                    } else {
                        CacheCompleteness::Partial
                    },
                )
            });
            self.storage(result)?;
        }
        let mut present: HashSet<_> = self
            .data
            .assignments
            .iter()
            .map(|row| row.assignment_id.clone())
            .collect();
        self.data.assignments.extend(
            page.data
                .assignments
                .into_iter()
                .filter(|row| present.insert(row.assignment_id.clone())),
        );
        scan::sort(&mut self.data);
        self.next_page = self
            .next_page
            .checked_add(1)
            .ok_or(OfflineReadError::Cache(CacheError::InvalidInput))?;
        if page.finished {
            if let (Some(cache), Some(ticket)) = (&self.cache, &self.ticket) {
                let result =
                    super::spoc::publish(cache, ticket, &self.data, self.fetched_at, self.complete);
                publication = self.storage(result)?;
            }
            self.finished = true;
        }
        Ok(publication)
    }
    fn storage<T>(
        &mut self,
        result: crate::facade::CacheResult<T>,
    ) -> Result<Option<T>, OfflineReadError> {
        match result {
            Ok(value) => Ok(Some(value)),
            Err(error @ (CacheError::Inactive | CacheError::Superseded)) => {
                Err(OfflineReadError::Cache(error))
            }
            Err(error) => {
                self.save_error = Some(error);
                self.ticket = None;
                Ok(None)
            }
        }
    }
    fn batch(&self, publication: Option<CachePublication>) -> SpocScanBatch {
        SpocScanBatch {
            resolution: self.resolution,
            data: self.data.clone(),
            fetched_at: self.fetched_at,
            completed_pages: self.next_page - 1,
            finished: self.finished,
            complete: self.finished && self.complete,
            publication,
            save_error: self.save_error,
        }
    }
}
impl UbaaClient {
    pub(super) async fn refresh_spoc_scan(
        &mut self,
        cache: &OfflineCache,
    ) -> Result<HomeRefresh, OfflineReadError> {
        let mut plan = self.begin_spoc_scan(Some(cache), None).await?;
        loop {
            let batch = self.next_spoc_scan(&mut plan).await?;
            if batch.finished {
                return Ok(batch.into_home());
            }
        }
    }

    /// 恢复所需路线并核实账号；学校学期、课程、每页由后续 next 独立推进。
    /// 无缓存时 `expected_identity` 仍可绑定本机账号；不会为只读建立第二个会话。
    ///
    /// # Errors
    /// 身份、已退出仓库、所需会话或参数错误不创建计划。
    pub async fn begin_spoc_scan(
        &mut self,
        cache: Option<&OfflineCache>,
        expected_identity: Option<&str>,
    ) -> Result<SpocScan, OfflineReadError> {
        if expected_identity.is_some_and(|id| id.trim().is_empty() || id.len() > 128) {
            return Err(OfflineReadError::Cache(CacheError::InvalidInput));
        }
        let mut save_error = None;
        if let Some(cache) = cache {
            match cache.check_read_generation() {
                Ok(()) => {}
                Err(error @ (CacheError::Inactive | CacheError::Superseded)) => {
                    return Err(OfflineReadError::Cache(error));
                }
                Err(error) => save_error = Some(error),
            }
        }
        let auth = self
            .recover_required_session(ReadonlyFeature::Spoc)
            .await
            .map_err(OfflineReadError::Read)?;
        let resolution = auth.resolution;
        if cache.is_some_and(|cache| !cache.matches(&auth.data.user))
            || expected_identity.is_some_and(|expected| {
                ![
                    auth.data.user.username.as_deref(),
                    auth.data.user.school_id.as_deref(),
                ]
                .into_iter()
                .flatten()
                .any(|value| value.trim() == expected.trim())
            })
        {
            return Err(OfflineReadError::IdentityMismatch {
                resolution,
                cache_error: cache.and_then(|cache| cache.deactivate().err()),
            });
        }
        let owner = self.runtime_for(resolution.mode).feature_state();
        let mut plan = SpocScan {
            resolution,
            owner: Arc::downgrade(&owner),
            generation: owner.lifecycle_generation(),
            route_generation: self.route_generation,
            cancellation: SpocScanCancellation(Arc::new(AtomicBool::new(false))),
            cache: cache.cloned(),
            ticket: None,
            save_error,
            stage: Stage::Term,
            data: SpocAssignments::default(),
            courses: scan::Courses::default(),
            seen: HashSet::new(),
            next_page: 1,
            complete: true,
            fetched_at: 0,
            finished: false,
        };
        if save_error.is_none()
            && let Some(cache) = cache
        {
            plan.ticket = plan.storage(cache.begin(CacheScope {
                route: resolution.mode,
                query: CacheQuery::SpocSelection,
            }))?;
        }
        Ok(plan)
    }
    fn validate_spoc_owner(&mut self, plan: &SpocScan) -> Result<(), OfflineReadError> {
        self.guard_latest_routed().map_err(OfflineReadError::Read)?;
        let owner = self.runtime_for(plan.resolution.mode).feature_state();
        if plan.cancellation.0.load(Ordering::Acquire)
            || !Weak::ptr_eq(&Arc::downgrade(&owner), &plan.owner)
            || owner.lifecycle_generation() != plan.generation
            || self.route_generation != plan.route_generation
        {
            return Err(OfflineReadError::Cache(CacheError::Superseded));
        }
        Ok(())
    }
    fn validate_spoc_scan(&mut self, plan: &mut SpocScan) -> Result<(), OfflineReadError> {
        self.validate_spoc_owner(plan)?;
        if plan.finished {
            return Err(OfflineReadError::Cache(CacheError::Superseded));
        }
        if let Some(cache) = &plan.cache {
            let result = if let Some(ticket) = &plan.ticket {
                cache.validate_read(ticket)
            } else {
                cache.check_read_generation()
            };
            plan.storage(result)?;
        }
        Ok(())
    }
    /// 最多读取当前学期、课程补充或一个全局页，完成认证仲裁后返回渐进投影。
    ///
    /// # Errors
    /// 请求失败、明确范围错配或生命周期改变终止当前计划，禁止跳页和迟到回写。
    pub async fn next_spoc_scan(
        &mut self,
        plan: &mut SpocScan,
    ) -> Result<SpocScanBatch, OfflineReadError> {
        let result = self.advance_spoc_scan(plan).await;
        if result.is_err() {
            plan.cancellation.cancel();
            if let (Some(cache), Some(ticket)) = (&plan.cache, &plan.ticket) {
                cache.failure(ticket, chrono::Utc::now().timestamp());
            }
        }
        result
    }
    async fn advance_spoc_scan(
        &mut self,
        plan: &mut SpocScan,
    ) -> Result<SpocScanBatch, OfflineReadError> {
        self.validate_spoc_scan(plan)?;
        if let (Some(cache), Some(ticket)) = (&plan.cache, &mut plan.ticket) {
            let result = cache.repository(|repo| repo.renew_read(ticket));
            plan.storage(result)?;
        }
        let mut publication = None;
        match plan.stage {
            Stage::Term => {
                let result = scan::term(self.runtime_for(plan.resolution.mode)).await;
                plan.data = self
                    .finish_routed(plan.resolution, result)
                    .map_err(OfflineReadError::Read)?
                    .data;
                plan.fetched_at = chrono::Utc::now().timestamp();
                plan.stage = Stage::Courses;
            }
            Stage::Courses => {
                let result =
                    scan::courses(self.runtime_for(plan.resolution.mode), &plan.data.term_code)
                        .await;
                match self.finish_routed(plan.resolution, result) {
                    Ok(value) => plan.courses = value.data,
                    Err(error)
                        if matches!(
                            error.error.kind,
                            ErrorKind::Authentication | ErrorKind::Internal
                        ) =>
                    {
                        return Err(OfflineReadError::Read(error));
                    }
                    Err(_) => plan.complete = false,
                }
                plan.stage = Stage::Page;
            }
            Stage::Page => {
                let result = scan::page(
                    self.runtime_for(plan.resolution.mode),
                    &plan.data,
                    plan.next_page,
                    &plan.courses,
                )
                .await;
                let page = self
                    .finish_routed(plan.resolution, result)
                    .map_err(OfflineReadError::Read)?
                    .data;
                self.validate_spoc_scan(plan)?;
                publication = plan.apply_page(page)?;
            }
        }
        if !plan.finished {
            self.validate_spoc_scan(plan)?;
        }
        Ok(plan.batch(publication))
    }
}

mod detail;
pub use detail::{SpocDetailScan, SpocDetailScanBatch};
