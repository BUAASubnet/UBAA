//! SPOC、希冀与课堂签到命令参数。

use clap::{Args, Subcommand};

/// SPOC 命令组。
#[derive(Debug, Args)]
pub struct SpocArgs {
    #[command(subcommand)]
    pub command: SpocCommand,
}

/// SPOC 操作。
#[derive(Debug, Subcommand)]
pub enum SpocCommand {
    /// 列出作业。
    Assignments,
    /// 输出用于实时验证的安全全局分页证据。
    #[command(hide = true)]
    Diagnostics,
    /// 显示一项作业。
    Assignment {
        #[command(subcommand)]
        command: SpocAssignmentCommand,
    },
}

/// SPOC 作业子命令。
#[derive(Debug, Subcommand)]
pub enum SpocAssignmentCommand {
    /// 显示作业详情。
    Show {
        #[arg(long)]
        id: String,
    },
}

/// 希冀作业命令组。
#[derive(Debug, Args)]
pub struct JudgeArgs {
    #[command(subcommand)]
    pub command: JudgeCommand,
}

/// 希冀作业操作。
#[derive(Debug, Subcommand)]
pub enum JudgeCommand {
    /// 列出作业。
    Assignments {
        #[arg(long)]
        include_expired: bool,
    },
    /// 输出用于实时验证的安全列表解析计数。
    #[command(hide = true)]
    Diagnostics {
        #[arg(long)]
        include_expired: bool,
    },
    /// 作业操作。
    Assignment {
        #[command(subcommand)]
        command: JudgeAssignmentCommand,
    },
}

/// 希冀作业详情子命令。
#[derive(Debug, Subcommand)]
pub enum JudgeAssignmentCommand {
    /// 显示一项详情。
    Show {
        #[arg(long)]
        course_id: String,
        #[arg(long)]
        id: String,
    },
    /// 显示多项详情。
    Details {
        #[arg(long = "key")]
        keys: Vec<String>,
    },
}

/// 课堂签到命令组。
#[derive(Debug, Args)]
pub struct SigninArgs {
    #[command(subcommand)]
    pub command: SigninCommand,
}

/// 课堂签到操作。
#[derive(Debug, Subcommand)]
pub enum SigninCommand {
    /// 列出今日课程及其签到状态。
    Today,
    /// 执行指定课程签到写操作。
    Perform {
        #[arg(long)]
        course_id: String,
        #[arg(long = "confirm-write")]
        confirm_write: bool,
    },
}
