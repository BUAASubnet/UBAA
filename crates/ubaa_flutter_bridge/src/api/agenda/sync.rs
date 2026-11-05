//! GUI 与 App 命令使用相同的 Core 日程同步服务。
use super::{
    BridgeAgendaStore, convert,
    models::{BridgeAgendaFailure, BridgeAgendaTime},
};
use crate::api::client::{BridgeClient, BridgeError, catch_panic, disposed_error};
use std::{path::PathBuf, sync::atomic::Ordering};
use ubaa_core::facade as core;
#[cfg(test)]
mod tests;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeAgendaSyncAction {
    Pull,
    Push,
    CreateConfirmed,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeAgendaSyncStatus {
    UpToDate,
    Pending,
    NeedsCreation,
    LocationUnknown,
    Unverified,
    Failed,
    Conflict,
    OutcomeUnknown,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BridgeAgendaSyncReport {
    pub status: BridgeAgendaSyncStatus,
    pub pending_count: u32,
    pub changed_count: u32,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BridgeAgendaSyncError {
    pub local: Option<BridgeAgendaFailure>,
    pub remote: Option<BridgeError>,
}
impl std::fmt::Display for BridgeAgendaSyncError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("日程同步未完成")
    }
}
impl std::error::Error for BridgeAgendaSyncError {}
impl From<core::AgendaSyncError> for BridgeAgendaSyncError {
    fn from(value: core::AgendaSyncError) -> Self {
        match value {
            core::AgendaSyncError::Local(error) => Self {
                local: Some(convert::error(error).failure),
                remote: None,
            },
            core::AgendaSyncError::Remote(error) => Self::from(BridgeError::from_core(error, None)),
        }
    }
}
impl From<BridgeError> for BridgeAgendaSyncError {
    fn from(value: BridgeError) -> Self {
        Self {
            local: None,
            remote: Some(value),
        }
    }
}
impl From<BridgeAgendaSyncAction> for core::AgendaSyncAction {
    fn from(value: BridgeAgendaSyncAction) -> Self {
        match value {
            BridgeAgendaSyncAction::Pull => Self::Pull,
            BridgeAgendaSyncAction::Push => Self::Push,
            BridgeAgendaSyncAction::CreateConfirmed => Self::CreateConfirmed,
        }
    }
}
impl TryFrom<core::AgendaSyncReport> for BridgeAgendaSyncReport {
    type Error = BridgeAgendaSyncError;
    fn try_from(value: core::AgendaSyncReport) -> Result<Self, Self::Error> {
        use core::AgendaSyncStatus as S;
        Ok(Self {
            status: match value.status {
                S::UpToDate => BridgeAgendaSyncStatus::UpToDate,
                S::Pending => BridgeAgendaSyncStatus::Pending,
                S::NeedsCreation => BridgeAgendaSyncStatus::NeedsCreation,
                S::LocationUnknown => BridgeAgendaSyncStatus::LocationUnknown,
                S::Unverified => BridgeAgendaSyncStatus::Unverified,
                S::Failed => BridgeAgendaSyncStatus::Failed,
                S::Conflict => BridgeAgendaSyncStatus::Conflict,
                S::OutcomeUnknown => BridgeAgendaSyncStatus::OutcomeUnknown,
            },
            pending_count: u32::try_from(value.pending_count)
                .map_err(|_| core::AgendaSyncError::Local(core::CacheError::Capacity))?,
            changed_count: u32::try_from(value.changed_count)
                .map_err(|_| core::AgendaSyncError::Local(core::CacheError::Capacity))?,
        })
    }
}
pub struct BridgeAgendaSyncService {
    pub(crate) inner: tokio::sync::Mutex<core::AgendaSyncService>,
}
impl BridgeAgendaSyncService {
    #[must_use]
    pub fn open(agenda: &BridgeAgendaStore, config_dir: String) -> Self {
        Self {
            inner: tokio::sync::Mutex::new(core::AgendaSyncService::new(
                agenda.store.clone(),
                PathBuf::from(config_dir).join("agenda_sync"),
            )),
        }
    }
}
/// 确认发起时持有的 Core 同步作用域，不能由宿主构造或改写。
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeAgendaSyncScope {
    inner: core::AgendaSyncScope,
}

impl BridgeClient {
    /// 立即捕获当前作用域；客户端忙时拒绝，避免等待到另一个客户端。
    /// # Errors
    /// 客户端忙或已关闭时不建立创建确认。
    #[flutter_rust_bridge::frb(sync)]
    pub fn capture_agenda_sync_scope(
        &self,
    ) -> Result<BridgeAgendaSyncScope, BridgeAgendaSyncError> {
        let guard = self
            .inner
            .try_lock()
            .map_err(|_| core::AgendaSyncError::Local(core::CacheError::Unavailable))?;
        if self.is_disposed.load(Ordering::SeqCst) {
            return Err(disposed_error().into());
        }
        let client = guard.as_ref().ok_or_else(disposed_error)?;
        Ok(BridgeAgendaSyncScope {
            inner: client.agenda_sync_scope()?,
        })
    }

    /// 执行一次读取或更新触发。首次创建必须提交原确认作用域。
    /// # Errors
    /// 分别保留本机日程故障与云盘错误，关闭后不交付旧结果。
    pub async fn sync_agenda(
        &self,
        service: &BridgeAgendaSyncService,
        action: BridgeAgendaSyncAction,
        now: BridgeAgendaTime,
    ) -> Result<BridgeAgendaSyncReport, BridgeAgendaSyncError> {
        self.sync_agenda_scoped(service, action, now, None).await
    }

    /// 在实际执行客户端锁内校验原确认作用域后，尝试首次创建。
    /// # Errors
    /// 作用域已改变、客户端已关闭或同步失败时返回对应错误。
    pub async fn create_agenda_sync_confirmed(
        &self,
        service: &BridgeAgendaSyncService,
        now: BridgeAgendaTime,
        scope: &BridgeAgendaSyncScope,
    ) -> Result<BridgeAgendaSyncReport, BridgeAgendaSyncError> {
        self.sync_agenda_scoped(
            service,
            BridgeAgendaSyncAction::CreateConfirmed,
            now,
            Some(scope),
        )
        .await
    }

    async fn sync_agenda_scoped(
        &self,
        service: &BridgeAgendaSyncService,
        action: BridgeAgendaSyncAction,
        now: BridgeAgendaTime,
        scope: Option<&BridgeAgendaSyncScope>,
    ) -> Result<BridgeAgendaSyncReport, BridgeAgendaSyncError> {
        let now: core::AgendaTime =
            now.try_into()
                .map_err(
                    |error: super::models::BridgeAgendaError| BridgeAgendaSyncError {
                        local: Some(error.failure),
                        remote: None,
                    },
                )?;
        let mut guard = self.inner.lock().await;
        if self.is_disposed.load(Ordering::SeqCst) {
            return Err(disposed_error().into());
        }
        let client = guard.as_mut().ok_or_else(disposed_error)?;
        if action == BridgeAgendaSyncAction::CreateConfirmed && scope.is_none() {
            return Err(core::AgendaSyncError::Local(core::CacheError::Superseded).into());
        }
        let mut service = service.inner.lock().await;
        let result = catch_panic(async {
            Ok(match scope {
                Some(scope) => service.run_confirmed(client, &scope.inner, now).await,
                None => service.run(client, action.into(), now).await,
            })
        })
        .await?;
        if self.is_disposed.load(Ordering::SeqCst) {
            return Err(disposed_error().into());
        }
        result.map_err(BridgeAgendaSyncError::from)?.try_into()
    }
}
