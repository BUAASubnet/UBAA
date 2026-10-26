//! 门锁页面的固定路线与同步撤销；不缓存返回材料。
use super::super::UbaaClient;
use super::super::types::Operation;
use crate::domain::{CgyyLockDisplay, ConnectionMode, ReadonlyFeature};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::internal::route_state::RouteFeatureState;
use std::fmt;
use std::sync::{
    Arc, Weak,
    atomic::{AtomicBool, Ordering},
};

#[derive(Clone)]
pub struct CgyyLockDisplayLease {
    owner: Weak<RouteFeatureState>,
    generation: u64,
    route_generation: u64,
    route: ConnectionMode,
    cancelled: Arc<AtomicBool>,
}
impl fmt::Debug for CgyyLockDisplayLease {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("CgyyLockDisplayLease")
    }
}
impl CgyyLockDisplayLease {
    /// 页面隐藏或销毁时同步撤销，不等待网络。
    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Release);
    }
    #[must_use]
    pub fn is_active(&self) -> bool {
        !self.cancelled.load(Ordering::Acquire)
    }
}
impl UbaaClient {
    /// 创建只在当前会话、客户端与路线策略内有效的门锁页面。
    /// # Errors
    /// 没有有效会话或路线不可用时拒绝。
    pub fn open_cgyy_lock_display(&mut self) -> Result<CgyyLockDisplayLease> {
        let resolution = self
            .resolve_operation(Operation::Feature(ReadonlyFeature::Cgyy))
            .map_err(|e| e.error)?;
        let owner = self.runtime_for(resolution.mode).feature_state();
        Ok(CgyyLockDisplayLease {
            generation: owner.lifecycle_generation(),
            owner: Arc::downgrade(&owner),
            route_generation: self.route_generation,
            route: resolution.mode,
            cancelled: Arc::new(AtomicBool::new(false)),
        })
    }
    fn validate_lock_display(&mut self, lease: &CgyyLockDisplayLease) -> Result<()> {
        self.guard_latest_session_ownership()?;
        self.guard_caller_pinned_route(lease.route)?;
        let owner = self.runtime_for(lease.route).feature_state();
        if !lease.is_active()
            || !Weak::ptr_eq(&lease.owner, &Arc::downgrade(&owner))
            || lease.generation != owner.lifecycle_generation()
            || lease.route_generation != self.route_generation
        {
            return Err(UbaaError::new(
                ErrorCode::InvalidInput,
                ErrorKind::Input,
                false,
                "门锁页面已失效，请重新打开",
            ));
        }
        Ok(())
    }
    /// 在页面已解析的路线fresh读取，取消后的迟到结果不返回宿主。
    /// # Errors
    /// 会话、页面失效或上游读取失败时返回安全错误。
    pub async fn read_cgyy_lock_display(
        &mut self,
        lease: &CgyyLockDisplayLease,
    ) -> Result<CgyyLockDisplay> {
        self.validate_lock_display(lease)?;
        let result = crate::features::cgyy::lock_display::read(self.runtime_for(lease.route)).await;
        self.validate_lock_display(lease)?;
        self.finish_caller_pinned(lease.route, result)
            .map(|r| r.data)
    }
}
