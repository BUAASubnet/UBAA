//! 完整学期导入每次只推进一个已验证读取边界，不复制网络会话。
use super::{
    CacheError, CacheQuery, CacheReadTicket, CacheScope, CachedSemesterSchedule, OfflineCache,
    OfflineReadError, ReadonlyFeature, RouteResolution, Routed, Term, UbaaClient, Week,
    WeeklySchedule,
};
use crate::internal::route_state::RouteFeatureState;
use std::{
    collections::BTreeMap,
    sync::{
        Arc, Weak,
        atomic::{AtomicBool, Ordering},
    },
};

#[derive(Clone)]
pub struct ScheduleImportCancellation(Arc<AtomicBool>);
impl ScheduleImportCancellation {
    /// 只阻止后续请求和发布；已经发送的只读请求仍按原会话收尾。
    pub fn cancel(&self) {
        self.0.store(true, Ordering::Release);
    }
}
/// 本批完成后的覆盖进度；`finished` 不等同于已持久保存，须同时检查 `save_error`。
pub struct ScheduleImportBatch {
    pub term_code: String,
    pub completed_weeks: usize,
    pub total_weeks: Option<usize>,
    pub finished: bool,
    pub save_error: Option<CacheError>,
}
#[derive(Clone, Copy)]
enum Stage {
    Terms,
    Weeks,
    Week,
}
/// 计划绑定原客户端、账号、实际路线和读取票据，不拥有Cookie或认证副本。
pub struct ScheduleImport {
    resolution: RouteResolution,
    owner: Weak<RouteFeatureState>,
    generation: u64,
    route_generation: u64,
    cache: OfflineCache,
    ticket: CacheReadTicket,
    term: String,
    terms: Vec<Term>,
    weeks: Vec<Week>,
    schedules: BTreeMap<i32, WeeklySchedule>,
    terms_observation: Option<(i64, i64)>,
    weeks_observation: Option<(i64, i64)>,
    observations: BTreeMap<i32, (i64, i64)>,
    stage: Stage,
    finished: bool,
    cancellation: ScheduleImportCancellation,
}
impl ScheduleImport {
    fn begin_query(&self, query: CacheQuery) -> Result<CacheReadTicket, OfflineReadError> {
        self.cache
            .begin(CacheScope {
                route: self.resolution.mode,
                query,
            })
            .map_err(OfflineReadError::Cache)
    }

