//! `SQLite` 短事务与持久代次；不持有或等待学校网络客户端。
use super::{
    CACHE_SCHEMA_VERSION, CacheCompleteness, CacheError, CacheKey, CacheLimits, CachePayload,
    CachePublication, CacheReadTicket, CacheRecord, CacheResult, CacheScope, crypto::Crypto, files,
};
use rusqlite::{Connection, OpenFlags, OptionalExtension, TransactionBehavior, params};
use serde::{Deserialize, Serialize};
use std::{
    path::{Path, PathBuf},
    time::Duration,
};

#[derive(Serialize, Deserialize)]
struct Control {
    epoch: u64,
    revision: i64,
    active: bool,
}

/// 每个随机账号别名对应一个私有数据库；调用方串行使用实例，多个实例由事务协调。
pub struct OfflineRepository {
    pub(super) db: Connection,
    crypto: Crypto,
    account: String,
    path: PathBuf,
    limits: CacheLimits,
}

impl OfflineRepository {
    /// 打开独立缓存；错误密钥、未知版本和不安全路径均不降级明文。
    ///
    /// # Errors
    /// 私有路径、数据库、密钥校验或版本不可用时返回稳定缓存错误。
    pub fn open(
        root: &Path,
        account: &str,
        key: CacheKey,
        limits: CacheLimits,
    ) -> CacheResult<Self> {
        if limits.soft_bytes == 0
            || limits.soft_bytes > limits.hard_bytes
            || limits.hard_bytes > 100 * 1024 * 1024
        {
            return Err(CacheError::InvalidInput);
        }
        let path = files::database_path(root, account)?;
        let mut db = Connection::open_with_flags(
            &path,
            OpenFlags::SQLITE_OPEN_READ_WRITE
                | OpenFlags::SQLITE_OPEN_NO_MUTEX
                | OpenFlags::SQLITE_OPEN_NOFOLLOW,
        )
        .map_err(CacheError::from)?;
        db.busy_timeout(Duration::from_millis(250))
            .map_err(CacheError::from)?;
        let version: u32 = db
            .pragma_query_value(None, "user_version", |r| r.get(0))
            .map_err(CacheError::from)?;
        if version != 0 && version != CACHE_SCHEMA_VERSION {
            return Err(CacheError::UnsupportedVersion);
        }
        db.execute_batch("PRAGMA journal_mode=DELETE; PRAGMA synchronous=FULL; PRAGMA secure_delete=ON; PRAGMA temp_store=MEMORY; PRAGMA trusted_schema=OFF;").map_err(CacheError::from)?;
        db.pragma_update(
            None,
            "max_page_count",
            i64::try_from(limits.hard_bytes / 4096 + 32).map_err(|_| CacheError::Capacity)?,
        )
        .map_err(CacheError::from)?;
        let crypto = Crypto::new(key);
        let account = account.to_ascii_lowercase();
        let tx = db
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(CacheError::from)?;
        tx.execute_batch("CREATE TABLE IF NOT EXISTS control(id INTEGER PRIMARY KEY CHECK(id=1), body BLOB NOT NULL);
            CREATE TABLE IF NOT EXISTS entries(key BLOB PRIMARY KEY, body BLOB NOT NULL, accessed INTEGER NOT NULL, priority INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS requests(key BLOB PRIMARY KEY, revision INTEGER NOT NULL);").map_err(CacheError::from)?;
        let existing: Option<Vec<u8>> = tx
            .query_row("SELECT body FROM control WHERE id=1", [], |r| r.get(0))
            .optional()
            .map_err(CacheError::from)?;
        if let Some(body) = existing {
            let _: Control = crypto.open(&body, account.as_bytes())?;
        } else {
            if version != 0 {
                return Err(CacheError::Corrupt);
            }
            let body = crypto.seal(
                &Control {
                    epoch: 0,
                    revision: 0,
                    active: true,
                },
                account.as_bytes(),
            )?;
            tx.execute("INSERT INTO control VALUES(1,?1)", [body])
                .map_err(CacheError::from)?;
        }
        tx.pragma_update(None, "user_version", CACHE_SCHEMA_VERSION)
            .map_err(CacheError::from)?;
        tx.commit().map_err(CacheError::from)?;
        Ok(Self {
            db,
            crypto,
            account,
            path,
            limits,
        })
    }

    /// 返回文件位置供本地容量管理；禁止将路径写入诊断。
    #[must_use]
    pub fn path(&self) -> &Path {
        &self.path
    }

    /// 为一次精确范围的在线读取分配持久修订；它不授予学校写资格。
    ///
    /// # Errors
    /// 账号已退出、查询非法或本地事务失败时返回错误。
    pub fn begin_read(&mut self, scope: CacheScope) -> CacheResult<CacheReadTicket> {
        scope.validate()?;
        let key = self.crypto.index(&(&self.account, &scope))?;
        let tx = self
            .db
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(CacheError::from)?;
        let mut control = load_control(&tx, &self.crypto, &self.account)?;
        require_active(&control)?;
        control.revision = control
            .revision
            .checked_add(1)
            .ok_or(CacheError::Capacity)?;
        save_control(&tx, &self.crypto, &self.account, &control)?;
        tx.execute("INSERT INTO requests VALUES(?1,?2) ON CONFLICT(key) DO UPDATE SET revision=excluded.revision", params![key, control.revision]).map_err(CacheError::from)?;
        // 崩溃遗留的请求不无限增长；被回收的旧 ticket 会校验失败。
        tx.execute(
            "DELETE FROM requests WHERE revision < ?1",
            [control.revision.saturating_sub(4096)],
        )
        .map_err(CacheError::from)?;
        tx.commit().map_err(CacheError::from)?;
        Ok(CacheReadTicket {
            account: self.account.clone(),
            scope,
            epoch: control.epoch,
            revision: control.revision,
        })
    }

    /// 只读本地内容；单条损坏隔离该范围，其余范围保持可读。
    ///
    /// # Errors
    /// 账号已退出、查询非法、单条损坏或存储故障时返回错误。
    pub fn read(&mut self, scope: &CacheScope, now: i64) -> CacheResult<Option<CacheRecord>> {
        scope.validate()?;
        let key = self.crypto.index(&(&self.account, scope))?;
        let tx = self
            .db
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(CacheError::from)?;
        require_active(&load_control(&tx, &self.crypto, &self.account)?)?;
        let Some(body) = load_body(&tx, &key)? else {
            return Ok(None);
        };
        let record = self
            .crypto
            .open::<CacheRecord>(&body, &key)
            .and_then(|record| {
                if record.scope == *scope && record.payload.matches(&scope.query) {
                    Ok(record)
                } else {
                    Err(CacheError::Corrupt)
                }
            });
        if record.is_err() {
            tx.execute("DELETE FROM entries WHERE key=?1", [&key])
                .map_err(CacheError::from)?;
        } else {
            tx.execute(
                "UPDATE entries SET accessed=?1 WHERE key=?2",
                params![now, key],
            )
            .map_err(CacheError::from)?;
        }
        tx.commit().map_err(CacheError::from)?;
        record.map(Some)
    }

    /// 发布已校验的领域内容；较旧修订和退出前的任务永远不能落盘。
    ///
    /// # Errors
    /// 载荷不匹配、账号/任务失效、容量超限或存储失败时原事务回滚。
    pub fn publish(
        &mut self,
        ticket: &CacheReadTicket,
        payload: CachePayload,
        now: i64,
        completeness: CacheCompleteness,
    ) -> CacheResult<CachePublication> {
        if !payload.matches(&ticket.scope.query) {
            return Err(CacheError::InvalidInput);
        }
        let key = self.crypto.index(&(&self.account, &ticket.scope))?;
        let tx = self
            .db
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(CacheError::from)?;
        validate_ticket(&tx, &self.crypto, &self.account, ticket, &key)?;
        let previous = load_body(&tx, &key)?
            .and_then(|body| self.crypto.open::<CacheRecord>(&body, &key).ok());
        let preserve = completeness == CacheCompleteness::Partial && previous.is_some();
        let record = if preserve {
            let mut previous = previous.ok_or(CacheError::Corrupt)?;
            previous.last_attempt_at = now;
            previous.last_attempt_succeeded = false;
            previous
        } else {
            CacheRecord {
                scope: ticket.scope.clone(),
                payload,
                fetched_at: now,
                last_attempt_at: now,
                last_verified_at: now,
                last_attempt_succeeded: completeness == CacheCompleteness::Complete,
                revision: ticket.revision,
                completeness,
            }
        };
        let body = self.crypto.seal(&record, &key)?;
        if u64::try_from(body.len()).map_err(|_| CacheError::Capacity)? > self.limits.hard_bytes {
            return Err(CacheError::Capacity);
        }
        tx.execute("INSERT INTO entries VALUES(?1,?2,?3,?4) ON CONFLICT(key) DO UPDATE SET body=excluded.body, accessed=excluded.accessed, priority=excluded.priority", params![key, body, now, ticket.scope.priority()]).map_err(CacheError::from)?;
        evict(&tx, &key, self.limits)?;
        tx.execute("DELETE FROM requests WHERE key=?1", [&key])
            .map_err(CacheError::from)?;
        tx.commit().map_err(CacheError::from)?;
        Ok(if preserve {
            CachePublication::Preserved
        } else {
            CachePublication::Stored
        })
    }

    /// 失败只推进尝试时间，不修改原结果取得时间和完整度。
    ///
    /// # Errors
    /// 任务失效、账号已退出或存储故障时返回错误。
    pub fn record_failure(&mut self, ticket: &CacheReadTicket, now: i64) -> CacheResult<()> {
        let key = self.crypto.index(&(&self.account, &ticket.scope))?;
        let tx = self
            .db
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(CacheError::from)?;
        validate_ticket(&tx, &self.crypto, &self.account, ticket, &key)?;
        if let Some(body) = load_body(&tx, &key)? {
            let mut record: CacheRecord = self.crypto.open(&body, &key)?;
            record.last_attempt_at = now;
            record.last_attempt_succeeded = false;
            let body = self.crypto.seal(&record, &key)?;
            tx.execute(
                "UPDATE entries SET body=?1 WHERE key=?2",
                params![body, key],
            )
            .map_err(CacheError::from)?;
        }
        tx.execute("DELETE FROM requests WHERE key=?1", [&key])
            .map_err(CacheError::from)?;
        tx.commit().map_err(CacheError::from)
    }

    /// 主动退出先调用此持久栅栏，再执行网络注销。
    ///
    /// # Errors
    /// 本地存储失败时不能宣称已可靠退出。
    pub fn deactivate(&mut self) -> CacheResult<()> {
        self.advance(Some(false), false)
    }
    /// 显式登录且核实归属后重新开放账号；不恢复任何旧 ticket。
    ///
    /// # Errors
    /// 本地存储失败时返回错误。
    pub fn activate(&mut self) -> CacheResult<()> {
        self.advance(Some(true), false)
    }
    /// 清理内容并使所有在途写回失效，保留当前账号登录入口状态。
    ///
    /// # Errors
    /// 事务失败时保留原数据，不显示清理成功。
    pub fn clear(&mut self) -> CacheResult<()> {
        self.advance(None, true)
    }

    fn advance(&mut self, active: Option<bool>, clear: bool) -> CacheResult<()> {
        let tx = self
            .db
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(CacheError::from)?;
        let mut control = load_control(&tx, &self.crypto, &self.account)?;
        control.epoch = control.epoch.checked_add(1).ok_or(CacheError::Capacity)?;
        if let Some(active) = active {
            control.active = active;
        }
        save_control(&tx, &self.crypto, &self.account, &control)?;
        tx.execute("DELETE FROM requests", [])
            .map_err(CacheError::from)?;
        if clear {
            tx.execute("DELETE FROM entries", [])
                .map_err(CacheError::from)?;
        }
        tx.commit().map_err(CacheError::from)
    }
}

fn load_control(db: &Connection, crypto: &Crypto, account: &str) -> CacheResult<Control> {
    let body: Vec<u8> = db
        .query_row("SELECT body FROM control WHERE id=1", [], |r| r.get(0))
        .map_err(CacheError::from)?;
    crypto.open(&body, account.as_bytes())
}
fn save_control(
    db: &Connection,
    crypto: &Crypto,
    account: &str,
    control: &Control,
) -> CacheResult<()> {
    let body = crypto.seal(control, account.as_bytes())?;
    db.execute("UPDATE control SET body=?1 WHERE id=1", [body])
        .map_err(CacheError::from)?;
    Ok(())
}
fn load_body(db: &Connection, key: &[u8]) -> CacheResult<Option<Vec<u8>>> {
    db.query_row("SELECT body FROM entries WHERE key=?1", [key], |r| r.get(0))
        .optional()
        .map_err(CacheError::from)
}
fn require_active(control: &Control) -> CacheResult<()> {
    if control.active {
        Ok(())
    } else {
        Err(CacheError::Inactive)
    }
}
fn validate_ticket(
    db: &Connection,
    crypto: &Crypto,
    account: &str,
    ticket: &CacheReadTicket,
    key: &[u8],
) -> CacheResult<()> {
    let control = load_control(db, crypto, account)?;
    require_active(&control)?;
    let revision: Option<i64> = db
        .query_row("SELECT revision FROM requests WHERE key=?1", [key], |r| {
            r.get(0)
        })
        .optional()
        .map_err(CacheError::from)?;
    if ticket.account != account
        || control.epoch != ticket.epoch
        || revision != Some(ticket.revision)
    {
        return Err(CacheError::Superseded);
    }
    Ok(())
}
fn evict(db: &Connection, protected: &[u8], limits: CacheLimits) -> CacheResult<()> {
    let total: i64 = db
        .query_row(
            "SELECT COALESCE(SUM(length(body)),0) FROM entries",
            [],
            |r| r.get(0),
        )
        .map_err(CacheError::from)?;
    let mut total = u64::try_from(total).map_err(|_| CacheError::Corrupt)?;
    if total <= limits.soft_bytes {
        return Ok(());
    }
    let mut statement = db.prepare("SELECT key, length(body), priority FROM entries WHERE key != ?1 ORDER BY priority, accessed").map_err(CacheError::from)?;
    let candidates = statement
        .query_map([protected], |r| {
            Ok((
                r.get::<_, Vec<u8>>(0)?,
                r.get::<_, i64>(1)?,
                r.get::<_, i64>(2)?,
            ))
        })
        .map_err(CacheError::from)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(CacheError::from)?;
    drop(statement);
    for (key, bytes, priority) in candidates {
        if total <= limits.soft_bytes {
            break;
        }
        if priority > 0 && total <= limits.hard_bytes {
            break;
        }
        db.execute("DELETE FROM entries WHERE key=?1", [key])
            .map_err(CacheError::from)?;
        total = total.saturating_sub(u64::try_from(bytes).map_err(|_| CacheError::Corrupt)?);
    }
    if total > limits.hard_bytes {
        Err(CacheError::Capacity)
    } else {
        Ok(())
    }
}
impl From<rusqlite::Error> for CacheError {
    fn from(error: rusqlite::Error) -> Self {
        match error.sqlite_error_code() {
            Some(rusqlite::ErrorCode::DiskFull) => Self::Capacity,
            Some(rusqlite::ErrorCode::DatabaseCorrupt | rusqlite::ErrorCode::NotADatabase) => {
                Self::Corrupt
            }
            _ => Self::Unavailable,
        }
    }
}
