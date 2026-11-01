//! 公共命令运行时：解析、计划、一次执行、最终交付分别调用。
mod attempt;
mod control;
mod output;
mod plan;
pub use attempt::{
    AttemptOutcome, PreparedCommand, ResultHandle, execute_attempt, execute_auth_attempt,
    execute_fixed_attempt, execute_local_attempt, prepare_input,
};
pub use control::{CommandControl, StopReason};
pub use output::{OutputChunk, OutputReader, OutputWriter, bounded_output};
pub use plan::{
    CommandClass, CommandPlan, CommandRequirements, ParseFailure, RecoveryTarget, parse,
};
use std::io::Write;

/// 两条标准流完成刷新后才交付退出码。
pub fn finish_output<O: Write, E: Write>(code: i32, stdout: &mut O, stderr: &mut E) -> i32 {
    let out = stdout.flush();
    let err = stderr.flush();
    if out.is_err() || err.is_err() {
        7
    } else {
        code
    }
}
