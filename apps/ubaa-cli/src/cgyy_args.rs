use clap::{Args, Subcommand};

/// 场馆预约命令组。
#[derive(Debug, Args)]
pub struct CgyyArgs {
    #[command(subcommand)]
    pub command: CgyyCommand,
}

/// 场馆预约只读操作。
#[derive(Debug, Subcommand)]
pub enum CgyyCommand {
    /// 查询场馆站点。
    Sites,
    /// 查询预约用途。
    Purposes,
    /// 查询指定站点日期的时段与空间状态。
    Day {
        #[arg(long)]
        site_id: i32,
        #[arg(long)]
        date: String,
    },
    /// 查询当前用户订单。
    Orders {
        #[arg(long, default_value_t = 0)]
        page: i32,
        #[arg(long, default_value_t = 10)]
        size: i32,
    },
    /// 查询订单详情。
    Detail {
        #[arg(long)]
        id: i32,
    },
    /// 查询当前用户门锁码。
    LockCode,
    /// 取消预约订单。
    Cancel {
        #[arg(long)]
        id: i32,
        #[arg(long = "confirm-write")]
        confirm_write: bool,
    },
    /// 提交场馆预约；敏感请求从标准输入读取。
    Submit {
        #[arg(long)]
        request_stdin: bool,
        #[arg(long = "confirm-write")]
        confirm_write: bool,
    },
}
