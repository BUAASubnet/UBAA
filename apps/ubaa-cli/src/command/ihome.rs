//! iHome 只读命令。
use clap::{Args, Subcommand, ValueEnum};
use ubaa_core::facade::{IhomeFilter, IhomeQuery, IhomeScope};
#[derive(Debug, Args)]
pub struct IhomeArgs {
    #[command(subcommand)]
    pub command: IhomeCommand,
}
#[derive(Debug, Subcommand)]
pub enum IhomeCommand {
    /// 查询诉求分页。
    List {
        #[arg(long, value_enum, default_value = "public")]
        scope: Scope,
        #[arg(long, default_value_t = 1)]
        page: i32,
        #[arg(long, default_value_t = 15)]
        limit: i32,
        #[arg(long, default_value = "")]
        keyword: String,
        #[arg(long, value_enum, default_value = "all")]
        filter: Filter,
        #[arg(long)]
        category_id: Option<i64>,
    },
    /// 查询诉求详情。
    Detail {
        id: i64,
        #[arg(long)]
        mine: bool,
    },
    /// 查询分类和支持开关。
    Config,
    /// 查询公告列表。
    Notices,
    /// 查询公告详情。
    Notice { id: i64 },
}
#[derive(Clone, Copy, Debug, ValueEnum)]
pub enum Scope {
    Public,
    Mine,
    Followed,
    Appraised,
}
#[derive(Clone, Copy, Debug, ValueEnum)]
pub enum Filter {
    All,
    Newest,
    Oldest,
    Replied,
    Unreplied,
    ReplyTime,
}
pub fn query(
    scope: Scope,
    page: i32,
    limit: i32,
    keyword: String,
    filter: Filter,
    category_id: Option<i64>,
) -> IhomeQuery {
    IhomeQuery {
        scope: match scope {
            Scope::Public => IhomeScope::Public,
            Scope::Mine => IhomeScope::Mine,
            Scope::Followed => IhomeScope::Followed,
            Scope::Appraised => IhomeScope::Appraised,
        },
        page,
        limit,
        keyword,
        filter: match filter {
            Filter::All => IhomeFilter::All,
            Filter::Newest => IhomeFilter::Newest,
            Filter::Oldest => IhomeFilter::Oldest,
            Filter::Replied => IhomeFilter::Replied,
            Filter::Unreplied => IhomeFilter::Unreplied,
            Filter::ReplyTime => IhomeFilter::ReplyTime,
        },
        category_id,
    }
}
