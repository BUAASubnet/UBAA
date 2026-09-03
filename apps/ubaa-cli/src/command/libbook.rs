use clap::{Args, Subcommand};

/// 图书馆座位命令组。
#[derive(Debug, Args)]
pub struct LibBookArgs {
    #[command(subcommand)]
    pub command: LibBookCommand,
}

/// 图书馆座位操作。
#[derive(Debug, Subcommand)]
pub enum LibBookCommand {
    /// 查询楼馆及楼层列表。
    Libraries {
        #[arg(long)]
        day: String,
    },
    /// 查询图书馆分区列表。
    Areas {
        #[arg(long)]
        premises_id: String,
        #[arg(long)]
        storey_id: Option<String>,
        #[arg(long)]
        day: String,
    },
    /// 查询分区详情及可用时段。
    AreaDetail {
        #[arg(long)]
        area_id: String,
    },
    /// 查询指定时段的座位状态。
    Seats {
        #[arg(long)]
        area_id: String,
        #[arg(long)]
        day: String,
        #[arg(long)]
        start_time: String,
        #[arg(long)]
        end_time: String,
    },
    /// 查询当前用户的预约记录。
    Bookings {
        #[arg(long, default_value_t = 1)]
        page: i32,
        #[arg(long, default_value_t = 20)]
        limit: i32,
    },
    /// 预约座位写操作。
    Reserve {
        #[arg(long)]
        area_id: String,
        #[arg(long)]
        seat_id: String,
        #[arg(long)]
        day: String,
        #[arg(long)]
        segment: String,
        #[arg(long, default_value = "")]
        start_time: String,
        #[arg(long, default_value = "")]
        end_time: String,
        #[arg(long = "confirm-write")]
        confirm_write: bool,
    },
    /// 取消预约写操作。
    Cancel {
        #[arg(long)]
        booking_id: String,
        #[arg(long = "confirm-write")]
        confirm_write: bool,
    },
}
