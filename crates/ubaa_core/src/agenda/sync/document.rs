use super::deletions::{self, AgendaSyncItemDeletion, AgendaSyncOverlayDeletion};
use crate::{
    agenda::{operations::overlay_key, recurrence::validate_item},
    cache::{CacheError, CacheResult},
    domain::agenda::{AgendaItem, SchoolAgendaOverlay},
};
use serde::{Deserialize, Serialize};
use std::{cmp::Ordering, collections::BTreeMap, io::Write};
use uuid::Uuid;
pub(super) const DOCUMENT_LIMIT: usize = 32 * 1024 * 1024;

/// 单次事项版本。序号在同一设备持久递增，区分同秒编辑。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct AgendaSyncItem {
    pub device_id: Uuid,
    pub sequence: u64,
    #[serde(with = "super::values::ItemValue")]
    pub item: AgendaItem,
}
/// 学校事项的本地覆盖版本，不包含学校原始数据。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct AgendaSyncOverlay {
    pub device_id: Uuid,
    pub sequence: u64,
    #[serde(with = "super::values::OverlayValue")]
    pub overlay: SchoolAgendaOverlay,
}
/// 不可变快照中的记录与紧凑删除摘要，独立于本机数据库格式。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct AgendaSyncDocument {
    pub schema: u32,
    pub items: Vec<AgendaSyncItem>,
    pub overlays: Vec<AgendaSyncOverlay>,
    pub item_deletions: Vec<AgendaSyncItemDeletion>,
    pub overlay_deletions: Vec<AgendaSyncOverlayDeletion>,
}
impl Default for AgendaSyncDocument {
    fn default() -> Self {
        Self {
            schema: 2,
            items: vec![],
            overlays: vec![],
            item_deletions: vec![],
            overlay_deletions: vec![],
        }
    }
}
impl AgendaSyncDocument {
    /// 逐记录合并，完整版本相同但内容不一致时拒绝整份文档。
    ///
    /// # Errors
    /// 文档、记录或版本冲突时不产生部分结果。
    pub fn merge(&self, other: &Self) -> CacheResult<Self> {
        let left = self.normalized()?;
        let right = other.normalized()?;
        let value = Self {
            schema: 2,
            items: merge_records(
                left.items,
                right.items,
                |v| Ok(v.item.id),
                |v| (v.item.updated_at, v.device_id, v.sequence),
            )?,
            overlays: merge_records(
                left.overlays,
                right.overlays,
                |v| overlay_key(&v.overlay.key),
                |v| (v.overlay.updated_at, v.device_id, v.sequence),
            )?,
            item_deletions: merge_records(
                left.item_deletions,
                right.item_deletions,
                |v| Ok(v.id),
                AgendaSyncItemDeletion::version,
            )?,
            overlay_deletions: merge_records(
                left.overlay_deletions,
                right.overlay_deletions,
                |v| overlay_key(&v.key),
                AgendaSyncOverlayDeletion::version,
            )?,
        }
        .normalized()?;
        value.encode()?;
        Ok(value)
    }
    /// 解析并验证同步正文。
    ///
    /// # Errors
    /// 格式、版本、内容或容量不符合约定时失败。
    pub fn decode(bytes: &[u8]) -> CacheResult<Self> {
        if bytes.len() > DOCUMENT_LIMIT {
            return Err(CacheError::Capacity);
        }
        let value: Self = serde_json::from_slice(bytes).map_err(|_| CacheError::Corrupt)?;
        value.normalized()
    }
    /// 生成有界的 UTF-8 JSON 正文。
    ///
    /// # Errors
    /// 文档不合法或超过正文预算时失败。
    pub fn encode(&self) -> CacheResult<Vec<u8>> {
        let value = self.normalized()?;
        encode_value(&value)
    }
    pub(super) fn normalized(&self) -> CacheResult<Self> {
        if self.schema != 2 {
            return Err(CacheError::UnsupportedVersion);
        }
        let mut value = self.clone();
        value.items.sort_by_key(|v| v.item.id);
        for record in &mut value.items {
            valid_version(record.device_id, record.sequence)?;
            record.item.locally_modified = false;
            validate_item(&record.item).map_err(|_| CacheError::Corrupt)?;
            if record.item.deleted_at.is_some() {
                return Err(CacheError::Corrupt);
            }
        }
        if value
            .items
            .windows(2)
            .any(|pair| pair[0].item.id == pair[1].item.id)
        {
            return Err(CacheError::Corrupt);
        }
        let mut overlays = BTreeMap::new();
        for mut record in value.overlays {
            valid_version(record.device_id, record.sequence)?;
            record.overlay.locally_modified = false;
            let key = overlay_key(&record.overlay.key).map_err(|_| CacheError::Corrupt)?;
            if record.overlay.deleted_at.is_some()
                || !crate::agenda::sqlite::valid_overlay(&record.overlay)
                || overlays.insert(key, record).is_some()
            {
                return Err(CacheError::Corrupt);
            }
        }
        value.overlays = overlays.into_values().collect();
        deletions::normalize(&mut value)?;
        Ok(value)
    }
}
pub(super) fn encode_value(value: &impl Serialize) -> CacheResult<Vec<u8>> {
    let mut writer = DocumentWriter { bytes: Vec::new() };
    serde_json::to_writer(&mut writer, value).map_err(|_| CacheError::Capacity)?;
    Ok(writer.bytes)
}
pub(super) fn valid_version(device_id: Uuid, sequence: u64) -> CacheResult<()> {
    if device_id.is_nil() || sequence == 0 || sequence > i64::MAX as u64 {
        return Err(CacheError::Corrupt);
    }
    Ok(())
}
fn merge_records<K: Ord, V: Eq, S: Ord>(
    left: Vec<V>,
    right: Vec<V>,
    key: impl Fn(&V) -> CacheResult<K>,
    version: impl Fn(&V) -> S,
) -> CacheResult<Vec<V>> {
    let mut values = BTreeMap::new();
    for record in left.into_iter().chain(right) {
        let identity = key(&record)?;
        if let Some(previous) = values.get(&identity) {
            match version(&record).cmp(&version(previous)) {
                Ordering::Equal if previous != &record => return Err(CacheError::Corrupt),
                Ordering::Less | Ordering::Equal => continue,
                Ordering::Greater => {}
            }
        }
        values.insert(identity, record);
    }
    Ok(values.into_values().collect())
}
struct DocumentWriter {
    bytes: Vec<u8>,
}
impl Write for DocumentWriter {
    fn write(&mut self, data: &[u8]) -> std::io::Result<usize> {
        if data.len() > DOCUMENT_LIMIT.saturating_sub(self.bytes.len()) {
            return Err(std::io::Error::other("同步正文超出预算"));
        }
        self.bytes.extend_from_slice(data);
        Ok(data.len())
    }
    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}
