//! 学业只读缓存复用既有协议，持久范围不由宿主序列化任意正文。
use super::{
    CachePayload, CacheQuery, CacheScope, ConnectionMode, OfflineCache, OfflineReadError,
    OfflineRefresh, ReadonlyFeature, UbaaClient,
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
        let refresh = self
            .prepare_cached_refresh(cache, query.feature(), query.cache_query())
            .await?;
        let resolution = refresh.resolution;
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
        let data = refresh.read_result(self.finish_routed(resolution, result))?;
        refresh
            .finish(data, true, Clone::clone)
            .map(|value| value.result)
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
        let now = chrono::Utc::now().timestamp();
        let current = self.read(
            &CacheScope {
                route,
                query: query.cache_query(),
            },
            now,
        )?;
        let mut selected = if matches!(
            query,
            AcademicQuery::Terms | AcademicQuery::Week { .. } | AcademicQuery::Weeks { .. }
        ) {
            let imported = self
                .repository(|repo| repo.read_imported_schedule(route, query.cache_query(), now))?;
            match (current, imported) {
                (Some(current), Some(imported)) => Some(if imported.revision > current.revision {
                    imported
                } else {
                    current
                }),
                (current, imported) => current.or(imported),
            }
        } else {
            current
        };
        if let (AcademicQuery::Weeks { term }, Some(record)) = (query, &mut selected)
            && let CachePayload::Weeks(weeks) = &mut record.payload
        {
            super::CachedSemesterSchedule::project_week_dates(term, weeks, now)?;
        }
        Ok(selected)
    }
}
