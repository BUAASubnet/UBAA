use clap::{Args, Subcommand};

/// 成绩命令组。
#[derive(Debug, Args)]
pub struct GradesArgs {
    #[command(subcommand)]
    pub command: GradesCommand,
}

/// 成绩操作。
#[derive(Debug, Subcommand)]
pub enum GradesCommand {
    /// 列出指定学期的成绩。
    List {
        #[arg(long)]
        term: String,
    },
}
