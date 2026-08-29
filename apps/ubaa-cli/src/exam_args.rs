use clap::{Args, Subcommand};

/// 考试命令组。
#[derive(Debug, Args)]
pub struct ExamArgs {
    #[command(subcommand)]
    pub command: ExamCommand,
}

/// 考试操作。
#[derive(Debug, Subcommand)]
pub enum ExamCommand {
    /// 列出指定学期的考试。
    List {
        #[arg(long)]
        term: String,
    },
}
