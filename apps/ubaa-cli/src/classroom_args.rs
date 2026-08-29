use clap::{Args, Subcommand};

/// 空闲教室命令组。
#[derive(Debug, Args)]
pub struct ClassroomArgs {
    #[command(subcommand)]
    pub command: ClassroomCommand,
}

/// 空闲教室操作。
#[derive(Debug, Subcommand)]
pub enum ClassroomCommand {
    /// 查询空闲教室。
    Search {
        #[arg(long)]
        campus: i32,
        #[arg(long)]
        date: String,
    },
}
