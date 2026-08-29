use clap::{Args, Subcommand};

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
