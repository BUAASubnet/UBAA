//! 路线客户端的会话冲突与操作收尾。

use super::RouteClient;
use crate::error::{ErrorCode, Result};
use crate::session::DualSessionCoordinator;

impl RouteClient {
    pub(super) fn guard_session_ownership(&mut self) -> Result<()> {
        if self
            .sessions
            .as_ref()
            .is_some_and(DualSessionCoordinator::is_conflicted)
        {
            self.runtime.clear_memory();
            self.auth.clear();
            Err(DualSessionCoordinator::conflict_error())
        } else {
            Ok(())
        }
    }

    /// 在会产生网络副作用的入口前确认当前运行时仍拥有最新会话修订。
    pub(super) fn guard_latest_session_ownership(&mut self) -> Result<()> {
        self.guard_session_ownership()?;
        if !self.runtime.has_local_session() && !self.auth.has_pending_login() {
            self.runtime.sync_empty_session_revision()?;
            return Ok(());
        }
        match self.runtime.ensure_session_revision() {
            Ok(()) => Ok(()),
            Err(error) => {
                self.runtime.clear_memory();
                self.auth.clear();
                Err(error)
            }
        }
    }

    pub(super) fn finish_session_operation<T>(&mut self, result: Result<T>) -> Result<T> {
        self.guard_session_ownership()?;
        result
    }

    pub(super) fn finish_readonly_operation<T>(&mut self, result: Result<T>) -> Result<T> {
        if result
            .as_ref()
            .is_err_and(|error| error.code == ErrorCode::AuthenticationRequired)
        {
            if self.runtime.has_local_session() {
                self.runtime.clear_with(|| self.auth.clear())?;
            } else {
                self.runtime.clear_memory();
                self.auth.clear();
            }
        }
        if result
            .as_ref()
            .is_err_and(|error| error.code == ErrorCode::InternalError)
            && !self.runtime.has_local_session()
        {
            self.auth.clear();
        }
        self.finish_session_operation(result)
    }
}
