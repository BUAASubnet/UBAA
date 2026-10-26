use super::{CacheError, CachePayload, CacheQuery, CacheResult, CacheScope, OfflineCache};
use crate::cache::{CacheCompleteness, CachedGradeScoreBaseline, OfflineRepository};
use crate::domain::ConnectionMode;

fn scope(route: ConnectionMode, term: &str) -> CacheScope {
    CacheScope {
        route,
        query: CacheQuery::GradeScoreBaseline { term: term.into() },
    }
}

fn read(
    repository: &mut OfflineRepository,
    scope: &CacheScope,
    now: i64,
) -> CacheResult<Option<CachedGradeScoreBaseline>> {
    repository
        .read(scope, now)?
        .map(|record| {
            if let CachePayload::GradeScoreBaseline(value) = record.payload
                && record.completeness == CacheCompleteness::Complete
                && value.valid()
            {
                return Ok(value);
            }
            Err(CacheError::Corrupt)
        })
        .transpose()
}

fn save(
    repository: &mut OfflineRepository,
    route: ConnectionMode,
    value: CachedGradeScoreBaseline,
    now: i64,
) -> CacheResult<()> {
    let ticket = repository.begin_read(scope(route, &value.term_code))?;
    repository
        .publish(
            &ticket,
            CachePayload::GradeScoreBaseline(value),
            now,
            CacheCompleteness::Complete,
        )
        .map(|_| ())
}

impl OfflineCache {
    /// 精确学期的派生基线，不获取网络锁或恢复认证。
    ///
    /// # Errors
    /// 仓库、账号生命周期、范围或密文无效时保留缓存错误分类。
    pub fn read_grade_score_baseline(
        &self,
        route: ConnectionMode,
        term: &str,
    ) -> CacheResult<Option<CachedGradeScoreBaseline>> {
        self.repository(|repository| {
            read(
                repository,
                &scope(route, term),
                chrono::Utc::now().timestamp(),
            )
        })
    }

    /// 同一本地锁内读取原基线并保存本次完整观察，返回比较所需的原值。
    /// 旧文件基线只在该学期尚无加密记录时迁入；宿主仅在成功后移除旧文件范围。
    ///
    /// # Errors
    /// 空集合、非法字段、保存失败或退出/清理栅栏均返回错误，不制造首次观察。
    pub fn update_grade_score_baseline(
        &self,
        route: ConnectionMode,
        latest: CachedGradeScoreBaseline,
        legacy: Option<CachedGradeScoreBaseline>,
    ) -> CacheResult<Option<CachedGradeScoreBaseline>> {
        if !latest.valid() || legacy.as_ref().is_some_and(|value| !value.valid()) {
            return Err(CacheError::InvalidInput);
        }
        self.repository(|repository| {
            let now = chrono::Utc::now().timestamp();
            if let Some(value) = legacy {
                let old_scope = scope(route, &value.term_code);
                if read(repository, &old_scope, now)?.is_none() {
                    save(repository, route, value, now)?;
                }
            }
            let previous = read(repository, &scope(route, &latest.term_code), now)?;
            save(repository, route, latest, now)?;
            Ok(previous)
        })
    }
}
