//! 单轮首页读取的身份校验结果，仅在原客户端和认证代次内复用。
use super::super::{AuthStatus, ConnectionMode, UbaaClient};

#[derive(Default)]
pub(in crate::facade) struct ReadRecoveryBatch {
    serial: u32,
    active: bool,
    routes: [Option<VerifiedRoute>; 2],
}
struct VerifiedRoute {
    authentication: uuid::Uuid,
    policy: u64,
    status: AuthStatus,
}

impl UbaaClient {
    /// 撤销当前轮次内已核验身份，下一次恢复重新访问认证服务。
    pub fn invalidate_read_recovery_batch(&mut self) {
        self.read_recovery_batch.routes = [None, None];
    }
    /// 开始一轮只读加载；后续各功能仍独立解析实际路线。
    pub fn begin_read_recovery_batch(&mut self) -> u32 {
        self.read_recovery_batch.serial = self.read_recovery_batch.serial.wrapping_add(1);
        self.read_recovery_batch.active = true;
        self.read_recovery_batch.routes = [None, None];
        self.read_recovery_batch.serial
    }

    /// 结束原批次。旧批次收尾不影响后来开始的读取。
    pub fn end_read_recovery_batch(&mut self, serial: u32) {
        if serial == self.read_recovery_batch.serial {
            self.read_recovery_batch.active = false;
            self.read_recovery_batch.routes = [None, None];
        }
    }

    pub(in crate::facade) fn cached_recovery_status(
        &self,
        route: ConnectionMode,
    ) -> Option<AuthStatus> {
        let batch = &self.read_recovery_batch;
        if !batch.active {
            return None;
        }
        let runtime = match route {
            ConnectionMode::Direct => &self.direct_runtime,
            ConnectionMode::WebVpn => &self.webvpn_runtime,
        };
        let saved = batch.routes[route_index(route)].as_ref()?;
        (runtime.has_local_session()
            && !runtime.authentication_revoked()
            && saved.authentication == runtime.authentication_generation()
            && saved.policy == self.route_generation)
            .then(|| saved.status.clone())
    }

    pub(in crate::facade) fn remember_recovery_status(
        &mut self,
        route: ConnectionMode,
        status: &AuthStatus,
    ) {
        if !self.read_recovery_batch.active {
            return;
        }
        let generation = self.runtime_for(route).authentication_generation();
        self.read_recovery_batch.routes[route_index(route)] = Some(VerifiedRoute {
            authentication: generation,
            policy: self.route_generation,
            status: status.clone(),
        });
    }
}
fn route_index(route: ConnectionMode) -> usize {
    match route {
        ConnectionMode::Direct => 0,
        ConnectionMode::WebVpn => 1,
    }
}
