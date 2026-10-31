//! 本机日程只读参数。学校缓存只接受显式路线和学期。
use super::CliConnectionMode;
use chrono::NaiveDate;
use clap::{Args, Subcommand};
use uuid::Uuid;

#[derive(Debug, Args)]
pub struct AgendaArgs {
    #[command(subcommand)]
    pub command: AgendaCommand,
}
#[derive(Debug, Subcommand)]
pub enum AgendaCommand {
    /// 列出校园日期范围 [from, to) 的本机事项。
    List {
        #[arg(long)]
        from: NaiveDate,
        #[arg(long)]
        to: NaiveDate,
        /// 合并同账号已有的学校缓存，不请求学校。
        #[arg(long, requires_all = ["route", "term"])]
        school_cache: bool,
        #[arg(long, value_enum, requires = "school_cache")]
        route: Option<CliConnectionMode>,
        #[arg(long, requires = "school_cache")]
        term: Option<String>,
    },
    /// 查看本机原始事项，包含删除标记。
    Show {
        #[arg(long)]
        id: Uuid,
    },
    /// 查询本机待同步记录数。
    Unsynced,
}
impl AgendaCommand {
    pub(crate) const fn operation(&self) -> &'static str {
        match self {
            Self::List { .. } => "list",
            Self::Show { .. } => "show",
            Self::Unsynced => "unsynced",
        }
    }
}
