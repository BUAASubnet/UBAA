//! 只统计密文长度和数据库页，清理不接触会话或凭据。
use super::{
    CacheError, CacheResult, Connection, Control, Crypto, Generation, OfflineRepository,
    OptionalExtension, TransactionBehavior, control_aad, load_current_control, require_active,
    save_control,
};
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CacheUsage {
    pub entry_count: u64,
    pub content_bytes: u64,
    pub database_bytes: u64,
    pub reusable_bytes: u64,
    pub soft_limit_bytes: u64,
    pub hard_limit_bytes: u64,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CacheClearReport {
    /// 返回此报告即表示内容清除事务已提交。
    pub usage: Option<CacheUsage>,
    pub compacted: bool,
    /// 提交后的压缩或统计错误不假装成事务回滚。
    pub maintenance_error: Option<CacheError>,
}
pub(super) fn prepare_control(
    db: &Connection,
    crypto: &Crypto,
    account: &str,
    new_database: bool,
) -> CacheResult<Generation> {
    let body: Option<Vec<u8>> = db
        .query_row("SELECT body FROM control WHERE id=1", [], |r| r.get(0))
        .optional()
        .map_err(CacheError::from)?;
    if let Some(body) = body {
        return crypto
            .open::<Control>(&body, &control_aad(account))
            .map(|control| control.handle_generation());
    }
    if !new_database {
        return Err(CacheError::Corrupt);
    }
    let control = Control {
        epoch: 0,
        revision: 0,
        active: true,
        generation: 0,
        database_id: database_id()?,
    };
    let body = crypto.seal(&control, &control_aad(account))?;
    db.execute("INSERT INTO control VALUES(1,?1)", [body])
        .map_err(CacheError::from)?;
    Ok(control.handle_generation())
}
fn database_id() -> CacheResult<[u8; 16]> {
    use rand::RngCore as _;
    let mut id = [0; 16];
    rand::rngs::OsRng
        .try_fill_bytes(&mut id)
        .map_err(|_| CacheError::Unavailable)?;
    Ok(id)
}
impl OfflineRepository {
    /// 不读取业务正文，仅返回当前账号的数值用量与限额。
    ///
    /// # Errors
    /// 已退出、旧代次、损坏或本地存储失败保持稳定错误。
    pub fn usage(&mut self) -> CacheResult<CacheUsage> {
        let tx = self.db.transaction().map_err(CacheError::from)?;
        require_active(&load_current_control(
            &tx,
            &self.crypto,
            &self.account,
            self.generation,
        )?)?;
        let (entry_count, content_bytes): (i64, i64) = tx
            .query_row(
                "SELECT COUNT(*), COALESCE(SUM(length(body)),0) FROM (SELECT body FROM entries UNION ALL SELECT body FROM readback_hints)",
                [],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .map_err(CacheError::from)?;
        let pages: i64 = tx
            .pragma_query_value(None, "page_count", |r| r.get(0))
            .map_err(CacheError::from)?;
        let size: i64 = tx
            .pragma_query_value(None, "page_size", |r| r.get(0))
            .map_err(CacheError::from)?;
        let free: i64 = tx
            .pragma_query_value(None, "freelist_count", |r| r.get(0))
            .map_err(CacheError::from)?;
        let unsigned = |value| u64::try_from(value).map_err(|_| CacheError::Corrupt);
        let value = CacheUsage {
            entry_count: unsigned(entry_count)?,
            content_bytes: unsigned(content_bytes)?,
            database_bytes: unsigned(pages.checked_mul(size).ok_or(CacheError::Capacity)?)?,
            reusable_bytes: unsigned(free.checked_mul(size).ok_or(CacheError::Capacity)?)?,
            soft_limit_bytes: self.limits.soft_bytes,
            hard_limit_bytes: self.limits.hard_bytes,
        };
        tx.commit().map_err(CacheError::from)?;
        Ok(value)
    }
    pub(crate) fn validate_handle(&mut self) -> CacheResult<()> {
        let tx = self.db.transaction().map_err(CacheError::from)?;
        require_active(&load_current_control(
            &tx,
            &self.crypto,
            &self.account,
            self.generation,
        )?)?;
        tx.commit().map_err(CacheError::from)
    }
    /// 设置清理使用的代次轮换；旧连接不能再取得新票据或激活账号。
    ///
    /// # Errors
    /// 清除事务失败保留数据与代次；提交后维护错误在报告中分开返回。
    pub fn clear_for_reopen(&mut self) -> CacheResult<CacheClearReport> {
        self.clear_with_maintenance(|db| db.execute_batch("VACUUM").map_err(CacheError::from))
    }
    pub(super) fn clear_with_maintenance(
        &mut self,
        compact: impl FnOnce(&Connection) -> CacheResult<()>,
    ) -> CacheResult<CacheClearReport> {
        let tx = self
            .db
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(CacheError::from)?;
        let mut control = load_current_control(&tx, &self.crypto, &self.account, self.generation)?;
        require_active(&control)?;
        control.epoch = control.epoch.checked_add(1).ok_or(CacheError::Capacity)?;
        control.generation = control
            .generation
            .checked_add(1)
            .ok_or(CacheError::Capacity)?;
        save_control(&tx, &self.crypto, &self.account, &control)?;
        tx.execute("DELETE FROM entries", [])
            .map_err(CacheError::from)?;
        tx.execute("DELETE FROM requests", [])
            .map_err(CacheError::from)?;
        tx.execute("DELETE FROM readback_hints", [])
            .map_err(CacheError::from)?;
        tx.commit().map_err(CacheError::from)?;
        self.generation = control.handle_generation();
        let maintenance_error = compact(&self.db).err();
        let compacted = maintenance_error.is_none();
        let usage = self.usage();
        let maintenance_error = maintenance_error.or_else(|| usage.as_ref().err().copied());
        Ok(CacheClearReport {
            usage: usage.ok(),
            compacted,
            maintenance_error,
        })
    }
}
