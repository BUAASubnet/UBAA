//! 并行读取只更新自身 Cookie，不竞争主客户端的持久会话修订。
use super::ClientRuntime;
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::internal::route_state::RouteFeatureState;
use std::sync::{Arc, Weak};

#[derive(Clone)]
pub(super) struct ReadonlyOwner {
    state: Weak<RouteFeatureState>,
    generation: u64,
}
impl ReadonlyOwner {
    pub(super) fn invalidate(&self) {
        if let Some(state) = self.state.upgrade() {
            state.clear();
        }
    }
    fn current(&self) -> bool {
        self.state
            .upgrade()
            .is_some_and(|state| state.lifecycle_generation() == self.generation)
    }
}

impl ClientRuntime {
    pub(crate) fn fork_parallel_readonly(&mut self) -> Self {
        let mut child = self.fork_for_readonly_with_cookie_filter(|_| true);
        child.readonly_generation = Some(ReadonlyOwner {
            state: Arc::downgrade(&self.feature_state),
            generation: self.feature_state.lifecycle_generation(),
        });
        // Token 可能依赖业务 Cookie；两者一起留在同组，主写客户端独立激活。
        child.feature_state = Arc::new(RouteFeatureState::default());
        child
    }

    pub(crate) fn synchronize_readonly(&mut self, parent: &Self) -> bool {
        let Some(owner) = &self.readonly_generation else {
            return false;
        };
        if !Weak::ptr_eq(&owner.state, &Arc::downgrade(&parent.feature_state)) || !owner.current() {
            return false;
        }
        // 调用方持有认证/写入排他边界；正常身份校验更新修订但不取消业务计划。
        self.session_revision = parent.session_revision;
        true
    }

    pub(super) fn ensure_readonly_generation(&self) -> Result<()> {
        if self
            .readonly_generation
            .as_ref()
            .is_some_and(|owner| !owner.current())
        {
            return Err(UbaaError::new(
                ErrorCode::AuthenticationRequired,
                ErrorKind::Authentication,
                false,
                "读取所属会话已失效",
            ));
        }
        Ok(())
    }

    pub(crate) fn ensure_primary_client(&self) -> Result<()> {
        if self.readonly_generation.is_some() {
            return Err(UbaaError::new(
                ErrorCode::InvalidInput,
                ErrorKind::Input,
                false,
                "只读实例不能执行登录、注销或学校写入",
            ));
        }
        Ok(())
    }
}

#[cfg(test)]
#[path = "runtime_readonly_tests.rs"]
mod tests;
