use std::path::PathBuf;

use clap::{Args, Subcommand};

/// 教学评教命令组。
#[derive(Debug, Args)]
pub struct EvaluationArgs {
    #[command(subcommand)]
    pub command: EvaluationCommand,
}

/// 教学评教操作。
#[derive(Debug, Subcommand)]
pub enum EvaluationCommand {
    /// 查询全部评教课程及进度。
    All,
    /// 查询待评教课程。
    Pending,
    /// 提交由文件提供的评教结果 JSON 数组。
    Submit {
        #[arg(long)]
        payload: PathBuf,
        #[arg(long = "confirm-write")]
        confirm_write: bool,
    },
    /// 自动读取并提交所有待评教课程。
    SubmitPending {
        #[arg(long = "confirm-write")]
        confirm_write: bool,
    },
}
