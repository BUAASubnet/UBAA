//! 会话持久化端口。

use crate::error::Result;

use super::types::{SessionMutation, SessionSnapshot, VersionedSession};

/// 一个客户端所属会话的持久化端口。
pub trait SessionStore: Send + Sync {
    /// 原子加载会话快照及当前版本号。
    ///
    /// # Errors
    ///
    /// 底层存储无法安全加载会话时返回错误。
    fn load_versioned(&self) -> Result<VersionedSession>;

    /// 仅当 `expected_revision` 仍为当前版本时，原子替换会话。
    ///
    /// # Errors
    ///
    /// 底层存储无法安全比较或替换会话时返回错误。
    fn compare_exchange(
        &self,
        expected_revision: u64,
        replacement: Option<&SessionSnapshot>,
    ) -> Result<SessionMutation>;

    /// 检查指定修订是否仍为外部持久化的最新修订，不采用外部快照。
    ///
    /// # Errors
    ///
    /// 底层存储无法安全读取当前修订时返回错误。
    fn is_revision_current(&self, expected_revision: u64) -> Result<bool> {
        Ok(self.load_versioned()?.revision == expected_revision)
    }

    /// 加载会话快照（如果存在）。
    ///
    /// # Errors
    ///
    /// 底层存储无法安全加载会话时返回错误。
    fn load(&self) -> Result<Option<SessionSnapshot>> {
        self.load_versioned().map(|state| state.snapshot)
    }

    /// 替换持久化快照。
    ///
    /// # Errors
    ///
    /// 底层存储无法安全加载或替换会话时返回错误。
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
    ///
    /// # Errors
    ///
    /// 底层存储无法安全加载或清除会话时返回错误。
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
