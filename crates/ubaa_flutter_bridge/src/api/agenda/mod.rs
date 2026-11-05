//! 本机日程独立于网络客户端、业务缓存密钥和学校操作资格。
pub(crate) mod convert;
mod evidence;
pub mod export;
pub mod home;
mod home_input;
pub mod models;
mod projection;
pub mod school;
pub mod sync;
#[cfg(test)]
mod tests;
use crate::api::offline::BridgeOfflineCache;
use convert::{date, error, id, invalid, time};
use models::{
    BridgeAgendaContent, BridgeAgendaDraft, BridgeAgendaEditScope, BridgeAgendaError,
    BridgeAgendaItem, BridgeAgendaOverlay, BridgeAgendaOverlayDraft, BridgeAgendaTime,
    BridgeSchoolAgendaKey, BridgeTeachingWeekInput, BridgeTeachingWeekPattern,
    BridgeTeachingWeekRule,
};
use school::{BridgeAgendaQuery, BridgeAgendaQueryResult};
use std::path::Path;
use ubaa_core::facade as core;

pub struct BridgeAgendaStore {
    pub(crate) store: core::AgendaStore,
}
async fn task<T: Send + 'static>(
    f: impl FnOnce() -> Result<T, BridgeAgendaError> + Send + 'static,
) -> Result<T, BridgeAgendaError> {
    tokio::task::spawn_blocking(f)
        .await
        .map_err(|_| error(core::CacheError::Unavailable))?
}
impl BridgeAgendaStore {
    /// 按已核实别名打开独立日程文件。
    ///
    /// # Errors
    /// 输入非法、账号已关闭或本地存储不可用时返回稳定日程错误。
    pub async fn open(config_dir: String, account_id: String) -> Result<Self, BridgeAgendaError> {
        task(move || {
            Ok(Self {
                store: core::AgendaStore::open(Path::new(&config_dir), &account_id)
                    .map_err(error)?,
            })
        })
        .await
    }
    /// 重新开放当前账号的日程访问。
    ///
    /// # Errors
    /// 输入非法、账号已关闭或本地存储不可用时返回稳定日程错误。
    pub async fn activate(&self) -> Result<(), BridgeAgendaError> {
        let store = self.store.clone();
        task(move || store.activate().map_err(error)).await
    }
    /// 关闭当前账号的日程访问，保留文件。
    ///
    /// # Errors
    /// 输入非法、账号已关闭或本地存储不可用时返回稳定日程错误。
    pub async fn deactivate(&self) -> Result<(), BridgeAgendaError> {
        let store = self.store.clone();
        task(move || store.deactivate().map_err(error)).await
    }
    /// 创建并返回新事项，失败时不产生记录。
    ///
    /// # Errors
    /// 输入非法、账号已关闭或本地存储不可用时返回稳定日程错误。
    pub async fn create(
        &self,
        draft: BridgeAgendaDraft,
        now: BridgeAgendaTime,
    ) -> Result<BridgeAgendaItem, BridgeAgendaError> {
        let store = self.store.clone();
        task(move || {
            let mut item = core::AgendaItem::new(draft.content.try_into()?, now.try_into()?);
            item.rrule = draft.rrule;
            item.exdates = draft
                .exdates
                .into_iter()
                .map(TryInto::try_into)
                .collect::<Result<_, _>>()?;
            store.create(item.clone()).map_err(error)?;
            Ok(item.into())
        })
        .await
    }
    /// 读取原始事项，包含删除标记。
    ///
    /// # Errors
    /// 输入非法、账号已关闭或本地存储不可用时返回稳定日程错误。
    pub async fn get(
        &self,
        item_id: String,
    ) -> Result<Option<BridgeAgendaItem>, BridgeAgendaError> {
        let store = self.store.clone();
        task(move || {
            store
                .get(id(&item_id)?)
                .map(|v| v.map(Into::into))
                .map_err(error)
        })
        .await
    }
    /// 按原始发生时间修改指定范围，返回后续系列的新 UUID。
    ///
    /// # Errors
    /// 输入非法、账号已关闭或本地存储不可用时返回稳定日程错误。
    pub async fn edit(
        &self,
        item_id: String,
        scope: BridgeAgendaEditScope,
        at: Option<BridgeAgendaTime>,
        content: BridgeAgendaContent,
        rrule: Option<String>,
        now: BridgeAgendaTime,
    ) -> Result<Option<String>, BridgeAgendaError> {
        let store = self.store.clone();
        task(move || {
            store
                .edit(
                    id(&item_id)?,
                    scope.into(),
                    time(at)?,
                    content.try_into()?,
                    rrule,
                    now.try_into()?,
                )
                .map(|v| v.map(|id| id.to_string()))
                .map_err(error)
        })
        .await
    }
    /// 原子保存内容、重复规则与假期排除日期。
    ///
    /// # Errors
    /// 输入、账号或存储无效时保留原事项。
    pub async fn edit_draft(
        &self,
        item_id: String,
        scope: BridgeAgendaEditScope,
        at: Option<BridgeAgendaTime>,
        draft: BridgeAgendaDraft,
        now: BridgeAgendaTime,
    ) -> Result<Option<String>, BridgeAgendaError> {
        let store = self.store.clone();
        task(move || {
            let exclusions = draft
                .exdates
                .into_iter()
                .map(TryInto::try_into)
                .collect::<Result<Vec<_>, _>>()?;
            store
                .edit_draft(
                    id(&item_id)?,
                    scope.into(),
                    time(at)?,
                    draft.content.try_into()?,
                    (draft.rrule, exclusions),
                    now.try_into()?,
                )
                .map(|value| value.map(|id| id.to_string()))
                .map_err(error)
        })
        .await
    }
    /// 按指定范围排除发生或写入删除标记。
    ///
    /// # Errors
    /// 输入非法、账号已关闭或本地存储不可用时返回稳定日程错误。
    pub async fn delete(
        &self,
        item_id: String,
        scope: BridgeAgendaEditScope,
        at: Option<BridgeAgendaTime>,
        now: BridgeAgendaTime,
    ) -> Result<(), BridgeAgendaError> {
        let store = self.store.clone();
        task(move || {
            store
                .delete(id(&item_id)?, scope.into(), time(at)?, now.try_into()?)
                .map_err(error)
        })
        .await
    }
    /// 完成或重新挂起原始发生。
    ///
    /// # Errors
    /// 输入非法、账号已关闭或本地存储不可用时返回稳定日程错误。
    pub async fn complete(
        &self,
        item_id: String,
        at: Option<BridgeAgendaTime>,
        completed: bool,
        now: BridgeAgendaTime,
    ) -> Result<(), BridgeAgendaError> {
        let store = self.store.clone();
        task(move || {
            store
                .complete(id(&item_id)?, time(at)?, completed, now.try_into()?)
                .map_err(error)
        })
        .await
    }
    /// 设置学校事项的本地覆盖，不改变学校数据。
    ///
    /// # Errors
    /// 输入非法、账号已关闭或本地存储不可用时返回稳定日程错误。
    pub async fn set_overlay(
        &self,
        overlay: BridgeAgendaOverlayDraft,
        now: BridgeAgendaTime,
    ) -> Result<(), BridgeAgendaError> {
        let store = self.store.clone();
        task(move || {
            let now = now.try_into()?;
            store
                .set_overlay(
                    core::SchoolAgendaOverlay {
                        key: overlay.key.into(),
                        completed_at: time(overlay.completed_at)?,
                        completion_override: overlay.completion_override,
                        hidden: overlay.hidden,
                        note: overlay.note,
                        updated_at: now,
                        deleted_at: None,
                        locally_modified: true,
                    },
                    now,
                )
                .map_err(error)
        })
        .await
    }
    /// 读取覆盖和删除标记。
    ///
    /// # Errors
    /// 输入非法、账号已关闭或本地存储不可用时返回稳定日程错误。
    pub async fn overlay(
        &self,
        key: BridgeSchoolAgendaKey,
    ) -> Result<Option<BridgeAgendaOverlay>, BridgeAgendaError> {
        let store = self.store.clone();
        task(move || {
            store
                .overlay(&key.into())
                .map(|v| v.map(Into::into))
                .map_err(error)
        })
        .await
    }
    /// 清除覆盖并保留待同步删除标记。
    ///
    /// # Errors
    /// 输入非法、账号已关闭或本地存储不可用时返回稳定日程错误。
    pub async fn clear_overlay(
        &self,
        key: BridgeSchoolAgendaKey,
        now: BridgeAgendaTime,
    ) -> Result<(), BridgeAgendaError> {
        let store = self.store.clone();
        task(move || {
            store
                .clear_overlay(&key.into(), now.try_into()?)
                .map_err(error)
        })
        .await
    }
    /// 查询未同步记录数，包括删除标记。
    ///
    /// # Errors
    /// 输入非法、账号已关闭或本地存储不可用时返回稳定日程错误。
    pub async fn unsynced_count(&self) -> Result<u32, BridgeAgendaError> {
        let store = self.store.clone();
        task(move || {
            u32::try_from(store.unsynced_count().map_err(error)?)
                .map_err(|_| error(core::CacheError::Capacity))
        })
        .await
    }
    /// 显式清除本账号日程，返回未同步记录数。
    ///
    /// # Errors
    /// 输入非法、账号已关闭或本地存储不可用时返回稳定日程错误。
    pub async fn clear_local_data(&self) -> Result<u32, BridgeAgendaError> {
        let store = self.store.clone();
        task(move || {
            u32::try_from(store.clear_local_data().map_err(error)?)
                .map_err(|_| error(core::CacheError::Capacity))
        })
        .await
    }
    /// 学校缓存未打开时查询本地日程和学校来源缺失状态。
    ///
    /// # Errors
    /// 输入非法、账号已关闭或本地存储不可用时返回稳定日程错误。
    pub async fn query_local(
        &self,
        query: BridgeAgendaQuery,
    ) -> Result<BridgeAgendaQueryResult, BridgeAgendaError> {
        let store = self.store.clone();
        task(move || {
            let q = query.try_into()?;
            Ok(projection::result(
                store.query_local_agenda(&q).map_err(error)?,
                q.now,
                None,
            ))
        })
        .await
    }
    /// 合并同账号、明确路线的学校缓存，缓存故障时返回本地事项。
    ///
    /// # Errors
    /// 输入非法、账号已关闭或本地存储不可用时返回稳定日程错误。
    pub async fn query_with_cache(
        &self,
        cache: &BridgeOfflineCache,
        query: BridgeAgendaQuery,
    ) -> Result<BridgeAgendaQueryResult, BridgeAgendaError> {
        let store = self.store.clone();
        let cache = cache.cache.clone();
        task(move || {
            let q: core::AgendaQuery = query.try_into()?;
            if !cache.matches_agenda_account(&store) {
                return Err(invalid());
            }
            match cache.query_agenda(&store, &q) {
                Ok(value) => Ok(projection::result(value, q.now, None)),
                // 输入/身份错误不可以当成缓存缺失而吞掉。
                Err(core::CacheError::InvalidInput) if !q.term.is_empty() => Err(invalid()),
                Err(e) => Ok(projection::result(
                    store.query_local_agenda(&q).map_err(error)?,
                    q.now,
                    Some(
                        crate::api::offline::cache_error(e)
                            .cache_failure
                            .unwrap_or(crate::api::offline::BridgeCacheFailure::Unavailable),
                    ),
                )),
            }
        })
        .await
    }
}
/// 复用 Core 的教学周规则生成校园时区重复规则。
///
/// # Errors
/// 输入非法、账号已关闭或本地存储不可用时返回稳定日程错误。
pub async fn agenda_teaching_week_rule(
    input: BridgeTeachingWeekInput,
) -> Result<BridgeTeachingWeekRule, BridgeAgendaError> {
    task(move || {
        let weekday = [
            chrono::Weekday::Mon,
            chrono::Weekday::Tue,
            chrono::Weekday::Wed,
            chrono::Weekday::Thu,
            chrono::Weekday::Fri,
            chrono::Weekday::Sat,
            chrono::Weekday::Sun,
        ]
        .get(
            usize::try_from(input.weekday.checked_sub(1).ok_or_else(invalid)?)
                .map_err(|_| invalid())?,
        )
        .copied()
        .ok_or_else(invalid)?;
        let time = chrono::NaiveTime::from_hms_opt(input.hour, input.minute, input.second)
            .ok_or_else(invalid)?;
        let skips = input
            .skips
            .iter()
            .map(|v| date(v))
            .collect::<Result<Vec<_>, _>>()?;
        let pattern = match input.pattern {
            BridgeTeachingWeekPattern::Every => core::TeachingWeekPattern::Every,
            BridgeTeachingWeekPattern::Odd => core::TeachingWeekPattern::Odd,
            BridgeTeachingWeekPattern::Even => core::TeachingWeekPattern::Even,
        };
        let v = core::teaching_week_rule(
            date(&input.monday)?,
            input.first,
            input.last,
            pattern,
            weekday,
            time,
            &skips,
        )
        .map_err(error)?;
        Ok(BridgeTeachingWeekRule {
            start: v.start.into(),
            rrule: v.rrule,
            exdates: v.exdates.into_iter().map(Into::into).collect(),
        })
    })
    .await
}
impl TryFrom<BridgeAgendaQuery> for core::AgendaQuery {
    type Error = BridgeAgendaError;
    fn try_from(v: BridgeAgendaQuery) -> Result<Self, Self::Error> {
        Ok(Self {
            route: v.route.into(),
            term: v.term,
            from: date(&v.from)?,
            to: date(&v.to)?,
            now: v.now.try_into()?,
            include_hidden: v.include_hidden,
            ygdk: core::YgdkAgendaSettings {
                enabled: v.ygdk_enabled,
                week_done: v.ygdk_week_done,
                term_done: v.ygdk_term_done,
            },
        })
    }
}
