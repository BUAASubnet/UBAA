//! 学业只读缓存复用既有协议，持久范围不由宿主序列化任意正文。
use super::{
    CacheError, CachePayload, CacheQuery, CacheScope, ConnectionMode, OfflineCache,
    OfflineReadError, OfflineRefresh, ReadonlyFeature, UbaaClient,
};

/// 仅允许已核对的学业和空教室操作；筛选投影不改变学校查询范围。
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum AcademicQuery {
    Terms,
    Weeks { term: String },
    Week { term: String, week: i32 },
    Exams { term: String },
    Grades { term: String },
    Classrooms { campus: i32, date: String },
}
impl AcademicQuery {
    /// 返回精确缓存键；既不推断当前学期，也不在重读时改写日期。
    #[must_use]
    pub fn cache_query(&self) -> CacheQuery {
        match self {
            Self::Terms => CacheQuery::ScheduleTerms,
            Self::Weeks { term } => CacheQuery::ScheduleWeeks { term: term.clone() },
            Self::Week { term, week } => CacheQuery::ScheduleWeek {
                term: term.clone(),
                week: *week,
            },
            Self::Exams { term } => CacheQuery::Exams { term: term.clone() },
            Self::Grades { term } => CacheQuery::Grades { term: term.clone() },
            Self::Classrooms { campus, date } => CacheQuery::Classrooms {
                campus: *campus,
                date: date.clone(),
            },
        }
    }
    const fn feature(&self) -> ReadonlyFeature {
        match self {
            Self::Terms | Self::Weeks { .. } | Self::Week { .. } => ReadonlyFeature::Schedule,
            Self::Exams { .. } => ReadonlyFeature::Exam,
            Self::Grades { .. } => ReadonlyFeature::Grades,
            Self::Classrooms { .. } => ReadonlyFeature::Classroom,
        }
    }
}
impl UbaaClient {
    /// 核对账号后沿原读取实现取得完整结果，成功才替换精确范围。
    ///
    /// # Errors
    /// 参数、身份、认证或学校读取失败保持原边界；退出/替代票据不可降级。
    pub async fn refresh_cached_academic(
        &mut self,
        cache: &OfflineCache,
        query: AcademicQuery,
    ) -> Result<OfflineRefresh<CachePayload>, OfflineReadError> {
        let cache_query = query.cache_query();
        CacheScope {
            route: ConnectionMode::Direct,
            query: cache_query.clone(),
        }
        .validate()
        .map_err(OfflineReadError::Cache)?;
        let authenticated = self
            .recover_required_session(query.feature())
            .await
            .map_err(OfflineReadError::Read)?;
        let resolution = authenticated.resolution;
        if !cache.matches(&authenticated.data.user) {
            return Err(OfflineReadError::IdentityMismatch {
                resolution,
                cache_error: cache.deactivate().err(),
            });
        }
        let scope = CacheScope {
            route: resolution.mode,
            query: cache_query,
        };
        let (ticket, mut save_error) = match cache.begin(scope.clone()) {
            Ok(ticket) => (Some(ticket), None),
            Err(error @ (CacheError::Inactive | CacheError::Superseded)) => {
                return Err(OfflineReadError::Cache(error));
            }
            Err(error) => (None, Some(error)),
        };
        let runtime = self.runtime_for(resolution.mode);
        let result = match query {
            AcademicQuery::Terms => crate::features::schedule::get_terms(runtime)
                .await
                .map(CachePayload::Terms),
            AcademicQuery::Weeks { term } => crate::features::schedule::get_weeks(runtime, &term)
                .await
                .map(CachePayload::Weeks),
            AcademicQuery::Week { term, week } => {
                crate::features::schedule::get_week(runtime, &term, week)
                    .await
                    .map(CachePayload::Week)
            }
            AcademicQuery::Exams { term } => crate::features::schedule::get_exam(runtime, &term)
                .await
                .map(CachePayload::Exams),
            AcademicQuery::Grades { term } => crate::features::grades::get_grades(runtime, &term)
                .await
                .map(CachePayload::Grades),
            AcademicQuery::Classrooms { campus, date } => {
                crate::features::classroom::search(runtime, campus, &date)
                    .await
                    .map(CachePayload::Classrooms)
            }
        };
        let fetched_at = chrono::Utc::now().timestamp();
        match self.finish_routed(resolution, result) {
            Ok(result) => {
                if let Some(ticket) = &ticket {
                    save_error = cache.publish(ticket, result.data.clone(), fetched_at).err();
                    if save_error.is_some() {
                        cache.failure(ticket, fetched_at);
                    }
                    if let Some(error @ (CacheError::Inactive | CacheError::Superseded)) =
                        save_error
                    {
                        return Err(OfflineReadError::Cache(error));
                    }
                }
                Ok(OfflineRefresh {
                    data: result.data,
                    resolution,
                    scope,
                    fetched_at,
                    save_error,
                })
            }
            Err(error) => {
                if let Some(ticket) = &ticket {
                    cache.failure(ticket, fetched_at);
                }
                Err(OfflineReadError::Read(error))
            }
        }
    }
}

impl OfflineCache {
    /// 精确读取已保存学业范围，不校验网络会话。
    ///
    /// # Errors
    /// 参数无效、账号关闭或本地记录损坏时返回稳定缓存错误。
    pub fn read_academic(
        &self,
        route: ConnectionMode,
        query: &AcademicQuery,
    ) -> super::CacheResult<Option<super::CacheRecord>> {
        self.read(
            &CacheScope {
                route,
                query: query.cache_query(),
            },
            chrono::Utc::now().timestamp(),
        )
    }
}
