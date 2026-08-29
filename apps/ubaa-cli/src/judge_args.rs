use clap::{Args, Subcommand};

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
