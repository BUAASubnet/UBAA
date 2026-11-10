use super::{ClientRuntime, ErrorCode, ErrorKind, Result, UbaaError};

impl ClientRuntime {
    pub(crate) fn has_sent_write(&self) -> bool {
        self.non_idempotent_boundary_crossed
    }

    /// 仅用于将访问学校的操作或请求交给网络之前。
    pub(crate) fn check_school_requests(&self) -> Result<()> {
        self.check_operation_controls()?;
        if let Some(service) = &self.app_service {
            let active = service.update_gate_active().map_err(|error| {
                UbaaError::new(
                    ErrorCode::InternalError,
                    ErrorKind::Internal,
                    false,
                    error.to_string(),
                )
            })?;
            self.check_operation_controls()?;
            if active {
                return Err(UbaaError::update_required());
            }
        }
        Ok(())
    }
}
