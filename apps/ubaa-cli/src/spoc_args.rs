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
