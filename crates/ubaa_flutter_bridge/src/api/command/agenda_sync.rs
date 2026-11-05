use super::{Body, BridgeCommand, BridgeCommandResult, command, core, stopped};
use crate::api::{
    agenda::BridgeAgendaStore,
    client::{BridgeClient, BridgeError, disposed_error},
    shared_account::BridgeSharedAccount,
};
use std::{
    path::PathBuf,
    sync::{Arc, atomic::Ordering},
};
impl BridgeCommand {
    /// 复用 GUI 的 Core 同步服务，作业内不进入会话恢复重跑器。
    /// # Errors
    /// 计划已消费或客户端已关闭时拒绝，业务结果由统一命令输出交付。
    /// # Panics
    /// 命令状态锁被其他线程的 panic 污染时终止。
    pub async fn execute_agenda_sync(
        &self,
        client: &BridgeClient,
        agenda: &BridgeAgendaStore,
        scope: &BridgeSharedAccount,
        config_dir: String,
    ) -> Result<BridgeCommandResult, BridgeError> {
        if !self.requirements().agenda_sync || self.attempts.fetch_add(1, Ordering::SeqCst) != 0 {
            return Err(stopped());
        }
        if self.prepared.lock().await.is_none() {
            return Err(stopped());
        }
        let plan = self.plan.as_ref().ok_or_else(stopped)?;
        let command::Command::Agenda(command::AgendaArgs {
            command: command::AgendaCommand::Sync { pull, create, .. },
        }) = &plan.cli().command
        else {
            return Err(stopped());
        };
        let action = if *pull {
            core::AgendaSyncAction::Pull
        } else if *create {
            core::AgendaSyncAction::CreateConfirmed
        } else {
            core::AgendaSyncAction::Push
        };
        let mut guard = client.inner.lock().await;
        if client.is_disposed.load(Ordering::SeqCst) {
            return Err(disposed_error());
        }
        let client = guard.as_mut().ok_or_else(disposed_error)?;
        *self.close.write().unwrap() = Some(client.close_control());
        if client.bhpan_capabilities().conditional_replace == core::BhpanCapability::Available {
            let resolution = client
                .resolve_bhpan_route()
                .map_err(BridgeError::from_routed)?
                .resolution;
            *self.sent.lock().unwrap() =
                Some((Arc::new(client.observe_write_boundary()), resolution));
        }
        let store = agenda.store.clone();
        let mut service =
            core::AgendaSyncService::new(store, PathBuf::from(config_dir).join("agenda_sync"));
        let now = core::AgendaTime::new(
            chrono::Utc::now()
                .with_nanosecond(0)
                .ok_or_else(stopped)?
                .fixed_offset(),
        );
        let result = self.control.run(service.run(client, action, now)).await;
        let result = match result {
            Ok(result) => result,
            Err(reason) => {
                client.close_control().close();
                return Ok(self.failure(if reason == command::StopReason::Deadline {
                    super::BridgeCommandFailure::Timeout
                } else {
                    super::BridgeCommandFailure::Cancelled
                }));
            }
        };
        let mut result = self.result(Body::AgendaSync {
            json: plan.cli().json,
            result: command::agenda::sync::AgendaSyncCommandResult(result),
        });
        result.scope = Some(scope.guard.clone());
        Ok(result)
    }
}
use chrono::Timelike;