    #[must_use]
    pub fn cancellation(&self) -> ScheduleImportCancellation {
        self.cancellation.clone()
    }
    fn finish(&mut self) -> Result<ScheduleImportBatch, OfflineReadError> {
        let value = CachedSemesterSchedule::new(
            self.term.clone(),
            std::mem::take(&mut self.terms),
            self.weeks.clone(),
            self.schedules.clone(),
            chrono::Utc::now().timestamp(),
        )
        .and_then(|value| {
            value.with_observations(
                self.weeks_observation.ok_or(CacheError::InvalidInput)?,
                self.observations.clone(),
            )
        })
        .and_then(|value| {
            value.with_terms_observation(self.terms_observation.ok_or(CacheError::InvalidInput)?)
        })
        .map_err(OfflineReadError::Cache)?;
        let saved = self
            .cache
            .repository(|repo| repo.publish_imported_semester(&self.ticket, value));
        if let Err(error @ (CacheError::Inactive | CacheError::Superseded)) = saved {
            return Err(OfflineReadError::Cache(error));
        }
        let save_error = saved.err();
        if save_error.is_some() {
            self.cache
                .failure(&self.ticket, chrono::Utc::now().timestamp());
        }
        self.finished = true;
        Ok(self.batch(save_error))
    }
    fn batch(&self, save_error: Option<CacheError>) -> ScheduleImportBatch {
        ScheduleImportBatch {
            term_code: self.term.clone(),
            completed_weeks: self.schedules.len(),
            total_weeks: matches!(self.stage, Stage::Week).then_some(self.weeks.len()),
            finished: self.finished,
            save_error,
        }
    }
}
impl UbaaClient {
    /// 核实账号并登记导入；学期必须由调用方明确选择，不猜测默认项。
    ///
    /// # Errors
    /// 参数、本地仓库、身份或所需路线恢复失败时不创建计划。
    pub async fn begin_schedule_import(
        &mut self,
        cache: &OfflineCache,
        term: &str,
    ) -> Result<ScheduleImport, OfflineReadError> {
        cache
            .check_read_generation()
            .map_err(OfflineReadError::Cache)?;
        if term.trim().is_empty() || term.len() > 1024 {
            return Err(OfflineReadError::Cache(CacheError::InvalidInput));
        }
        let authenticated = self
            .recover_required_session(ReadonlyFeature::Schedule)
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
                query: CacheQuery::ScheduleImport { term: term.into() },
            })
            .map_err(OfflineReadError::Cache)?;
        let owner = self.runtime_for(resolution.mode).feature_state();
        Ok(ScheduleImport {
            resolution,
            generation: owner.lifecycle_generation(),
            owner: Arc::downgrade(&owner),
            route_generation: self.route_generation,
            cache: cache.clone(),
            ticket,
            term: term.into(),
            terms: Vec::new(),
            weeks: Vec::new(),
            schedules: BTreeMap::new(),
            terms_observation: None,
            weeks_observation: None,
            observations: BTreeMap::new(),
            stage: Stage::Terms,
            finished: false,
            cancellation: ScheduleImportCancellation(Arc::new(AtomicBool::new(false))),
        })
    }
    fn validate_schedule_import(&mut self, plan: &ScheduleImport) -> Result<(), OfflineReadError> {
        self.guard_latest_routed().map_err(OfflineReadError::Read)?;
        let owner = self.runtime_for(plan.resolution.mode).feature_state();
        if plan.finished
            || plan.cancellation.0.load(Ordering::Acquire)
            || !Weak::ptr_eq(&Arc::downgrade(&owner), &plan.owner)
            || owner.lifecycle_generation() != plan.generation
            || self.route_generation != plan.route_generation
        {
            return Err(OfflineReadError::Cache(CacheError::Superseded));
        }
        plan.cache
            .validate_read(&plan.ticket)
            .map_err(OfflineReadError::Cache)
    }
    /// 推进学期索引、周次索引或单周读取；每批含原激活/会话维护的完整收尾。
    ///
    /// # Errors
    /// 取消、较新请求、路线/会话替换、学校失败或不完整元数据终止计划；不自动重发。
    pub async fn next_schedule_import(
        &mut self,
        plan: &mut ScheduleImport,
    ) -> Result<Routed<ScheduleImportBatch>, OfflineReadError> {
        let result = self.advance_schedule_import(plan).await;
        if result.is_err() {
            plan.cancellation.cancel();
            plan.cache
                .failure(&plan.ticket, chrono::Utc::now().timestamp());
        }
        result
    }
    async fn advance_schedule_import(
        &mut self,
        plan: &mut ScheduleImport,
    ) -> Result<Routed<ScheduleImportBatch>, OfflineReadError> {
        self.validate_schedule_import(plan)?;
        plan.cache
            .repository(|repo| repo.renew_read(&mut plan.ticket))
            .map_err(OfflineReadError::Cache)?;
        match plan.stage {
            Stage::Terms => {
                let ticket = plan.begin_query(CacheQuery::ScheduleTerms)?;
                let result =
                    crate::features::schedule::get_terms(self.runtime_for(plan.resolution.mode))
                        .await;
                let result = self
                    .finish_routed(plan.resolution, result)
                    .map_err(OfflineReadError::Read)?;
                self.validate_schedule_import(plan)?;
                if result
                    .data
                    .iter()
                    .filter(|term| term.item_code == plan.term)
                    .count()
                    != 1
                {
                    return Err(OfflineReadError::Cache(CacheError::InvalidInput));
                }
                plan.terms_observation =
                    Some((chrono::Utc::now().timestamp(), ticket.request_revision()));
                plan.terms = result.data;
                plan.stage = Stage::Weeks;
            }
            Stage::Weeks => {
                let ticket = plan.begin_query(CacheQuery::ScheduleWeeks {
                    term: plan.term.clone(),
                })?;
                let result = crate::features::schedule::get_weeks_for_import(
                    self.runtime_for(plan.resolution.mode),
                    &plan.term,
                )
                .await;
                let result = self
                    .finish_routed(plan.resolution, result)
                    .map_err(OfflineReadError::Read)?;
                self.validate_schedule_import(plan)?;
                plan.weeks = CachedSemesterSchedule::normalized_weeks(&plan.term, result.data)
                    .map_err(OfflineReadError::Cache)?;
                plan.weeks_observation =
                    Some((chrono::Utc::now().timestamp(), ticket.request_revision()));
                plan.stage = Stage::Week;
            }
            Stage::Week => {
                let week = plan
                    .weeks
                    .get(plan.schedules.len())
                    .ok_or(OfflineReadError::Cache(CacheError::InvalidInput))?
                    .serial_number;
                let ticket = plan.begin_query(CacheQuery::ScheduleWeek {
                    term: plan.term.clone(),
                    week,
                })?;
                let result = crate::features::schedule::get_week_for_import(
                    self.runtime_for(plan.resolution.mode),
                    &plan.term,
                    week,
                )
                .await;
                let result = self
                    .finish_routed(plan.resolution, result)
                    .map_err(OfflineReadError::Read)?;
                self.validate_schedule_import(plan)?;
                plan.schedules.insert(week, result.data);
                plan.observations.insert(
                    week,
                    (chrono::Utc::now().timestamp(), ticket.request_revision()),
                );
                if plan.schedules.len() == plan.weeks.len() {
                    return Ok(Routed {
                        data: plan.finish()?,
                        resolution: plan.resolution,
                    });
                }
            }
        }
        Ok(Routed {
            data: plan.batch(None),
            resolution: plan.resolution,
        })
    }
}

impl OfflineCache {
    /// 读取完整导入的精确周次或日期投影，不获取网络客户端锁。
    ///
    /// # Errors
    /// 账号已退出、范围无效或缓存损坏时返回稳定缓存错误。
    pub fn read_imported_schedule(
        &self,
        route: super::ConnectionMode,
        query: CacheQuery,
    ) -> super::CacheResult<Option<super::CacheRecord>> {
        self.repository(|repo| {
            repo.read_imported_schedule(route, query, chrono::Utc::now().timestamp())
        })
    }
}
#[cfg(test)]
mod tests;
