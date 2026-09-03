//! UBAA Core 的命令行解析与输出展示。

mod backend;
pub use backend::{CliBackend, RoutedCliBackend};
mod command;
pub use command::{
    AuthArgs, AuthCommand, BykcArgs, BykcCommand, CgyyArgs, CgyyCommand, ClassroomArgs,
    ClassroomCommand, Cli, CliConnectionMode, Command, EvaluationArgs, EvaluationCommand, ExamArgs,
    ExamCommand, GradesArgs, GradesCommand, JudgeArgs, JudgeAssignmentCommand, JudgeCommand,
    LibBookArgs, LibBookCommand, LoginArgs, ScheduleArgs, ScheduleCommand, SigninArgs,
    SigninCommand, SpocArgs, SpocAssignmentCommand, SpocCommand, UserArgs, UserCommand, YgdkArgs,
    YgdkCommand,
};
mod execute;
pub use execute::{
    run_dual_login, run_dual_logout, run_dual_status, run_with_backend,
    run_with_backend_with_route, run_with_routed_backend,
};
mod io;
pub use io::error::render_startup_error;
mod routing;
pub use routing::ReadonlyRouteContext;

#[cfg(test)]
mod tests {
    use serde_json::json;
    use ubaa_core::domain::CgyyLockCode;

    use crate::io::human::{mask_sensitive, safe_lock_code_value};

    #[test]
    fn sensitive_mask_handles_unicode_without_byte_slicing() {
        assert_eq!(mask_sensitive("ABCD1234"), "AB****34");
        assert_eq!(mask_sensitive("北航用户甲乙"), "北航**甲乙");
    }

    #[test]
    fn lock_code_cli_projection_does_not_expose_opaque_payload() {
        let value = safe_lock_code_value(&CgyyLockCode { available: true });
        assert_eq!(value, json!({"available": true}));
    }
}
