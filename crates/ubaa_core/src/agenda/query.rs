//! 自建事项和学校投影在同一个日程事务中叠加本地覆盖。
use super::{AgendaStore, expand_agenda};
use crate::{
    cache::{CacheError, CacheResult},
    domain::agenda::{AgendaEntry, AgendaEntryItem, SchoolAgendaItem},
};
use chrono::NaiveDate;
impl AgendaStore {
    pub(crate) fn merge_school(
        &self,
        from: NaiveDate,
        to: NaiveDate,
        school: Vec<SchoolAgendaItem>,
        include_hidden: bool,
    ) -> CacheResult<Vec<AgendaEntry>> {
        if from >= to || (to - from).num_days() > 3660 {
            return Err(CacheError::InvalidInput);
        }
        self.access(true, false, |data| {
            merge_entries(data, from, to, school, include_hidden)
        })
    }
}
pub(super) fn merge_entries(
    data: &super::store::AgendaData,
    from: NaiveDate,
    to: NaiveDate,
    school: Vec<SchoolAgendaItem>,
    include_hidden: bool,
) -> CacheResult<Vec<AgendaEntry>> {
    let mut entries = Vec::new();
    for item in data.items.values() {
        for occurrence in expand_agenda(item, from, to)? {
            entries.push(AgendaEntry {
                completed: occurrence.completed_at.is_some(),
                hidden: false,
                note: occurrence.content.notes.clone(),
                item: AgendaEntryItem::Local(occurrence),
            });
        }
        if entries.len() > usize::from(u16::MAX) {
            return Err(CacheError::Capacity);
        }
    }
    for item in school {
        if !item.timing.intersects(from, to) {
            continue;
        }
        let key = super::operations::overlay_key(&item.key)?;
        let overlay = data.overlays.get(&key).filter(|o| o.deleted_at.is_none());
        let upstream = item.upstream_status.completed();
        let hidden = overlay.is_some_and(|o| o.hidden);
        if hidden && !include_hidden {
            continue;
        }
        entries.push(AgendaEntry {
            completed: overlay.map_or(upstream, |o| o.effective_completed(upstream)),
            hidden,
            note: overlay.and_then(|o| o.note.clone()),
            item: AgendaEntryItem::School(item),
        });
    }
    if entries.len() > usize::from(u16::MAX) {
        return Err(CacheError::Capacity);
    }
    // 学校相同时间保持来源/响应顺序；自建事项沿原查询的 UUID 顺序。
    entries.sort_by_key(AgendaEntry::sort_time);
    Ok(entries)
}
