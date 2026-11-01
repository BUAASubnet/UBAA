use clap::{Args, Subcommand};

/// 博雅课程命令组。
#[derive(Debug, Args)]
pub struct BykcArgs {
    #[command(subcommand)]
    pub command: BykcCommand,
}

/// 博雅课程操作。
#[derive(Debug, Subcommand)]
pub enum BykcCommand {
    /// 查询用户资料。
    Profile,
    /// 查询课程分页。
    Courses {
        #[arg(long, default_value_t = 1)]
        page: i32,
        #[arg(long, default_value_t = 20)]
        size: i32,
        #[arg(long)]
        all: bool,
    },
    /// 查询课程详情。
    Course {
        #[arg(long)]
        id: i64,
    },
    /// 查询已选课程。
    Chosen,
    /// 查询修读统计。
    Statistics,
    /// 选课写操作。
    Select {
        #[arg(long)]
        course_id: i64,
        #[arg(long = "confirm-write")]
        confirm_write: bool,
    },
    /// 退选写操作。
    Deselect {
        #[arg(long)]
        course_id: i64,
        #[arg(long = "confirm-write")]
        confirm_write: bool,
    },
    /// 签到或签退写操作。
    Sign {
        #[arg(long)]
        course_id: i64,
        #[arg(long)]
        sign_type: i32,
        #[arg(long)]
        lat: Option<f64>,
        #[arg(long)]
        lng: Option<f64>,
        #[arg(long = "confirm-write")]
        confirm_write: bool,
    },
}
