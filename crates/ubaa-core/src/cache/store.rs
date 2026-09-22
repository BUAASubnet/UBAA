//! `SQLite` 短事务与持久代次；不持有或等待学校网络客户端。
use super::{
    CACHE_SCHEMA_VERSION, CacheCompleteness, CacheError, CacheKey, CacheLimits, CacheObservation,
    CachePayload, CachePublication, CacheReadTicket, CacheRecord, CacheResult, CacheScope,
    crypto::Crypto, files,
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
    generation: u64,
    database_id: [u8; 16],
}
#[derive(Clone, Copy, Eq, PartialEq)]
struct Generation {
    database_id: [u8; 16],
    counter: u64,
}
impl Control {
    fn handle_generation(&self) -> Generation {
        Generation {
            database_id: self.database_id,
            counter: self.generation,
        }
    }
}

/// 每个随机账号别名对应一个私有数据库；调用方串行使用实例，多个实例由事务协调。
pub struct OfflineRepository {
    pub(super) db: Connection,
    crypto: Crypto,
    account: String,
    path: PathBuf,
    limits: CacheLimits,
    generation: Generation,
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
        validate_limits(limits)?;
        let path = files::database_path(root, account)?;
        let mut db = open_connection(&path)?;
        let crypto = Crypto::new(key);
        let account = account.to_ascii_lowercase();
        let generation = initialize_database(&mut db, &crypto, &account, limits)?;
        Ok(Self {
            db,
            crypto,
            account,
            path,
            limits,
            generation,
        })
    }

    /// 返回文件位置供本地容量管理；禁止将路径写入诊断。
    #[must_use]
    pub fn path(&self) -> &Path {
        &self.path
    }

    /// 在短只读事务中核对在途读取资格，不发布或消费该请求。
    ///
    /// # Errors
    /// 账号关闭、较新请求取代或存储故障时返回稳定错误。
    pub fn validate_read(&mut self, ticket: &CacheReadTicket) -> CacheResult<()> {
        let key = self.crypto.index(&(&self.account, &ticket.scope))?;
        let tx = self.db.transaction().map_err(CacheError::from)?;
        validate_ticket(
            &tx,
            &self.crypto,
            &self.account,
            ticket,
            &key,
            self.generation,
        )?;
        tx.commit().map_err(CacheError::from)
    }

    /// 原子续租仍有效的长扫描；不能重新取得已被替代的请求资格。
    ///
    /// # Errors
    /// 原票据失效、账号关闭或事务失败时保持原票据不变。
    pub fn renew_read(&mut self, ticket: &mut CacheReadTicket) -> CacheResult<()> {
        let key = self.crypto.index(&(&self.account, &ticket.scope))?;
        let tx = self
            .db
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(CacheError::from)?;
        validate_ticket(
            &tx,
            &self.crypto,
            &self.account,
            ticket,
            &key,
            self.generation,
        )?;
        let mut control = load_current_control(&tx, &self.crypto, &self.account, self.generation)?;
        control.revision = control
            .revision
            .checked_add(1)
            .ok_or(CacheError::Capacity)?;
        save_control(&tx, &self.crypto, &self.account, &control)?;
        tx.execute(
            "UPDATE requests SET revision=?1 WHERE key=?2",
            params![control.revision, key],
        )
        .map_err(CacheError::from)?;
        tx.commit().map_err(CacheError::from)?;
        ticket.revision = control.revision;
        Ok(())
    }

    /// 为一次精确范围的在线读取分配持久修订；它不授予学校写资格。
    ///
    /// # Errors
    /// 账号已退出、查询非法或本地事务失败时返回错误。
    pub fn begin_read(&mut self, scope: CacheScope) -> CacheResult<CacheReadTicket> {
        self.begin_read_inner(scope, None)
    }

    /// 同事务核对父请求后才分配子范围修订，迟到父任务不能撤销新子读取。
    ///
    /// # Errors
    /// 父请求失效、范围非法或本地存储错误保持原分类。
    pub fn begin_read_guarded(
        &mut self,
        scope: CacheScope,
        parent: &CacheReadTicket,
    ) -> CacheResult<CacheReadTicket> {
        self.begin_read_inner(scope, Some(parent))
    }

    fn begin_read_inner(
        &mut self,
        scope: CacheScope,
        parent: Option<&CacheReadTicket>,
    ) -> CacheResult<CacheReadTicket> {
        scope.validate()?;
        let key = self.crypto.index(&(&self.account, &scope))?;
        let tx = self
            .db
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(CacheError::from)?;
        let mut control = load_current_control(&tx, &self.crypto, &self.account, self.generation)?;
        require_active(&control)?;
        if let Some(parent) = parent {
            let parent_key = self.crypto.index(&(&self.account, &parent.scope))?;
            validate_ticket(
                &tx,
                &self.crypto,
                &self.account,
                parent,
                &parent_key,
                self.generation,
            )?;
        }
        control.revision = control
            .revision
            .checked_add(1)
            .ok_or(CacheError::Capacity)?;
        save_control(&tx, &self.crypto, &self.account, &control)?;
        let body = self.crypto.seal(&scope, &invalidation::scope_aad(&key))?;
        tx.execute("INSERT INTO requests(key,revision,scope) VALUES(?1,?2,?3) ON CONFLICT(key) DO UPDATE SET revision=excluded.revision,scope=excluded.scope", params![key, control.revision, body]).map_err(CacheError::from)?;
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
            database_id: control.database_id,
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
        require_active(&load_current_control(
            &tx,
            &self.crypto,
            &self.account,
            self.generation,
        )?)?;
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
        self.publish_inner(
            ticket,
            None,
            payload,
            CacheObservation {
                source_at: now,
                attempted_at: now,
            },
            completeness,
        )
    }

    /// 子条目与扫描父资格在同一事务内验证，防止退出或较新扫描后迟到落盘。
    ///
    /// # Errors
    /// 任一票据失效或发布失败时不修改原内容。
    pub fn publish_guarded(
        &mut self,
        ticket: &CacheReadTicket,
        parent: &CacheReadTicket,
        payload: CachePayload,
        now: i64,
        completeness: CacheCompleteness,
    ) -> CacheResult<CachePublication> {
        self.publish_inner(
            ticket,
            Some(parent),
            payload,
            CacheObservation {
                source_at: now,
                attempted_at: now,
            },
            completeness,
        )
    }

    /// 复用内容保留原取得/校验时间，本次尝试单独计时。
    ///
    /// # Errors
    /// 与普通发布相同；原票据失效时不能发布。
    pub fn publish_observed(
        &mut self,
        ticket: &CacheReadTicket,
        payload: CachePayload,
        observation: CacheObservation,
        completeness: CacheCompleteness,
    ) -> CacheResult<CachePublication> {
        self.publish_inner(ticket, None, payload, observation, completeness)
    }
    fn publish_inner(
        &mut self,
        ticket: &CacheReadTicket,
        parent: Option<&CacheReadTicket>,
        payload: CachePayload,
        observation: CacheObservation,
        completeness: CacheCompleteness,
    ) -> CacheResult<CachePublication> {
        let now = observation.attempted_at;
        let key = self.crypto.index(&(&self.account, &ticket.scope))?;
        let tx = self
            .db
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(CacheError::from)?;
        validate_ticket(
            &tx,
            &self.crypto,
            &self.account,
            ticket,
            &key,
            self.generation,
        )?;
        if let Some(parent) = parent {
            let parent_key = self.crypto.index(&(&self.account, &parent.scope))?;
            validate_ticket(
                &tx,
                &self.crypto,
                &self.account,
                parent,
                &parent_key,
                self.generation,
            )?;
        }
        // 先在同一事务核对退出/替代栅栏，不能让无效载荷掩盖账号失效。
        if !payload.matches(&ticket.scope.query) {
            return Err(CacheError::InvalidInput);
        }
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
                fetched_at: observation.source_at,
                last_attempt_at: now,
                last_verified_at: observation.source_at,
                last_attempt_succeeded: completeness == CacheCompleteness::Complete,
                revision: ticket.revision,
                completeness,
            }
        };
        let body = self.crypto.seal(&record, &key)?;
        if u64::try_from(body.len()).map_err(|_| CacheError::Capacity)? > self.limits.hard_bytes {
            return Err(CacheError::Capacity);
        }
        retention::Admission {
            db: &tx,
            crypto: &self.crypto,
            account: &self.account,
            limits: self.limits,
            now,
        }
        .reserve(&key, &record, body.len())?;
        tx.execute("INSERT INTO entries VALUES(?1,?2,?3,?4) ON CONFLICT(key) DO UPDATE SET body=excluded.body, accessed=excluded.accessed, priority=excluded.priority", params![key, body, now, ticket.scope.legacy_priority()]).map_err(CacheError::from)?;
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
        self.record_failure_inner(ticket, None, now)
    }
    /// 失败元数据同样受扫描父资格保护，不能污染新任务的缓存状态。
    ///
    /// # Errors
    /// 任一票据失效或本地事务失败时不修改原记录。
    pub fn record_failure_guarded(
        &mut self,
        ticket: &CacheReadTicket,
        parent: &CacheReadTicket,
        now: i64,
    ) -> CacheResult<()> {
        self.record_failure_inner(ticket, Some(parent), now)
    }
    fn record_failure_inner(
        &mut self,
        ticket: &CacheReadTicket,
        parent: Option<&CacheReadTicket>,
        now: i64,
    ) -> CacheResult<()> {
        let key = self.crypto.index(&(&self.account, &ticket.scope))?;
        let tx = self
            .db
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(CacheError::from)?;
        validate_ticket(
            &tx,
            &self.crypto,
            &self.account,
            ticket,
            &key,
            self.generation,
        )?;
        if let Some(parent) = parent {
            let parent_key = self.crypto.index(&(&self.account, &parent.scope))?;
            validate_ticket(
                &tx,
                &self.crypto,
                &self.account,
                parent,
                &parent_key,
                self.generation,
            )?;
        }
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
        let mut control = load_current_control(&tx, &self.crypto, &self.account, self.generation)?;
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
    crypto.open(&body, &control_aad(account))
}
fn save_control(
    db: &Connection,
    crypto: &Crypto,
    account: &str,
    control: &Control,
) -> CacheResult<()> {
    let body = crypto.seal(control, &control_aad(account))?;
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
    generation: Generation,
) -> CacheResult<()> {
    let control = load_current_control(db, crypto, account, generation)?;
    require_active(&control)?;
    let request: Option<(i64, Vec<u8>)> = db
        .query_row(
            "SELECT revision,scope FROM requests WHERE key=?1",
            [key],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .optional()
        .map_err(CacheError::from)?;
    if ticket.account != account
        || control.database_id != ticket.database_id
        || control.epoch != ticket.epoch
        || request.as_ref().map(|value| value.0) != Some(ticket.revision)
    {
        return Err(CacheError::Superseded);
    }
    let (_, body) = request.ok_or(CacheError::Superseded)?;
    let scope: CacheScope = crypto.open(&body, &invalidation::scope_aad(key))?;
    if scope != ticket.scope {
        return Err(CacheError::Corrupt);
    }
    Ok(())
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

#[cfg(test)]
mod management_tests;

mod management;
pub use management::{CacheClearReport, CacheUsage};
fn control_aad(account: &str) -> Vec<u8> {
    [b"ubaa.cache.control.v3\0".as_slice(), account.as_bytes()].concat()
}
fn load_current_control(
    db: &Connection,
    crypto: &Crypto,
    account: &str,
    generation: Generation,
) -> CacheResult<Control> {
    let control = load_control(db, crypto, account)?;
    if control.handle_generation() != generation {
        return Err(CacheError::Superseded);
    }
    Ok(control)
}

#[cfg(test)]
mod retention_tests;

mod retention;

#[cfg(test)]
mod rebuild_tests;

fn validate_limits(limits: CacheLimits) -> CacheResult<()> {
    if limits.soft_bytes == 0
        || limits.soft_bytes > limits.hard_bytes
        || limits.hard_bytes > 100 * 1024 * 1024
    {
        Err(CacheError::InvalidInput)
    } else {
        Ok(())
    }
}
fn open_connection(path: &Path) -> CacheResult<Connection> {
    let db = Connection::open_with_flags(
        path,
        OpenFlags::SQLITE_OPEN_READ_WRITE
            | OpenFlags::SQLITE_OPEN_NO_MUTEX
            | OpenFlags::SQLITE_OPEN_NOFOLLOW,
    )
    .map_err(CacheError::from)?;
    db.busy_timeout(Duration::from_millis(250))
        .map_err(CacheError::from)?;
    Ok(db)
}
fn initialize_database(
    db: &mut Connection,
    crypto: &Crypto,
    account: &str,
    limits: CacheLimits,
) -> CacheResult<Generation> {
    let version: u32 = db
        .pragma_query_value(None, "user_version", |r| r.get(0))
        .map_err(CacheError::from)?;
    if version > CACHE_SCHEMA_VERSION {
        return Err(CacheError::UnsupportedVersion);
    }
    db.execute_batch("PRAGMA journal_mode=DELETE; PRAGMA synchronous=FULL; PRAGMA secure_delete=ON; PRAGMA temp_store=MEMORY; PRAGMA trusted_schema=OFF;").map_err(CacheError::from)?;
    db.pragma_update(
        None,
        "max_page_count",
        i64::try_from(limits.hard_bytes / 4096 + 32).map_err(|_| CacheError::Capacity)?,
    )
    .map_err(CacheError::from)?;
    let tx = db
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(CacheError::from)?;
    // 取得写锁后重新读取，避免并发打开时使用迁移前的版本快照。
    let current_version: u32 = tx
        .pragma_query_value(None, "user_version", |r| r.get(0))
        .map_err(CacheError::from)?;
    if current_version > CACHE_SCHEMA_VERSION {
        return Err(CacheError::UnsupportedVersion);
    }
    tx.execute_batch("CREATE TABLE IF NOT EXISTS control(id INTEGER PRIMARY KEY CHECK(id=1), body BLOB NOT NULL);
        CREATE TABLE IF NOT EXISTS entries(key BLOB PRIMARY KEY, body BLOB NOT NULL, accessed INTEGER NOT NULL, priority INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS requests(key BLOB PRIMARY KEY, revision INTEGER NOT NULL, scope BLOB NOT NULL);").map_err(CacheError::from)?;
    let generation = management::prepare_control(&tx, crypto, account, current_version)?;
    if current_version > 0 && current_version < 5 {
        // 旧在途票据不迁移，业务条目的密文和取得时间保持原样。
        tx.execute_batch("DROP TABLE requests; CREATE TABLE requests(key BLOB PRIMARY KEY, revision INTEGER NOT NULL, scope BLOB NOT NULL);").map_err(CacheError::from)?;
    }
    tx.pragma_update(None, "user_version", CACHE_SCHEMA_VERSION)
        .map_err(CacheError::from)?;
    tx.commit().map_err(CacheError::from)?;
    Ok(generation)
}
mod rebuild;
pub use rebuild::CacheRecovery;

mod invalidation;

pub use invalidation::{CacheInvalidation, CacheInvalidationReport};
