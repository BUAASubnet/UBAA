use super::{
    BridgeConnectionMode, BridgeError, BridgeOfflineCache, BridgeWeek, BridgeWeeklySchedule,
    cache_error, core, local_task, map_weekly_schedule, map_weeks,
};

#[derive(Clone, Debug)]
pub struct BridgeCourseHubWeek {
    pub week: BridgeWeek,
    pub schedule: BridgeWeeklySchedule,
}

impl BridgeOfflineCache {
    /// 只投影完整导入的各周，未导入返回空集合。
    ///
    /// # Errors
    /// 账号不可用、范围无效或导入记录损坏时返回本地错误。
    pub async fn course_hub_schedule(
        &self,
        route: BridgeConnectionMode,
        term: String,
    ) -> Result<Vec<BridgeCourseHubWeek>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            let read = |query| {
                cache
                    .read_imported_schedule(route.into(), query)
                    .map_err(cache_error)
            };
            let Some(record) = read(core::CacheQuery::ScheduleWeeks { term: term.clone() })? else {
                return Ok(vec![]);
            };
            let corrupt = || cache_error(core::CacheError::Corrupt);
            let core::CachePayload::Weeks(weeks) = record.payload else {
                return Err(corrupt());
            };
            let mut result = Vec::new();
            for week in map_weeks(weeks) {
                let Some(record) = read(core::CacheQuery::ScheduleWeek {
                    term: term.clone(),
                    week: week.serial_number,
                })?
                else {
                    return Ok(vec![]);
                };
                let core::CachePayload::Week(schedule) = record.payload else {
                    return Err(corrupt());
                };
                result.push(BridgeCourseHubWeek {
                    week,
                    schedule: map_weekly_schedule(schedule),
                });
            }
            Ok(result)
        })
        .await
    }

    /// # Errors
    /// 账号或本地仓库不可用时返回缓存错误。
    pub async fn read_judge_overrides(&self, term: String) -> Result<Vec<String>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || cache.read_judge_overrides(&term).map_err(cache_error)).await
    }

    /// # Errors
    /// 账号或范围无效、保存失败时返回缓存错误。
    pub async fn set_judge_link(
        &self,
        term: String,
        course_id: String,
        linked: bool,
    ) -> Result<(), BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .set_judge_link(&term, &course_id, linked)
                .map_err(cache_error)
        })
        .await
    }
}
