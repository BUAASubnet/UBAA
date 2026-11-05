//! 独立账号库，不参与只读缓存容量、退出清理或格式重建。
use super::recurrence::validate_item;
use crate::cache::{CacheError, CacheResult};
use crate::domain::agenda::{AgendaItem, SchoolAgendaOverlay};
use rusqlite::{Connection, TransactionBehavior};
use std::{
    collections::BTreeMap,
    path::Path,
    sync::{Arc, Mutex},
};
use uuid::Uuid;

#[derive(Clone, Default)]
pub(super) struct AgendaData {
    pub items: BTreeMap<Uuid, AgendaItem>,
    pub overlays: BTreeMap<String, SchoolAgendaOverlay>,
    pub(super) active: bool,
    pub(super) sync: super::sync::SyncState,
}
impl AgendaData {
    fn clear_local_rows(&mut self) -> CacheResult<()> {
        self.sync.advance_epoch()?;
        // 目录创建没有待发布正文，只有文件发布保留无正文的未决身份。
        self.sync.pending = self
            .sync
            .pending
            .take()
            .filter(|pending| pending.publication.is_some());
        if let Some(pending) = &mut self.sync.pending {
            pending.document = None;
        }
        self.sync.item_deletions.clear();
        self.sync.overlay_deletions.clear();
        self.items.clear();
        self.overlays.clear();
        Ok(())
    }
}
struct Repository {
    db: Connection,
}
/// 与学校客户端独立的账号句柄。宿主须按已核实账号打开，退出时 deactivate，重新登录后 activate。
#[derive(Clone)]
pub struct AgendaStore {
    repository: Arc<Mutex<Repository>>,
    account_alias: Arc<str>,
    guard: Option<crate::facade::SharedAccountGuard>,
}
impl AgendaStore {
    /// 打开按随机账号别名隔离的私有明文库，首次打开激活，后续保留退出状态。
    ///
    /// # Errors
    /// 路径、格式、版本或 `SQLite` 失败均返回稳定本地错误，不删除原库。
    pub fn open(root: &Path, account: &str) -> CacheResult<Self> {
        let account = account.to_ascii_lowercase();
        let db = super::sqlite::open(root, &account)?;
        Ok(Self {
            repository: Arc::new(Mutex::new(Repository { db })),
            account_alias: Arc::from(account),
            guard: None,
        })
    }
    /// 在固定共享身份的短提交边界内打开库。
    ///
    /// # Errors
    /// 原持久身份已撤销或存储不可用时返回稳定本地错误。
    pub fn open_shared(
        root: &Path,
        account: &str,
        guard: crate::facade::SharedAccountGuard,
    ) -> CacheResult<Self> {
        let permit = guard.acquire().map_err(|_| CacheError::Superseded)?;
        let store = Self::open(root, account)?;
        drop(permit);
        Ok(store.with_shared_account(guard))
    }
    /// 返回绑定固定共享代次的新句柄，原句柄保持原归属。
    #[must_use]
    pub fn with_shared_account(mut self, guard: crate::facade::SharedAccountGuard) -> Self {
        self.guard = Some(guard);
        self
    }
    pub(crate) fn account_alias(&self) -> &str {
        &self.account_alias
    }
    pub(crate) fn matches_sync_guard(
        &self,
        guard: Option<&crate::facade::SharedAccountGuard>,
    ) -> bool {
        self.guard
            .as_ref()
            .zip(guard)
            .is_some_and(|(left, right)| left.same_scope(right))
    }
    pub(super) fn access<T>(
        &self,
        require_active: bool,
        write: bool,
        f: impl FnOnce(&mut AgendaData) -> CacheResult<T>,
    ) -> CacheResult<T> {
        let _permit = self
            .guard
            .as_ref()
            .map(crate::facade::SharedAccountGuard::acquire)
            .transpose()
            .map_err(|_| CacheError::Superseded)?;
        let mut repository = self
            .repository
            .lock()
            .map_err(|_| CacheError::Unavailable)?;
        let Repository { db } = &mut *repository;
        let tx = db.transaction_with_behavior(if write {
            TransactionBehavior::Immediate
        } else {
            TransactionBehavior::Deferred
        })?;
        let mut data = super::sqlite::load(&tx, &self.account_alias)?;
        let before = write.then(|| data.clone());
        if require_active && !data.active {
            return Err(CacheError::Inactive);
        }
        let result = f(&mut data)?;
        if let Some(before) = before {
            super::sync::track_local_changes(&before, &mut data)?;
            super::sqlite::save(&tx, &before, &data)?;
        }
        tx.commit()?;
        Ok(result)
    }
    /// 保存新事项；已有 UUID（包括删除标记）不可覆盖。
    ///
    /// # Errors
    /// 非法事项、重复 UUID、已退出或存储失败时不修改原数据。
    pub fn create(&self, mut item: AgendaItem) -> CacheResult<()> {
        item.locally_modified = true;
        validate_item(&item)?;
        self.access(true, true, |data| {
            if data.items.contains_key(&item.id) || data.sync.item_deletions.contains_key(&item.id)
            {
                return Err(CacheError::InvalidInput);
            }
            data.items.insert(item.id, item);
            Ok(())
        })
    }
    /// 返回原始事项，包括删除标记，供后续同步使用。
    ///
    /// # Errors
    /// 已退出或本地存储不可用时返回稳定错误。
    pub fn get(&self, id: Uuid) -> CacheResult<Option<AgendaItem>> {
        self.access(true, false, |data| Ok(data.items.get(&id).cloned()))
    }
    /// 先查询待同步记录数，删除标记也计入。
    ///
    /// # Errors
    /// 已退出或本地存储不可用时返回稳定错误。
    pub fn unsynced_count(&self) -> CacheResult<usize> {
        self.access(true, false, |d| {
            Ok(d.items.values().filter(|v| v.locally_modified).count()
                + d.overlays.values().filter(|v| v.locally_modified).count())
        })
    }
    /// 显式清除当前账号的全部本机日程，返回清除前的未同步记录数。
    ///
    /// # Errors
    /// 已退出或事务失败时原数据保持不变。
    pub fn clear_local_data(&self) -> CacheResult<usize> {
        self.access(true, true, |d| {
            let n = d.items.values().filter(|v| v.locally_modified).count()
                + d.overlays.values().filter(|v| v.locally_modified).count();
            d.clear_local_rows()?;
            Ok(n)
        })
    }
    /// 在同一 `SQLite` 写事务中核对未同步数量并清除全部本机记录。
    ///
    /// # Errors
    /// 数量变化、账号失效或存储失败时保留全部记录。
    pub fn clear_local_data_if_unsynced(&self, expected: usize) -> CacheResult<usize> {
        self.access(true, true, |data| {
            let count = data.items.values().filter(|v| v.locally_modified).count()
                + data
                    .overlays
                    .values()
                    .filter(|v| v.locally_modified)
                    .count();
            if count != expected {
                return Err(CacheError::InvalidInput);
            }
            data.clear_local_rows()?;
            Ok(count)
        })
    }
    /// 关闭账号的日程读取与修改，数据保持原样。
    ///
    /// # Errors
    /// 事务失败时不能宣称已退出。
    pub fn deactivate(&self) -> CacheResult<()> {
        self.access(false, true, |d| {
            d.active = false;
            Ok(())
        })
    }
    /// 宿主核实同一账号重新登录后显式开放，不发起网络请求。
    ///
    /// # Errors
    /// 本地存储不可用时返回稳定错误。
    pub fn activate(&self) -> CacheResult<()> {
        self.access(false, true, |d| {
            d.active = true;
            Ok(())
        })
    }
}
