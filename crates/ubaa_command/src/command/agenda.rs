//! 本机日程参数。学校缓存只接受显式路线和学期。
use super::CliConnectionMode;
use chrono::NaiveDate;
use clap::{Args, Subcommand, ValueEnum};
use std::path::PathBuf;
use uuid::Uuid;

#[derive(Clone, Debug, Args)]
pub struct AgendaArgs {
    #[command(subcommand)]
    pub command: AgendaCommand,
}
#[derive(Clone, Debug, Subcommand)]
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
    /// 同步个人云盘日程；上传需要明确确认，首次创建另外确认。
    Sync {
        #[arg(long, conflicts_with_all = ["confirm_write", "create"])]
        pull: bool,
        #[arg(long, requires = "confirm_write")]
        create: bool,
        #[arg(long)]
        confirm_write: bool,
    },
    /// 创建本机日程；输入只含可编辑内容和重复规则。
    Create {
        #[arg(long)]
        input: PathBuf,
        #[arg(long)]
        confirm_local_write: bool,
    },
    /// 按指定重复范围完整替换本机内容。
    Edit {
        #[arg(long)]
        id: Uuid,
        #[arg(long, value_enum)]
        scope: AgendaScope,
        #[arg(long)]
        at: Option<String>,
        #[arg(long)]
        input: PathBuf,
        #[arg(long)]
        confirm_local_write: bool,
    },
    /// 删除本机日程的指定重复范围。
    Delete {
        #[arg(long)]
        id: Uuid,
        #[arg(long, value_enum)]
        scope: AgendaScope,
        #[arg(long)]
        at: Option<String>,
        #[arg(long)]
        confirm_local_write: bool,
    },
    /// 完成本机发生。
    Complete(AgendaCompletion),
    /// 将本机发生重新挂起。
    Reopen(AgendaCompletion),
    /// 修改学校事项的本机覆盖。
    Overlay {
        #[command(subcommand)]
        command: AgendaOverlayCommand,
    },
    /// 核对未同步数量后清除本机日程。
    Clear {
        #[arg(long)]
        expected_unsynced: Option<usize>,
        #[arg(long)]
        confirm_local_write: bool,
    },
    /// 导出日期范围的 ICS 快照。
    Export {
        #[arg(long)]
        from: NaiveDate,
        #[arg(long)]
        to: NaiveDate,
        #[arg(long, requires_all = ["route", "term"])]
        school_cache: bool,
        #[arg(long, value_enum, requires = "school_cache")]
        route: Option<CliConnectionMode>,
        #[arg(long, requires = "school_cache")]
        term: Option<String>,
        #[arg(long, required_unless_present = "stdout", conflicts_with = "stdout")]
        output: Option<PathBuf>,
        #[arg(long, conflicts_with_all = ["output", "json"])]
        stdout: bool,
        #[arg(long, requires = "output")]
        overwrite: bool,
        #[arg(long)]
        include_hidden: bool,
        #[arg(long)]
        exclude_completed: bool,
    },
}
impl AgendaCommand {
    #[must_use]
    pub const fn operation(&self) -> &'static str {
        match self {
            Self::List { .. } => "list",
            Self::Show { .. } => "show",
            Self::Unsynced => "unsynced",
            Self::Sync { .. } => "sync",
            Self::Create { .. } => "create",
            Self::Edit { .. } => "edit",
            Self::Delete { .. } => "delete",
            Self::Complete(_) => "complete",
            Self::Reopen(_) => "reopen",
            Self::Overlay {
                command: AgendaOverlayCommand::Set { .. },
            } => "overlay_set",
            Self::Overlay {
                command: AgendaOverlayCommand::Clear { .. },
            } => "overlay_clear",
            Self::Clear { .. } => "clear",
            Self::Export { .. } => "export",
        }
    }
}

#[derive(Clone, Copy, Debug, ValueEnum)]
pub enum AgendaScope {
    This,
    ThisAndFuture,
    All,
}
impl From<AgendaScope> for ubaa_core::facade::AgendaEditScope {
    fn from(value: AgendaScope) -> Self {
        match value {
            AgendaScope::This => Self::This,
            AgendaScope::ThisAndFuture => Self::ThisAndFuture,
            AgendaScope::All => Self::All,
        }
    }
}
#[derive(Clone, Debug, Args)]
pub struct AgendaCompletion {
    #[arg(long)]
    pub id: Uuid,
    #[arg(long, required_unless_present = "undated", conflicts_with = "undated")]
    pub at: Option<String>,
    #[arg(long, conflicts_with = "at")]
    pub undated: bool,
    #[arg(long)]
    pub confirm_local_write: bool,
}
#[derive(Clone, Copy, Debug, ValueEnum)]
pub enum AgendaCompletionOverride {
    Complete,
    Reopen,
    Inherit,
}
#[derive(Clone, Debug, Subcommand)]
pub enum AgendaOverlayCommand {
    Set {
        #[arg(long)]
        source: String,
        #[arg(long)]
        upstream_id: String,
        #[arg(long, value_enum)]
        completion: Option<AgendaCompletionOverride>,
        #[arg(long, action = clap::ArgAction::Set)]
        hidden: Option<bool>,
        #[arg(long)]
        note_file: Option<PathBuf>,
        #[arg(long)]
        confirm_local_write: bool,
    },
    Clear {
        #[arg(long)]
        source: String,
        #[arg(long)]
        upstream_id: String,
        #[arg(long)]
        confirm_local_write: bool,
    },
}
