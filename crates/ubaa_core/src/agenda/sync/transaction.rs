use super::{
    AgendaSyncDocument, AgendaSyncItem, AgendaSyncOverlay,
    pending::{PendingOperation, PublicationReceipt, StoredPending, SyncAttempt},
    state::{Stamp, SyncState},
};
use crate::{
    agenda::{AgendaStore, operations::overlay_key, store::AgendaData},
    cache::{CacheError, CacheResult},
    domain::agenda::AgendaTime,
};
use uuid::Uuid;

/// 绑定本机账号、设备和生命周期的待核对快照，不能反序列化或跨账号使用。
#[derive(Clone, Debug)]
pub struct AgendaSyncSnapshot {
    pub(super) account_alias: String,
    pub(super) device_id: Uuid,
    pub(super) epoch: u64,
    pub(super) document: AgendaSyncDocument,
    pub(super) attempt: Option<Uuid>,
    pub(super) publication: Option<u64>,
}
pub(super) struct RestoredAttempt {
    pub snapshot: AgendaSyncSnapshot,
    pub operation: PendingOperation,
    body_retained: bool,
}
impl RestoredAttempt {
    pub fn retains_body(&self) -> bool {
        self.body_retained
    }

    /// 只有保留正文且收到明确登记回执的文件，才可进入读回确认。
    pub fn confirmable_object(&self) -> Option<&str> {
        match &self.operation {
            PendingOperation::Publication {
                receipt: PublicationReceipt::Registered(object),
                ..
            } if self.body_retained => Some(object),
            _ => None,
        }
    }
}
impl AgendaSyncSnapshot {
    #[must_use]
    pub fn document(&self) -> &AgendaSyncDocument {
        &self.document
    }
}
impl AgendaStore {
    /// 当前账号是否已明确许可 GUI 自动同步。
    ///
    /// # Errors
    /// 账号停用或存储失败时拒绝读取。
    pub fn sync_enabled(&self) -> CacheResult<bool> {
        self.access(true, false, |data| Ok(data.sync.enabled))
    }
    /// 在用户确认后保存当前账号的自动同步许可。
    ///
    /// # Errors
    /// 账号停用、代次失效或事务失败时不修改许可。
    pub fn enable_sync(&self) -> CacheResult<()> {
        self.access(true, true, |data| {
            data.sync.enabled = true;
            Ok(())
        })
    }
    pub(super) fn restore_sync_attempt(&self) -> CacheResult<Option<RestoredAttempt>> {
        self.access(true, false, |data| {
            Ok(data.sync.pending.as_ref().map(|pending| RestoredAttempt {
                snapshot: AgendaSyncSnapshot {
                    account_alias: self.account_alias().into(),
                    device_id: data.sync.device_id,
                    epoch: data.sync.epoch,
                    document: pending.document().cloned().unwrap_or_default(),
                    attempt: Some(pending.id()),
                    publication: pending.operation().publication(),
                },
                operation: pending.operation().clone(),
                body_retained: pending.document().is_some(),
            }))
        })
    }
    pub(super) fn begin_sync_attempt(
        &self,
        sent: &mut AgendaSyncSnapshot,
        operation: SyncAttempt,
    ) -> CacheResult<Uuid> {
        let id = Uuid::new_v4();
        let (publication, document) = self.access(true, true, |data| {
            self.check_sync_scope(sent, data)?;
            if data.sync.pending.is_some() {
                return Err(CacheError::Superseded);
            }
            // 正文与发布序号在同一 IMMEDIATE 事务中确定，包含其他进程已提交的修改。
            let (document, operation) = match operation {
                SyncAttempt::Directory(target) => (
                    sent.document.clone(),
                    PendingOperation::Directory {
                        target: Some(target),
                    },
                ),
                SyncAttempt::Publication => {
                    let document = document(data)?;
                    let sequence = data.sync.next_publication;
                    data.sync.next_publication = sequence
                        .checked_add(1)
                        .filter(|value| i64::try_from(*value).is_ok())
                        .ok_or(CacheError::Capacity)?;
                    (
                        document,
                        PendingOperation::Publication {
                            sequence,
                            receipt: PublicationReceipt::Unknown(None),
                        },
                    )
                }
            };
            let publication = operation.publication();
            data.sync.pending = Some(StoredPending::restore(
                id,
                Some(document.clone()),
                operation,
            ));
            Ok((publication, document))
        })?;
        sent.document = document;
        sent.attempt = Some(id);
        sent.publication = publication;
        Ok(id)
    }
    pub(super) fn record_sync_receipt(
        &self,
        sent: &AgendaSyncSnapshot,
        receipt: PublicationReceipt,
    ) -> CacheResult<()> {
        self.access(true, true, |data| {
            self.check_sync_scope(sent, data)?;
            let pending = data
                .sync
                .pending
                .as_mut()
                .filter(|pending| Some(pending.id()) == sent.attempt)
                .ok_or(CacheError::Superseded)?;
            pending.record_receipt(receipt)
        })
    }
    pub(super) fn clear_sync_attempt(&self, sent: &AgendaSyncSnapshot) -> CacheResult<()> {
        self.access(true, true, |data| {
            self.check_sync_scope(sent, data)?;
            Self::require_sync_attempt(sent, data)?;
            data.sync.pending = None;
            Ok(())
        })
    }
    pub(super) fn check_sync_attempt(&self, sent: &AgendaSyncSnapshot) -> CacheResult<()> {
        self.access(true, false, |data| {
            self.check_sync_scope(sent, data)?;
            Self::require_sync_attempt(sent, data)
        })
    }
    pub(super) fn has_sync_attempt(&self, scope: &AgendaSyncSnapshot) -> CacheResult<bool> {
        self.access(true, false, |data| {
            self.check_sync_scope(scope, data)?;
            Ok(data.sync.pending.is_some())
        })
    }
    fn require_sync_attempt(sent: &AgendaSyncSnapshot, data: &AgendaData) -> CacheResult<()> {
        if data.sync.pending.as_ref().is_some_and(|pending| {
            Some(pending.id()) == sent.attempt
                && pending.operation().publication() == sent.publication
                && pending.document() == Some(&sent.document)
        }) {
            Ok(())
        } else {
            Err(CacheError::Superseded)
        }
    }
    /// 取得当前账号完整同步快照，含删除标记。
    ///
    /// # Errors
    /// 账号停用或存储不可用时失败。
    pub fn sync_snapshot(&self) -> CacheResult<AgendaSyncSnapshot> {
        self.access(true, false, |data| {
            Ok(AgendaSyncSnapshot {
                account_alias: self.account_alias().into(),
                device_id: data.sync.device_id,
                epoch: data.sync.epoch,
                document: document(data)?,
                attempt: None,
                publication: None,
            })
        })
    }
    /// 在原快照生命周期内原子合并已明确读取的远端文档。
    ///
    /// # Errors
    /// 旧作用域、内容冲突或存储失败时保持本机数据。
    pub fn merge_sync(
        &self,
        scope: &AgendaSyncSnapshot,
        remote: &AgendaSyncDocument,
    ) -> CacheResult<usize> {
        self.merge_sync_inner(scope, remote, None)
    }
    pub(super) fn merge_sync_at(
        &self,
        scope: &AgendaSyncSnapshot,
        remote: &AgendaSyncDocument,
        now: AgendaTime,
    ) -> CacheResult<usize> {
        self.merge_sync_inner(scope, remote, Some(tombstone_cutoff(now)?))
    }
    fn merge_sync_inner(
        &self,
        scope: &AgendaSyncSnapshot,
        remote: &AgendaSyncDocument,
        cutoff: Option<chrono::DateTime<chrono::FixedOffset>>,
    ) -> CacheResult<usize> {
        let retired = |dirty: bool, deleted: Option<AgendaTime>| {
            !dirty
                && cutoff
                    .zip(deleted)
                    .is_some_and(|(cutoff, deleted)| deleted.datetime < cutoff)
        };
        let remote = remote.normalized()?;
        self.access(true, true, |data| {
            self.check_sync_scope(scope, data)?;
            let merged = document(data)?.merge(&remote)?;
            let remote_items: std::collections::BTreeMap<_, _> =
                remote.items.iter().map(|v| (v.item.id, v)).collect();
            let remote_overlays: std::collections::BTreeMap<_, _> = remote
                .overlays
                .iter()
                .map(|v| Ok((overlay_key(&v.overlay.key)?, v)))
                .collect::<CacheResult<_>>()?;
            let mut changed = super::deletions::merge_into(data, &merged, &remote)?;
            for record in merged.items {
                let key = record.item.id;
                if data.sync.item_deletions.get(&key).is_some_and(|deleted| {
                    let version = (record.item.updated_at, record.device_id, record.sequence);
                    deleted.version() > version
                        || deleted.version() == version && record.item.deleted_at.is_none()
                }) {
                    continue;
                }
                let remote = remote_items.get(&key).copied();
                let known = remote == Some(&record)
                    || remote.is_none()
                        && data
                            .items
                            .get(&key)
                            .is_some_and(|old| retired(old.locally_modified, old.deleted_at));
                let stamp = Stamp {
                    device_id: record.device_id,
                    sequence: record.sequence,
                };
                imported_sequence(&mut data.sync, stamp)?;
                let mut item = record.item;
                item.locally_modified = !known
                    || data.sync.pending.is_some()
                        && data.sync.items.get(&key) == Some(&stamp)
                        && data.items.get(&key).is_some_and(|old| {
                            old.locally_modified && super::state::same_item(old, &item)
                        });
                changed += usize::from(
                    data.items.get(&key) != Some(&item)
                        || data.sync.items.get(&key) != Some(&stamp),
                );
                data.items.insert(key, item);
                data.sync.items.insert(key, stamp);
            }
            for record in merged.overlays {
                let key = overlay_key(&record.overlay.key)?;
                if data
                    .sync
                    .overlay_deletions
                    .get(&key)
                    .is_some_and(|deleted| {
                        let version =
                            (record.overlay.updated_at, record.device_id, record.sequence);
                        deleted.version() > version
                            || deleted.version() == version && record.overlay.deleted_at.is_none()
                    })
                {
                    continue;
                }
                let remote = remote_overlays.get(&key).copied();
                let known = remote == Some(&record)
                    || remote.is_none()
                        && data
                            .overlays
                            .get(&key)
                            .is_some_and(|old| retired(old.locally_modified, old.deleted_at));
                let stamp = Stamp {
                    device_id: record.device_id,
                    sequence: record.sequence,
                };
                imported_sequence(&mut data.sync, stamp)?;
                let mut overlay = record.overlay;
                overlay.locally_modified = !known
                    || data.sync.pending.is_some()
                        && data.sync.overlays.get(&key) == Some(&stamp)
                        && data.overlays.get(&key).is_some_and(|old| {
                            old.locally_modified && super::state::same_overlay(old, &overlay)
                        });
                changed += usize::from(
                    data.overlays.get(&key) != Some(&overlay)
                        || data.sync.overlays.get(&key) != Some(&stamp),
                );
                data.overlays.insert(key.clone(), overlay);
                data.sync.overlays.insert(key, stamp);
            }
            if let Some(cutoff) = cutoff {
                changed += crate::agenda::operations::purge_before(data, cutoff);
            }
            Ok(changed)
        })
    }
    /// 读回文档匹配已发送快照时，仅确认此后未修改的记录。
    ///
    /// # Errors
    /// 旧作用域、读回不匹配或存储失败时保留待同步状态。
    pub fn confirm_sync(
        &self,
        sent: &AgendaSyncSnapshot,
        read_back: &AgendaSyncDocument,
    ) -> CacheResult<usize> {
        let read_back = read_back.normalized()?;
        if sent.document != read_back {
            return Err(CacheError::Superseded);
        }
        self.access(true, true, |data| {
            self.check_sync_scope(sent, data)?;
            if sent.attempt.is_some() {
                Self::require_sync_attempt(sent, data)?;
            }
            let mut confirmed = super::deletions::confirm(data, &sent.document)?;
            for record in &sent.document.items {
                let stamp = Stamp {
                    device_id: record.device_id,
                    sequence: record.sequence,
                };
                if data.sync.items.get(&record.item.id) == Some(&stamp)
                    && let Some(value) = data.items.get_mut(&record.item.id)
                    && super::state::same_item(value, &record.item)
                {
                    confirmed += usize::from(value.locally_modified);
                    value.locally_modified = false;
                }
            }
            for record in &sent.document.overlays {
                let key = overlay_key(&record.overlay.key)?;
                let stamp = Stamp {
                    device_id: record.device_id,
                    sequence: record.sequence,
                };
                if data.sync.overlays.get(&key) == Some(&stamp)
                    && let Some(value) = data.overlays.get_mut(&key)
                    && super::state::same_overlay(value, &record.overlay)
                {
                    confirmed += usize::from(value.locally_modified);
                    value.locally_modified = false;
                }
            }
            if sent.attempt.is_some() {
                data.sync.pending = None;
            }
            Ok(confirmed)
        })
    }
    pub(super) fn sync_pending_count(&self, scope: &AgendaSyncSnapshot) -> CacheResult<usize> {
        self.access(true, false, |data| {
            self.check_sync_scope(scope, data)?;
            Ok(data.items.values().filter(|v| v.locally_modified).count()
                + data
                    .overlays
                    .values()
                    .filter(|v| v.locally_modified)
                    .count())
        })
    }
    fn check_sync_scope(&self, scope: &AgendaSyncSnapshot, data: &AgendaData) -> CacheResult<()> {
        if scope.account_alias != self.account_alias()
            || scope.device_id != data.sync.device_id
            || scope.epoch != data.sync.epoch
        {
            return Err(CacheError::Superseded);
        }
        Ok(())
    }
}
fn tombstone_cutoff(now: AgendaTime) -> CacheResult<chrono::DateTime<chrono::FixedOffset>> {
    if !now.valid() {
        return Err(CacheError::InvalidInput);
    }
    now.datetime
        .checked_sub_signed(chrono::Duration::days(180))
        .ok_or(CacheError::InvalidInput)
}
pub(super) fn imported_sequence(state: &mut SyncState, stamp: Stamp) -> CacheResult<()> {
    if stamp.device_id == state.device_id && stamp.sequence >= state.next_sequence {
        state.next_sequence = stamp
            .sequence
            .checked_add(1)
            .filter(|v| i64::try_from(*v).is_ok())
            .ok_or(CacheError::Capacity)?;
    }
    Ok(())
}
fn document(data: &AgendaData) -> CacheResult<AgendaSyncDocument> {
    let mut result = AgendaSyncDocument::default();
    for (key, value) in &data.items {
        if value.deleted_at.is_some() {
            continue;
        }
        let stamp = data.sync.items.get(key).ok_or(CacheError::Corrupt)?;
        let mut item = value.clone();
        item.locally_modified = false;
        result.items.push(AgendaSyncItem {
            device_id: stamp.device_id,
            sequence: stamp.sequence,
            item,
        });
    }
    for (key, value) in &data.overlays {
        if value.deleted_at.is_some() {
            continue;
        }
        let stamp = data.sync.overlays.get(key).ok_or(CacheError::Corrupt)?;
        let mut overlay = value.clone();
        overlay.locally_modified = false;
        result.overlays.push(AgendaSyncOverlay {
            device_id: stamp.device_id,
            sequence: stamp.sequence,
            overlay,
        });
    }
    super::deletions::append(data, &mut result)?;
    result.normalized()
}
