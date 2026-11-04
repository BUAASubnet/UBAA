use super::{
    AgendaStore, expand_agenda,
    recurrence::{is_occurrence, parse_id, validate_item},
};
use crate::cache::{CacheError, CacheResult};
use crate::domain::agenda::{
    AgendaContent, AgendaEditScope, AgendaItem, AgendaOccurrence, AgendaTime, SchoolAgendaKey,
    SchoolAgendaOverlay,
};
use chrono::{Duration, NaiveDate};
use uuid::Uuid;

impl AgendaStore {
    /// 查询日期范围内展开的自建事项，含原始 RECURRENCE-ID、覆盖内容和完成状态。
    ///
    /// # Errors
    /// 范围非法、账号关闭、展开超限或存储故障时返回稳定本地错误。
    pub fn query(&self, from: NaiveDate, to: NaiveDate) -> CacheResult<Vec<AgendaOccurrence>> {
        if from >= to || (to - from).num_days() > 3660 {
            return Err(CacheError::InvalidInput);
        }
        self.access(true, false, |data| {
            let mut rows = Vec::new();
            for item in data.items.values() {
                rows.extend(expand_agenda(item, from, to)?);
                if rows.len() > usize::from(u16::MAX) {
                    return Err(CacheError::Capacity);
                }
            }
            rows.sort_by_key(|r| (r.content.anchor(), r.item_id, r.recurrence_id.clone()));
            Ok(rows)
        })
    }
    /// 修改仅此次、此次及以后或全部。仅此次不修改系列规则；其余范围使用传入规则。
    /// 后半段产生新 UUID，返回该 UUID；同规则拆分保留剩余 COUNT。
    ///
    /// # Errors
    /// 目标不存在、发生时间无效、时间倒退、内容/规则非法或事务失败时整体回滚。
    pub fn edit(
        &self,
        id: Uuid,
        scope: AgendaEditScope,
        at: Option<AgendaTime>,
        content: AgendaContent,
        rrule: Option<String>,
        now: AgendaTime,
    ) -> CacheResult<Option<Uuid>> {
        self.edit_internal(id, scope, at, content, (rrule, None), now)
    }
    /// 原子修改事项与排除日期，单次修改保留系列规则和其他发生。
    ///
    /// # Errors
    /// 内容、重复规则、排除日期或存储无效时整体回滚。
    pub fn edit_draft(
        &self,
        id: Uuid,
        scope: AgendaEditScope,
        at: Option<AgendaTime>,
        content: AgendaContent,
        recurrence: (Option<String>, Vec<AgendaTime>),
        now: AgendaTime,
    ) -> CacheResult<Option<Uuid>> {
        self.edit_internal(
            id,
            scope,
            at,
            content,
            (recurrence.0, Some(recurrence.1)),
            now,
        )
    }
    fn edit_internal(
        &self,
        id: Uuid,
        scope: AgendaEditScope,
        at: Option<AgendaTime>,
        content: AgendaContent,
        recurrence: (Option<String>, Option<Vec<AgendaTime>>),
        now: AgendaTime,
    ) -> CacheResult<Option<Uuid>> {
        let (rrule, exdates) = recurrence;
        self.access(true, true, |data| {
            let item = data.items.get_mut(&id).ok_or(CacheError::InvalidInput)?;
            touch(item, now)?;
            let mut successor = match scope {
                AgendaEditScope::This => {
                    let key = occurrence_key(item, at)?;
                    if item.rrule.is_none() {
                        let old_anchor = item.content.anchor();
                        let new_anchor = content.anchor();
                        item.content = content;
                        item.rrule = rrule;
                        super::split::remap_exceptions(item, old_anchor, new_anchor)?;
                    } else {
                        if !content.valid() {
                            return Err(CacheError::InvalidInput);
                        }
                        item.overrides.insert(key, content);
                    }
                    None
                }
                AgendaEditScope::All => {
                    let anchor = content.anchor();
                    let old_anchor = item.content.anchor();
                    let mut replacement_rule = rrule;
                    if replacement_rule == item.rrule
                        && let (Some(raw), Some(old), Some(new)) =
                            (&mut replacement_rule, old_anchor, anchor)
                    {
                        *raw = super::split::shift_until(raw, new.datetime - old.datetime)?;
                    }
                    item.content = content;
                    item.rrule = replacement_rule;
                    super::split::remap_exceptions(item, old_anchor, anchor)?;
                    None
                }
                AgendaEditScope::ThisAndFuture => {
                    let at = at.ok_or(CacheError::InvalidInput)?;
                    occurrence_key(item, Some(at))?;
                    Some(super::split::split(item, at, content, rrule, now)?)
                }
            };
            if let Some(exdates) = exdates {
                match scope {
                    AgendaEditScope::This if item.rrule.is_some() => {}
                    AgendaEditScope::ThisAndFuture => {
                        if let Some(next) = &mut successor {
                            next.exdates = exdates.into_iter().collect();
                        }
                    }
                    _ => item.exdates = exdates.into_iter().collect(),
                }
            }
            validate_item(item)?;
            if let Some(next) = successor {
                validate_item(&next)?;
                let id = next.id;
                data.items.insert(id, next);
                Ok(Some(id))
            } else {
                Ok(None)
            }
        })
    }
    /// 删除仅此次（EXDATE）、此次及以后（UNTIL 截断）或全部（删除标记）。
    ///
    /// # Errors
    /// 目标或发生时间无效、时间倒退或存储失败时不修改原数据。
    pub fn delete(
        &self,
        id: Uuid,
        scope: AgendaEditScope,
        at: Option<AgendaTime>,
        now: AgendaTime,
    ) -> CacheResult<()> {
        self.access(true, true, |data| {
            let item = data.items.get_mut(&id).ok_or(CacheError::InvalidInput)?;
            touch(item, now)?;
            match scope {
                AgendaEditScope::All => item.deleted_at = Some(now),
                AgendaEditScope::This => {
                    let key = occurrence_key(item, at)?;
                    if item.rrule.is_some() {
                        item.exdates.insert(at.ok_or(CacheError::InvalidInput)?);
                        item.overrides.remove(&key);
                        item.completions.remove(&key);
                    } else {
                        item.deleted_at = Some(now);
                    }
                }
                AgendaEditScope::ThisAndFuture => {
                    let at = at.ok_or(CacheError::InvalidInput)?;
                    occurrence_key(item, Some(at))?;
                    super::split::truncate(item, at, now)?;
                }
            }
            validate_item(item)
        })
    }
    /// 按原始发生时间完成或取消完成；无日期待办传入 None。
    ///
    /// # Errors
    /// 已删除或排除的发生、非法时间、账号关闭或存储失败时返回错误。
    pub fn complete(
        &self,
        id: Uuid,
        at: Option<AgendaTime>,
        completed: bool,
        now: AgendaTime,
    ) -> CacheResult<()> {
        self.access(true, true, |data| {
            let item = data.items.get_mut(&id).ok_or(CacheError::InvalidInput)?;
            touch(item, now)?;
            let key = occurrence_key(item, at)?;
            item.completions.insert(key, completed.then_some(now));
            validate_item(item)
        })
    }
    /// 设置完整本地覆盖；未完成标记优先于学校提交状态，清除旧删除标记。
    ///
    /// # Errors
    /// 键、时间或内容非法、时间倒退或本机事务失败时保留原记录。
    pub fn set_overlay(
        &self,
        mut overlay: SchoolAgendaOverlay,
        now: AgendaTime,
    ) -> CacheResult<()> {
        let key = overlay_key(&overlay.key)?;
        if !now.valid()
            || overlay.completed_at.is_some_and(|t| !t.valid())
            || overlay.note.as_ref().is_some_and(|s| s.len() > 65536)
        {
            return Err(CacheError::InvalidInput);
        }
        self.access(true, true, |d| {
            if d.overlays.get(&key).is_some_and(|v| now < v.updated_at) {
                return Err(CacheError::InvalidInput);
            }
            overlay.updated_at = now;
            overlay.deleted_at = None;
            overlay.locally_modified = true;
            d.overlays.insert(key, overlay);
            Ok(())
        })
    }
    /// `查询覆盖层，包括用于同步的删除标记。effective_completed` 根据删除状态回落上游。
    ///
    /// # Errors
    /// 键无效、账号关闭或存储失败时返回稳定本地错误。
    pub fn overlay(&self, key: &SchoolAgendaKey) -> CacheResult<Option<SchoolAgendaOverlay>> {
        let key = overlay_key(key)?;
        self.access(true, false, |d| Ok(d.overlays.get(&key).cloned()))
    }
    /// 清除本地覆盖并写入删除标记；原来没有覆盖时也生成标记供后续合并。
    ///
    /// # Errors
    /// 键无效、时间倒退、账号关闭或事务失败时返回稳定错误。
    pub fn clear_overlay(&self, key: &SchoolAgendaKey, now: AgendaTime) -> CacheResult<()> {
        let index = overlay_key(key)?;
        if !now.valid() {
            return Err(CacheError::InvalidInput);
        }
        self.access(true, true, |d| {
            if d.overlays.get(&index).is_some_and(|v| now < v.updated_at) {
                return Err(CacheError::InvalidInput);
            }
            d.overlays.insert(
                index,
                SchoolAgendaOverlay {
                    key: key.clone(),
                    completed_at: None,
                    completion_override: false,
                    hidden: false,
                    note: None,
                    updated_at: now,
                    deleted_at: Some(now),
                    locally_modified: true,
                },
            );
            Ok(())
        })
    }
    /// 只清理已同步且严格超过 180 天的事项及覆盖层删除标记。
    ///
    /// # Errors
    /// 时间无效、账号关闭或事务失败时保留原数据。
    pub fn purge_tombstones(&self, now: AgendaTime) -> CacheResult<usize> {
        if !now.valid() {
            return Err(CacheError::InvalidInput);
        }
        let cutoff = now
            .datetime
            .checked_sub_signed(Duration::days(180))
            .ok_or(CacheError::InvalidInput)?;
        self.access(true, true, |d| {
            let n = d.items.len() + d.overlays.len();
            d.items.retain(|_, v| {
                v.locally_modified || v.deleted_at.is_none_or(|t| t.datetime >= cutoff)
            });
            d.overlays.retain(|_, v| {
                v.locally_modified || v.deleted_at.is_none_or(|t| t.datetime >= cutoff)
            });
            Ok(n - d.items.len() - d.overlays.len())
        })
    }
}
pub(super) fn overlay_key(key: &SchoolAgendaKey) -> CacheResult<String> {
    if [&key.source, &key.upstream_id]
        .iter()
        .any(|s| s.trim().is_empty() || s.len() > 4096)
    {
        return Err(CacheError::InvalidInput);
    }
    // 编码元组避免 source/upstream_id 中的分隔符碰撞。
    serde_json::to_string(&(key.source.as_str(), key.upstream_id.as_str()))
        .map_err(|_| CacheError::InvalidInput)
}
fn touch(item: &mut AgendaItem, now: AgendaTime) -> CacheResult<()> {
    if !now.valid() || now < item.updated_at || item.deleted_at.is_some() {
        return Err(CacheError::InvalidInput);
    }
    item.updated_at = now;
    item.locally_modified = true;
    Ok(())
}
fn occurrence_key(item: &AgendaItem, at: Option<AgendaTime>) -> CacheResult<String> {
    if item.content.anchor().is_none() && at.is_none() {
        return Ok("undated".into());
    }
    let at = at.ok_or(CacheError::InvalidInput)?;
    if !is_occurrence(item, at)? || item.exdates.contains(&at) {
        return Err(CacheError::InvalidInput);
    }
    let key = at.recurrence_id();
    parse_id(&key)?;
    Ok(key)
}
