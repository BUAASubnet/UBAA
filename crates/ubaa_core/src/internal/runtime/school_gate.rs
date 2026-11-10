use super::{ClientRuntime, Result, UbaaError};

impl ClientRuntime {
    pub(crate) fn has_sent_write(&self) -> bool {
        self.non_idempotent_boundary_crossed
    }

    /// 仅用于将访问学校的操作或请求交给网络之前。
    pub(crate) fn check_school_requests(&self) -> Result<()> {
        self.check_operation_controls()?;
        if let Some(service) = &self.app_service {
            let active = service.update_gate_active();
            self.check_operation_controls()?;
            match active {
                Ok(true) => return Err(UbaaError::update_required()),
                Ok(false) => {}
                Err(_) => tracing::warn!(
                    target: "ubaa::app_service::school_gate",
                    "无法读取应用服务门控状态，本次学校请求继续"
                ),
            }
        }
        Ok(())
    }
}
