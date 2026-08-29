use clap::{Args, Subcommand};

/// 课表命令组。
#[derive(Debug, Args)]
pub struct ScheduleArgs {
    #[command(subcommand)]
    pub command: ScheduleCommand,
}

/// 课表操作。
#[derive(Debug, Subcommand)]
pub enum ScheduleCommand {
    /// 列出学期。
    Terms,
    /// 列出教学周。
    Weeks {
        #[arg(long)]
        term: String,
    },
    /// 查询指定教学周。
    Current {
        #[arg(long)]
        term: String,
        #[arg(long)]
        week: i32,
    },
    /// 查询今日课程。
    Today,
}
