//! 只读评教计划绑定原客户端与独立缓存票据，不持有可复用的写授权。
use crate::facade::{
    CacheCompleteness, CacheError, CachePayload, CachePublication, CacheQuery, CacheReadTicket,
    CacheScope, EvaluationCoursesResponse, OfflineCache, OfflineReadError, ReadonlyFeature,
    RouteResolution, UbaaClient,
};
use crate::{
    cache::SharedReadRecovery, domain::EvaluationCourse, features::evaluation::scan::Cursor,
    internal::route_state::RouteFeatureState,
};
use std::sync::{
    Arc, Weak,
    atomic::{AtomicBool, Ordering},
};
#[derive(Clone)]
pub struct EvaluationScanCancellation(Arc<AtomicBool>);
impl EvaluationScanCancellation {
    /// 取消后续请求与迟到发布，不中断已发送请求的原会话收尾。
    pub fn cancel(&self) {
        self.0.store(true, Ordering::Release);
    }
}
pub struct EvaluationScan {
    resolution: RouteResolution,
    owner: Weak<RouteFeatureState>,
    generation: u64,
    route_generation: u64,
    cancellation: EvaluationScanCancellation,
    cache: Option<OfflineCache>,
    ticket: Option<CacheReadTicket>,
    save_error: Option<CacheError>,
    cursor: Cursor,
    fetched_at: i64,
}
pub struct EvaluationScanBatch {
    pub resolution: RouteResolution,
    pub data: EvaluationCoursesResponse,
    pub completed_course_lists: u32,
    pub fetched_at: i64,
    pub finished: bool,
    pub complete: bool,
    pub publication: Option<CachePublication>,
    pub save_error: Option<CacheError>,
    pub error: Option<crate::facade::RoutedError>,
}
impl EvaluationScan {
    #[must_use]
    pub fn cancellation(&self) -> EvaluationScanCancellation {
        self.cancellation.clone()
    }
    fn scope(&self) -> CacheScope {
        CacheScope {
            route: self.resolution.mode,
            query: CacheQuery::EvaluationCurrent,
        }
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

    fn batch(&self, publication: Option<CachePublication>) -> EvaluationScanBatch {
        EvaluationScanBatch {
            resolution: self.resolution,
            data: self.cursor.data(),
            completed_course_lists: self.cursor.completed_course_lists,
            fetched_at: self.fetched_at,
            finished: self.cursor.finished,
            complete: self.cursor.complete(),
            publication,
            save_error: self.save_error,
            error: self
                .cursor
                .error
                .clone()
                .map(|error| crate::facade::RoutedError {
                    resolution: Some(self.resolution),
                    error,
                }),
        }
    }

    fn recover_shared_read(
        &mut self,
        mut batch: EvaluationScanBatch,
    ) -> Result<EvaluationScanBatch, OfflineReadError> {
        let (Some(cache), Some(ticket)) = (&self.cache, &self.ticket) else {
            return Err(OfflineReadError::Cache(CacheError::Superseded));
        };
        let recovery = cache
            .repository(|repo| repo.recover_shared_read(ticket, batch.complete))
            .map_err(OfflineReadError::Cache)?;
        let recovery = if let SharedReadRecovery::Retry(next) = recovery {
            match cache.repository(|repo| {
                repo.publish(
                    &next,
                    CachePayload::EvaluationCurrent(batch.data.clone().into()),
                    batch.fetched_at,
                    CacheCompleteness::Complete,
                )
            }) {
                Err(CacheError::Superseded) => cache
                    .repository(|repo| {
                        Ok(match repo.recover_shared_read(&next, false)? {
                            SharedReadRecovery::Reuse(record) => {
                                SharedReadRecovery::Superseded(Some(record))
                            }
                            recovery => recovery,
                        })
                    })
                    .map_err(OfflineReadError::Cache)?,
                result => {
                    batch.publication = self.storage(result)?;
                    batch.save_error = self.save_error;
                    return Ok(batch);
                }
            }
        } else {
            recovery
        };
        self.cursor.finished = true;
        self.ticket = None;
        batch.finished = true;
        batch.error = None;
        let selected = match recovery {
            SharedReadRecovery::Reuse(record) => {
                batch.complete = true;
                batch.publication = Some(CachePublication::Stored);
                batch.save_error = None;
                Some(record)
            }
            SharedReadRecovery::Superseded(record) => {
                batch.complete = false;
                batch.publication = record.as_ref().map(|_| CachePublication::Preserved);
                batch.save_error = Some(CacheError::Superseded);
                record
            }
            SharedReadRecovery::Retry(_) => {
                return Err(OfflineReadError::Cache(CacheError::Superseded));
            }
        };
        batch.data = if let Some(record) = selected {
            let CachePayload::EvaluationCurrent(value) = record.payload else {
                return Err(OfflineReadError::Cache(CacheError::Corrupt));
            };
            batch.fetched_at = record.fetched_at;
            batch.resolution.mode = record.scope.route;
            batch.resolution.diagnostic.mode = record.scope.route;
            EvaluationCoursesResponse {
                courses: value
                    .courses
                    .into_iter()
                    .map(|course| EvaluationCourse {
                        id: course.id,
                        kcmc: course.kcmc,
                        bpmc: course.bpmc,
                        is_evaluated: course.is_evaluated,
                        ..EvaluationCourse::default()
                    })
                    .collect(),
                progress: value.progress,
            }
        } else {
            EvaluationCoursesResponse::default()
        };
        Ok(batch)
    }
}
impl UbaaClient {
    /// 核对所需路线与本机身份，创建只读分段；不读取任何写前题目或模式。
    ///
    /// # Errors
    /// 身份、会话、已关闭缓存或参数失败时不创建计划。
    pub async fn begin_evaluation_scan(
        &mut self,
        cache: Option<&OfflineCache>,
        expected_identity: Option<&str>,
    ) -> Result<EvaluationScan, OfflineReadError> {
        if expected_identity.is_some_and(|id| id.trim().is_empty() || id.len() > 128) {
            return Err(OfflineReadError::Cache(CacheError::InvalidInput));
        }
        if let Some(cache) = cache {
            cache
                .check_read_generation()
                .map_err(OfflineReadError::Cache)?;
        }
        let auth = self
            .recover_required_session(ReadonlyFeature::Evaluation)
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
        // 恢复有效会话也要补齐评教原参数；不能依赖只有完整登录才设置的易失字段。
        let account_name = auth
            .data
            .user
            .school_id
            .as_deref()
            .filter(|value| !value.trim().is_empty())
            .or(auth
                .data
                .user
                .username
                .as_deref()
                .filter(|value| !value.trim().is_empty()))
            .ok_or_else(|| {
                OfflineReadError::Read(crate::facade::RoutedError {
                    resolution: Some(resolution),
                    error: crate::facade::UbaaError::new(
                        crate::facade::ErrorCode::UpstreamChanged,
                        crate::facade::ErrorKind::Upstream,
                        false,
                        "评教账号标识缺失",
                    ),
                })
            })?;
        self.runtime_for(resolution.mode)
            .remember_account_name(Some(account_name));
        let owner = self.runtime_for(resolution.mode).feature_state();
        let mut plan = EvaluationScan {
            resolution,
            owner: Arc::downgrade(&owner),
            generation: owner.lifecycle_generation(),
            route_generation: self.route_generation,
            cancellation: EvaluationScanCancellation(Arc::new(AtomicBool::new(false))),
            cache: cache.cloned(),
            ticket: None,
            save_error: None,
            cursor: Cursor::default(),
            fetched_at: chrono::Utc::now().timestamp(),
        };
        if let Some(cache) = cache {
            plan.ticket = plan.storage(cache.begin(plan.scope()))?;
        }
        Ok(plan)
    }
    fn validate_evaluation_owner(
        &mut self,
        plan: &mut EvaluationScan,
        before: bool,
    ) -> Result<(), OfflineReadError> {
        self.guard_latest_routed().map_err(OfflineReadError::Read)?;
        let owner = self.runtime_for(plan.resolution.mode).feature_state();
        if (before && plan.cursor.finished)
            || plan.cancellation.0.load(Ordering::Acquire)
            || !Weak::ptr_eq(&Arc::downgrade(&owner), &plan.owner)
            || owner.lifecycle_generation() != plan.generation
            || self.route_generation != plan.route_generation
        {
            return Err(OfflineReadError::Cache(CacheError::Superseded));
        }
        Ok(())
    }
    /// 每次只推进完整激活或一个任务/问卷/课程 GET，完成会话仲裁后交回宿主。
    ///
    /// # Errors
    /// 认证、会话冲突、取消或任何生命周期失效终止计划，部分子失败保留原容错。
    pub async fn next_evaluation_scan(
        &mut self,
        plan: &mut EvaluationScan,
    ) -> Result<EvaluationScanBatch, OfflineReadError> {
        let result = self.advance_evaluation_scan(plan).await;
        if result.is_err() {
            plan.cancellation.cancel();
            if let (Some(cache), Some(ticket)) = (&plan.cache, &plan.ticket) {
                cache.failure(ticket, chrono::Utc::now().timestamp());
            }
        }
        result
    }
    async fn advance_evaluation_scan(
        &mut self,
        plan: &mut EvaluationScan,
    ) -> Result<EvaluationScanBatch, OfflineReadError> {
        self.validate_evaluation_owner(plan, true)?;
        if let Some(cache) = &plan.cache {
            let result = if let Some(ticket) = &mut plan.ticket {
                cache.repository(|repo| repo.renew_read(ticket))
            } else {
                cache.check_read_generation()
            };
            if matches!(result, Err(CacheError::Superseded)) && plan.ticket.is_some() {
                return plan.recover_shared_read(plan.batch(None));
            }
            plan.storage(result)?;
        }
        let original = plan.cursor.clone();
        let resolution = plan.resolution;
        let initial_route = resolution.mode;
        let (resolution, result) = crate::facade::routing::read_with_fallback!(self, resolution, {
            let mut cursor = original.clone();
            cursor
                .advance(
                    self.runtime_for(resolution.mode),
                    resolution.mode != initial_route,
                )
                .await
                .map(|()| cursor)
        });
        if resolution.mode != plan.resolution.mode {
            let owner = self.runtime_for(resolution.mode).feature_state();
            plan.owner = Arc::downgrade(&owner);
            plan.generation = owner.lifecycle_generation();
            if let Some(ticket) = &mut plan.ticket {
                ticket.set_source_route(resolution.mode);
            }
        }
        plan.resolution = resolution;
        plan.cursor = self
            .finish_routed(resolution, result)
            .map_err(OfflineReadError::Read)?
            .data;
        self.validate_evaluation_owner(plan, false)?;
        let mut batch = plan.batch(None);
        if let Some(cache) = &plan.cache {
            let result = match &plan.ticket {
                Some(ticket) if batch.finished => cache
                    .repository(|repo| {
                        repo.publish(
                            ticket,
                            CachePayload::EvaluationCurrent(batch.data.clone().into()),
                            batch.fetched_at,
                            if batch.complete {
                                CacheCompleteness::Complete
                            } else {
                                CacheCompleteness::Partial
                            },
                        )
                    })
                    .map(Some),
                Some(ticket) => cache.validate_read(ticket).map(|()| None),
                None => cache.check_read_generation().map(|()| None),
            };
            if matches!(result, Err(CacheError::Superseded)) && plan.ticket.is_some() {
                return plan.recover_shared_read(batch);
            }
            batch.publication = plan.storage(result)?.flatten();
            batch.save_error = plan.save_error;
        }
        Ok(batch)
    }
}
