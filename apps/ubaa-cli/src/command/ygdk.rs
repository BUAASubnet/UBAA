use std::path::PathBuf;

use clap::{Args, Subcommand};

/// 阳光打卡命令组。
#[derive(Debug, Args)]
pub struct YgdkArgs {
    #[command(subcommand)]
    pub command: YgdkCommand,
}

/// 阳光打卡操作。
#[derive(Debug, Subcommand)]
pub enum YgdkCommand {
    /// 查询阳光打卡概览。
    Overview,
    /// 查询阳光打卡记录。
    Records {
        #[arg(long, default_value_t = 1)]
        page: i32,
        #[arg(long, default_value_t = 20)]
        size: i32,
    },
    /// 提交打卡写操作。
    Submit {
        #[arg(long)]
        item_id: Option<i32>,
        #[arg(long)]
        start_time: String,
        #[arg(long)]
        end_time: String,
        #[arg(long)]
        place: Option<String>,
        #[arg(long)]
        photo: PathBuf,
        #[arg(long)]
        share_to_square: bool,
        #[arg(long = "confirm-write")]
        confirm_write: bool,
    },
}
