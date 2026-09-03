use std::sync::{Arc, Mutex};

use ubaa_core::facade::Result;
use ubaa_core::facade::testing::{
    SessionMutation, SessionSnapshot, SessionStore, VersionedSession,
};

use crate::http::mock_error;

/// 确定性 Core 集成测试使用的内存会话存储。
#[derive(Clone, Debug, Default)]
pub struct MemorySessionStore {
    state: Arc<Mutex<MemorySessionState>>,
}

#[derive(Debug, Default)]
struct MemorySessionState {
    snapshot: Option<SessionSnapshot>,
    revision: u64,
}

impl MemorySessionStore {
    /// 构造空存储。
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// 返回副本供断言使用。
    ///
    /// # Errors
    ///
    /// 当存储锁中毒时返回提示信息。
    pub fn snapshot(&self) -> std::result::Result<Option<SessionSnapshot>, String> {
        self.state
            .lock()
            .map(|state| state.snapshot.clone())
            .map_err(|_| "memory store lock poisoned".into())
    }
}

impl SessionStore for MemorySessionStore {
    fn load_versioned(&self) -> Result<VersionedSession> {
        let state = self
            .state
            .lock()
            .map_err(|_| mock_error("memory store lock poisoned"))?;
        Ok(VersionedSession {
            snapshot: state.snapshot.clone(),
            revision: state.revision,
        })
    }

    fn compare_exchange(
        &self,
        expected_revision: u64,
        replacement: Option<&SessionSnapshot>,
    ) -> Result<SessionMutation> {
        let mut state = self
            .state
            .lock()
            .map_err(|_| mock_error("memory store lock poisoned"))?;
        if state.revision != expected_revision {
            return Ok(SessionMutation::Conflict);
        }
        state.revision = state
            .revision
            .checked_add(1)
            .ok_or_else(|| mock_error("memory session revision is exhausted"))?;
        state.snapshot = replacement.cloned();
        Ok(SessionMutation::Applied {
            revision: state.revision,
        })
    }
}
