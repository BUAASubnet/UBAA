//! 仅持久保存待核对提示，不能恢复学校目标、资格或可消费意图。
use super::{
    CacheError, CacheResult, Generation, OfflineRepository, TransactionBehavior,
    load_current_control, require_active,
};
use crate::domain::ConnectionMode;
use rand::RngCore as _;
use serde::{Deserialize, Serialize};
use std::fmt::Write as _;

/// 与学校提交材料隔离的封闭操作名称，只用于展示核对入口。
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum WriteReadbackOperation {
    BykcSelectCourse,
    BykcDeselectCourse,
    BykcSignCourse,
    SigninPerform,
    LibbookReserve,
    LibbookCancelBooking,
    YgdkSubmit,
    CgyySubmitReservation,
    CgyyCancelOrder,
    EvaluationSubmitCourses,
}

/// 重启后只表明上次操作需要核对，不说明已发送或学校是否成功。
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WriteReadbackHint {
    pub id: String,
    pub operation: WriteReadbackOperation,
    pub route: ConnectionMode,
    pub started_at: i64,
}

/// 仅可移除本轮提示的本地票据，不是学校写意图，也不支持序列化。
pub struct WriteReadbackTicket {
    id: String,
    account: String,
    generation: Generation,
    epoch: u64,
}

impl WriteReadbackTicket {
    /// 仅用于宿主确认已接收结果；不是学校授权或重放凭据。
    #[must_use]
    pub fn id(&self) -> &str {
        &self.id
    }
}

const MAX_HINTS: usize = 64;

impl OfflineRepository {
    /// 显式单次提交前保存最小线索；进程中断后保留待核对提示。
    ///
    /// # Errors
    /// 账号关闭、时间无效、容量或存储错误不降级明文。
    pub fn begin_write_readback(
        &mut self,
        operation: WriteReadbackOperation,
        route: ConnectionMode,
        started_at: i64,
    ) -> CacheResult<WriteReadbackTicket> {
        if started_at <= 0 {
            return Err(CacheError::InvalidInput);
        }
        let tx = self
            .db
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(CacheError::from)?;
        let control = load_current_control(&tx, &self.crypto, &self.account, self.generation)?;
        require_active(&control)?;
        let count: i64 = tx
            .query_row("SELECT COUNT(*) FROM readback_hints", [], |row| row.get(0))
            .map_err(CacheError::from)?;
        if usize::try_from(count).map_err(|_| CacheError::Corrupt)? >= MAX_HINTS {
            return Err(CacheError::Capacity);
        }
        let mut random = [0u8; 16];
        rand::rngs::OsRng
            .try_fill_bytes(&mut random)
            .map_err(|_| CacheError::Unavailable)?;
        let mut id = String::with_capacity(32);
        for byte in random {
            write!(id, "{byte:02x}").map_err(|_| CacheError::Unavailable)?;
        }
        let hint = WriteReadbackHint {
            id: id.clone(),
            operation,
            route,
            started_at,
        };
        let body = self.crypto.seal(&hint, &aad(&self.account, &id))?;
        let used: i64 = tx.query_row(
            "SELECT COALESCE(SUM(length(body)),0) FROM (SELECT body FROM entries UNION ALL SELECT body FROM readback_hints)",
            [], |row| row.get(0),
        ).map_err(CacheError::from)?;
        let total = u64::try_from(used)
            .map_err(|_| CacheError::Corrupt)?
            .checked_add(u64::try_from(body.len()).map_err(|_| CacheError::Capacity)?)
            .ok_or(CacheError::Capacity)?;
        if total > self.limits.hard_bytes {
            return Err(CacheError::Capacity);
        }
        tx.execute(
            "INSERT INTO readback_hints(id,body) VALUES(?1,?2)",
            rusqlite::params![id, body],
        )
        .map_err(CacheError::from)?;
        tx.commit().map_err(CacheError::from)?;
        Ok(WriteReadbackTicket {
            id,
            account: self.account.clone(),
            generation: self.generation,
            epoch: control.epoch,
        })
    }

    /// 仅读取提示白名单；不取得网络锁或恢复任何业务权限。
    ///
    /// # Errors
    /// 旧代次、退出、被篡改记录或存储不可用时保持稳定分类。
    pub fn write_readback_hints(&mut self) -> CacheResult<Vec<WriteReadbackHint>> {
        let tx = self.db.transaction().map_err(CacheError::from)?;
        require_active(&load_current_control(
            &tx,
            &self.crypto,
            &self.account,
            self.generation,
        )?)?;
        let mut hints = Vec::new();
        {
            let mut statement = tx
                .prepare("SELECT id,body FROM readback_hints LIMIT 65")
                .map_err(CacheError::from)?;
            let mut rows = statement.query([]).map_err(CacheError::from)?;
            while let Some(row) = rows.next().map_err(CacheError::from)? {
                let id: String = row.get(0).map_err(CacheError::from)?;
                let body: Vec<u8> = row.get(1).map_err(CacheError::from)?;
                let hint: WriteReadbackHint = self.crypto.open(&body, &aad(&self.account, &id))?;
                if hint.id != id
                    || !valid_id(&id)
                    || hint.started_at <= 0
                    || hints.len() >= MAX_HINTS
                {
                    return Err(CacheError::Corrupt);
                }
                hints.push(hint);
            }
        }
        tx.commit().map_err(CacheError::from)?;
        hints.sort_by(|a, b| (b.started_at, &b.id).cmp(&(a.started_at, &a.id)));
        Ok(hints)
    }

    /// 只有确定结果才移除本轮提示；跨清理/退出的迟到收尾不得修改新状态。
    ///
    /// # Errors
    /// 本地票据过期、账号关闭或删除失败时保持原提示，不改变学校结果。
    pub fn finish_write_readback(&mut self, ticket: &WriteReadbackTicket) -> CacheResult<()> {
        let tx = self
            .db
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(CacheError::from)?;
        let control = load_current_control(&tx, &self.crypto, &self.account, self.generation)?;
        require_active(&control)?;
        if ticket.account != self.account
            || ticket.generation != self.generation
            || ticket.epoch != control.epoch
        {
            return Err(CacheError::Superseded);
        }
        tx.execute("DELETE FROM readback_hints WHERE id=?1", [&ticket.id])
            .map_err(CacheError::from)?;
        tx.commit().map_err(CacheError::from)
    }

    /// 用户核对后移除本地提示；不向学校提交或将结果标记为成功。
    ///
    /// # Errors
    /// 标识无效、退出或存储错误不能显示已移除。
    pub fn dismiss_write_readback(&mut self, id: &str) -> CacheResult<()> {
        if !valid_id(id) {
            return Err(CacheError::InvalidInput);
        }
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
        tx.execute("DELETE FROM readback_hints WHERE id=?1", [id])
            .map_err(CacheError::from)?;
        tx.commit().map_err(CacheError::from)
    }
}

fn aad(account: &str, id: &str) -> Vec<u8> {
    [
        b"ubaa.cache.readback.v1\0".as_slice(),
        account.as_bytes(),
        b"\0",
        id.as_bytes(),
    ]
    .concat()
}
fn valid_id(id: &str) -> bool {
    id.len() == 32
        && id
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}
