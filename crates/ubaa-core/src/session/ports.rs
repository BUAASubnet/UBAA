//! 会话持久化端口。

use crate::error::Result;

use super::{SessionMutation, SessionSnapshot, VersionedSession};

/// 一个客户端所属会话的持久化端口。
pub trait SessionStore: Send + Sync {
    /// 原子加载会话快照及当前版本号。
    fn load_versioned(&self) -> Result<VersionedSession>;

    /// 仅当 `expected_revision` 仍为当前版本时，原子替换会话。
    fn compare_exchange(
        &self,
        expected_revision: u64,
        replacement: Option<&SessionSnapshot>,
    ) -> Result<SessionMutation>;

    /// 检查指定修订是否仍为外部持久化的最新修订，不采用外部快照。
    fn is_revision_current(&self, expected_revision: u64) -> Result<bool> {
        Ok(self.load_versioned()?.revision == expected_revision)
    }

    /// 加载会话快照（如果存在）。
    fn load(&self) -> Result<Option<SessionSnapshot>> {
        self.load_versioned().map(|state| state.snapshot)
    }

    /// 替换持久化快照。
    fn save(&self, snapshot: &SessionSnapshot) -> Result<()> {
        loop {
            let current = self.load_versioned()?;
            if matches!(
                self.compare_exchange(current.revision, Some(snapshot))?,
                SessionMutation::Applied { .. }
            ) {
                return Ok(());
            }
        }
    }

    /// 删除本地会话状态。
    fn clear(&self) -> Result<()> {
        loop {
            let current = self.load_versioned()?;
            if matches!(
                self.compare_exchange(current.revision, None)?,
                SessionMutation::Applied { .. }
            ) {
                return Ok(());
            }
        }
    }
}
