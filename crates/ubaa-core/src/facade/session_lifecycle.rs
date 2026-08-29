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
