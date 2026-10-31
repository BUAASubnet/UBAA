//! 独立账号库，不参与只读缓存容量、退出清理或格式重建。
use super::recurrence::validate_item;
use crate::cache::{CacheError, CacheKey, CacheResult, crypto::Crypto, files};
use crate::domain::agenda::{AgendaItem, SchoolAgendaOverlay};
use rusqlite::{Connection, OpenFlags, OptionalExtension, TransactionBehavior};
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeMap,
    path::Path,
    sync::{Arc, Mutex},
    time::Duration,
};
use uuid::Uuid;

#[derive(Default, Serialize, Deserialize)]
pub(super) struct AgendaData {
    pub items: BTreeMap<Uuid, AgendaItem>,
    pub overlays: BTreeMap<String, SchoolAgendaOverlay>,
    active: bool,
}
struct Repository {
    db: Connection,
    crypto: Crypto,
    aad: Vec<u8>,
}
/// 与学校客户端独立的账号句柄。宿主须按已核实账号打开，退出时 deactivate，重新登录后 activate。
#[derive(Clone)]
pub struct AgendaStore {
    repository: Arc<Mutex<Repository>>,
}
impl AgendaStore {
    /// 打开按随机账号别名隔离的私有密文库，首次打开激活，后续保留退出状态。
    ///
    /// # Errors
    /// 路径、密钥、版本或 `SQLite` 失败均返回稳定本地错误，不删除原库。
    pub fn open(root: &Path, account: &str, key: CacheKey) -> CacheResult<Self> {
        let path = files::scoped_database_path(root, account, "agenda")?;
        let mut db = Connection::open_with_flags(
            path,
            OpenFlags::SQLITE_OPEN_READ_WRITE
                | OpenFlags::SQLITE_OPEN_NO_MUTEX
                | OpenFlags::SQLITE_OPEN_NOFOLLOW,
        )?;
        db.busy_timeout(Duration::from_millis(250))?;
        let version: u32 = db.pragma_query_value(None, "user_version", |r| r.get(0))?;
        if version != 0 && version != 1 {
            return Err(CacheError::UnsupportedVersion);
        }
        db.execute_batch("PRAGMA journal_mode=DELETE; PRAGMA synchronous=FULL; PRAGMA secure_delete=ON; PRAGMA temp_store=MEMORY; PRAGMA trusted_schema=OFF;")?;
        let crypto = Crypto::new(key);
        let aad = [
            b"ubaa.agenda.v1\0".as_slice(),
            account.to_ascii_lowercase().as_bytes(),
        ]
        .concat();
        let tx = db.transaction_with_behavior(TransactionBehavior::Immediate)?;
        let version: u32 = tx.pragma_query_value(None, "user_version", |r| r.get(0))?;
        if version != 0 && version != 1 {
            return Err(CacheError::UnsupportedVersion);
        }
        tx.execute_batch("CREATE TABLE IF NOT EXISTS agenda_state(id INTEGER PRIMARY KEY CHECK(id=1), body BLOB NOT NULL)")?;
        let body: Option<Vec<u8>> = tx
            .query_row("SELECT body FROM agenda_state WHERE id=1", [], |r| r.get(0))
            .optional()?;
        if let Some(body) = body {
            let _: AgendaData = crypto.open(&body, &aad)?;
        } else if version == 0 {
            let body = crypto.seal(
                &AgendaData {
                    active: true,
                    ..AgendaData::default()
                },
                &aad,
            )?;
            tx.execute("INSERT INTO agenda_state VALUES(1,?1)", [body])?;
        } else {
            return Err(CacheError::Corrupt);
        }
        tx.pragma_update(None, "user_version", 1)?;
        tx.commit()?;
        Ok(Self {
            repository: Arc::new(Mutex::new(Repository { db, crypto, aad })),
        })
    }
    pub(super) fn access<T>(
        &self,
        require_active: bool,
        write: bool,
        f: impl FnOnce(&mut AgendaData) -> CacheResult<T>,
    ) -> CacheResult<T> {
        let mut repository = self
            .repository
            .lock()
            .map_err(|_| CacheError::Unavailable)?;
        let Repository { db, crypto, aad } = &mut *repository;
        let tx = db.transaction_with_behavior(if write {
            TransactionBehavior::Immediate
        } else {
            TransactionBehavior::Deferred
        })?;
        let version: u32 = tx.pragma_query_value(None, "user_version", |r| r.get(0))?;
        if version != 1 {
            return Err(CacheError::UnsupportedVersion);
        }
        let body: Vec<u8> =
            tx.query_row("SELECT body FROM agenda_state WHERE id=1", [], |r| r.get(0))?;
        let mut data: AgendaData = crypto.open(&body, aad)?;
        if require_active && !data.active {
            return Err(CacheError::Inactive);
        }
        let result = f(&mut data)?;
        if write {
            let body = crypto.seal(&data, aad)?;
            if body.len() > 16 * 1024 * 1024 {
                return Err(CacheError::Capacity);
            }
            tx.execute("UPDATE agenda_state SET body=?1 WHERE id=1", [body])?;
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
            if data.items.contains_key(&item.id) {
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
            d.items.clear();
            d.overlays.clear();
            Ok(n)
        })
    }
    /// 关闭账号的日程读取与修改，数据和密钥保持原样。
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
