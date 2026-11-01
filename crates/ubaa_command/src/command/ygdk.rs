use std::fmt;
use std::path::PathBuf;

use clap::{Args, Subcommand};

/// 阳光打卡命令组。
#[derive(Args)]
pub struct YgdkArgs {
    #[command(subcommand)]
    pub command: YgdkCommand,
}

/// 阳光打卡操作。
#[derive(Subcommand)]
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
        classify_id: i32,
        #[arg(long)]
        item_id: i32,
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

impl fmt::Debug for YgdkArgs {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("YgdkArgs")
            .field("command", &self.command)
            .finish()
    }
}

impl fmt::Debug for YgdkCommand {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Overview => formatter.write_str("Overview"),
            Self::Records { page, size } => formatter
                .debug_struct("Records")
                .field("page", page)
                .field("size", size)
                .finish(),
            Self::Submit {
                classify_id,
                item_id,
                place,
                share_to_square,
                confirm_write,
                ..
            } => formatter
                .debug_struct("Submit")
                .field("classify_id", classify_id)
                .field("item_id", item_id)
                .field("start_time", &"[已隐藏]")
                .field("end_time", &"[已隐藏]")
                .field("place_present", &place.is_some())
                .field("photo", &"[已隐藏]")
                .field("share_to_square", share_to_square)
                .field("confirm_write", confirm_write)
                .finish(),
        }
    }
}
