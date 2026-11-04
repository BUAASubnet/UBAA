//! UBAA Core 的命令行解析与输出展示。

pub mod agenda;
pub mod bhpan;
pub use command::{
    BhpanArgs, BhpanCommand, BhpanLibraryKind, BhpanRecycleCommand, BhpanShareCommand,
    BhpanShareOptions, bhpan_password,
};
mod backend;
pub use backend::{CliBackend, RoutedCliBackend};
mod command;
pub use command::{
    AgendaArgs, AgendaCommand, AgendaCompletion, AgendaCompletionOverride, AgendaOverlayCommand,
    AgendaScope, AuthArgs, AuthCommand, BykcArgs, BykcCommand, CgyyArgs, CgyyCommand,
    ClassroomArgs, ClassroomCommand, Cli, CliConnectionMode, Command, EvaluationArgs,
    EvaluationCommand, ExamArgs, ExamCommand, GradesArgs, GradesCommand, JudgeArgs,
    JudgeAssignmentCommand, JudgeCommand, LibBookArgs, LibBookCommand, LoginArgs, ScheduleArgs,
    ScheduleCommand, SigninArgs, SigninCommand, SpocArgs, SpocAssignmentCommand, SpocCommand,
    UserArgs, UserCommand, YgdkArgs, YgdkCommand,
};
pub use command::{NetworkArgs, NetworkCommand, PortalArgs, PortalCommand};
mod execute;
pub use execute::{
    run_dual_login, run_dual_logout, run_dual_status, run_with_backend,
    run_with_backend_with_route, run_with_routed_backend,
};
mod io;
pub use io::error::CliJsonError;
pub use io::render::render_startup_error;
pub use io::schema::{
    AggregateJsonEnvelope, AggregateJsonMeta, AggregateLogoutData, CLI_JSON_SCHEMA_VERSION,
    CliFeature, ResolvedRoutedJsonMeta, RoutedJsonEnvelope, UnresolvedRoutedJsonMeta,
};
mod routing;
pub use routing::ReadonlyRouteContext;

#[cfg(test)]
mod tests {
    use serde_json::json;
    use ubaa_core::facade::CgyyLockCode;

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

pub mod runtime;
pub use runtime::{
    AttemptOutcome, CommandClass, CommandControl, CommandPlan, CommandRequirements,
    PreparedCommand, RecoveryTarget, ResultHandle, StopReason, execute_attempt,
    execute_auth_attempt, execute_fixed_attempt, parse, prepare_input,
};

/// 渲染已知路线的执行错误，保持公共 JSON 和退出码。
pub fn render_operation_error<O: std::io::Write, E: std::io::Write>(
    json: bool,
    feature: CliFeature,
    error: ubaa_core::facade::RoutedError,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    let code = io::render::render_routed_result(json, feature, Err(error), stdout, stderr);
    runtime::finish_output(code, stdout, stderr)
}
