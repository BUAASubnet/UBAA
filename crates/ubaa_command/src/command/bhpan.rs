//! 云盘命令参数，路径仅用于本次读取中的目标选择。
use clap::{Args, Subcommand, ValueEnum};
use std::path::PathBuf;
use ubaa_core::facade::{BhpanPermission, BhpanRootKind, BhpanShareSettings};
use ubaa_core::facade::{Result, SecretValue, UbaaClient, UbaaError};

#[derive(Clone, Copy, Debug, Default, ValueEnum)]
pub enum BhpanLibraryKind {
    All,
    #[default]
    Personal,
    Shared,
    Department,
    Group,
}
impl From<BhpanLibraryKind> for BhpanRootKind {
    fn from(value: BhpanLibraryKind) -> Self {
        match value {
            BhpanLibraryKind::All => Self::All,
            BhpanLibraryKind::Personal => Self::Personal,
            BhpanLibraryKind::Shared => Self::Shared,
            BhpanLibraryKind::Department => Self::Department,
            BhpanLibraryKind::Group => Self::Group,
        }
    }
}
#[derive(Clone, Debug, Args)]
pub struct BhpanArgs {
    /// 文档库分类。个人库以外需要 --library 指定本次列表中的名称。
    #[arg(long, global = true, value_enum, default_value = "personal")]
    pub root: BhpanLibraryKind,
    #[arg(long, global = true)]
    pub library: Option<String>,
    #[command(subcommand)]
    pub command: BhpanCommand,
}
#[derive(Clone, Debug, Subcommand)]
pub enum BhpanCommand {
    /// 复用学校 SSO 激活云盘。
    Login,
    Roots,
    List {
        #[arg(default_value = "/")]
        path: String,
    },
    Stat {
        path: String,
    },
    SuggestName {
        parent: String,
        name: String,
    },
    Mkdir {
        parent: String,
        name: String,
        #[arg(long)]
        confirm_write: bool,
    },
    Rename {
        path: String,
        name: String,
        #[arg(long)]
        confirm_write: bool,
    },
    Move {
        path: String,
        destination: String,
        #[arg(long)]
        confirm_write: bool,
    },
    Copy {
        path: String,
        destination: String,
        #[arg(long)]
        confirm_write: bool,
    },
    Delete {
        path: String,
        #[arg(long)]
        confirm_write: bool,
    },
    Recycle {
        #[command(subcommand)]
        command: BhpanRecycleCommand,
    },
    Share {
        #[command(subcommand)]
        command: BhpanShareCommand,
    },
    /// 只尝试个人库秒传，未匹配时停止。
    UploadFast {
        parent: String,
        file: PathBuf,
        name: String,
        #[arg(long)]
        confirm_write: bool,
    },
    /// 只返回脱敏下载准备摘要，不传输文件字节。
    DownloadPrepare {
        #[arg(required = true)]
        paths: Vec<String>,
    },
}
#[derive(Clone, Debug, Subcommand)]
pub enum BhpanRecycleCommand {
    List,
    /// 以本次回收站列表中唯一的定位值或名称选择目标。
    Restore {
        selector: String,
        #[arg(long)]
        confirm_write: bool,
    },
    DeleteForever {
        selector: String,
        #[arg(long)]
        confirm_write: bool,
    },
}
#[derive(Clone, Debug, Subcommand)]
pub enum BhpanShareCommand {
    History,
    Records {
        path: String,
    },
    Create {
        path: String,
        #[command(flatten)]
        settings: BhpanShareOptions,
        #[arg(long)]
        confirm_write: bool,
    },
    Update {
        link: String,
        #[command(flatten)]
        settings: BhpanShareOptions,
        #[arg(long)]
        confirm_write: bool,
    },
    Cancel {
        link: String,
        #[arg(long)]
        confirm_write: bool,
    },
    /// 打开分享并浏览指定路径；密码仅从标准输入读取。
    Open {
        link: String,
        #[arg(default_value = "/")]
        path: String,
        #[arg(long)]
        password_stdin: bool,
    },
    Save {
        link: String,
        path: String,
        destination: String,
        #[arg(long)]
        password_stdin: bool,
        #[arg(long)]
        confirm_write: bool,
    },
}
#[derive(Clone, Copy, Debug, ValueEnum)]
pub enum BhpanAllow {
    Create,
    Modify,
    Download,
    Preview,
    Display,
}
#[derive(Clone, Debug, Args)]
pub struct BhpanShareOptions {
    #[arg(long)]
    pub title: String,
    #[arg(long)]
    pub expires_at: String,
    #[arg(long, default_value_t=-1, allow_hyphen_values=true)]
    pub limited_times: i64,
    #[arg(long, value_enum, value_delimiter = ',', required = true)]
    pub allow: Vec<BhpanAllow>,
    /// 从标准输入读取分享密码。省略表示空密码。
    #[arg(long)]
    pub password_stdin: bool,
}
impl BhpanShareOptions {
    pub fn settings(&self, password: SecretValue) -> BhpanShareSettings {
        BhpanShareSettings {
            title: self.title.clone(),
            expires_at: self.expires_at.clone(),
            limited_times: self.limited_times,
            password,
            permissions: self
                .allow
                .iter()
                .map(|v| match v {
                    BhpanAllow::Create => BhpanPermission::Create,
                    BhpanAllow::Modify => BhpanPermission::Modify,
                    BhpanAllow::Download => BhpanPermission::Download,
                    BhpanAllow::Preview => BhpanPermission::Preview,
                    BhpanAllow::Display => BhpanPermission::Display,
                })
                .collect(),
        }
    }
}
impl BhpanCommand {
    pub const fn confirmation(&self) -> Option<bool> {
        match self {
            Self::Mkdir { confirm_write, .. }
            | Self::Rename { confirm_write, .. }
            | Self::Move { confirm_write, .. }
            | Self::Copy { confirm_write, .. }
            | Self::Delete { confirm_write, .. }
            | Self::UploadFast { confirm_write, .. }
            | Self::Recycle {
                command:
                    BhpanRecycleCommand::Restore { confirm_write, .. }
                    | BhpanRecycleCommand::DeleteForever { confirm_write, .. },
            }
            | Self::Share {
                command:
                    BhpanShareCommand::Create { confirm_write, .. }
                    | BhpanShareCommand::Update { confirm_write, .. }
                    | BhpanShareCommand::Cancel { confirm_write, .. }
                    | BhpanShareCommand::Save { confirm_write, .. },
            } => Some(*confirm_write),
            _ => None,
        }
    }
    pub const fn password_stdin(&self) -> bool {
        match self {
            Self::Share {
                command:
                    BhpanShareCommand::Create { settings, .. }
                    | BhpanShareCommand::Update { settings, .. },
            } => settings.password_stdin,
            Self::Share {
                command:
                    BhpanShareCommand::Open { password_stdin, .. }
                    | BhpanShareCommand::Save { password_stdin, .. },
            } => *password_stdin,
            _ => false,
        }
    }
    pub fn validate(&self) -> Result<()> {
        let paths: Vec<&str> = match self {
            Self::List { path }
            | Self::Stat { path }
            | Self::Rename { path, .. }
            | Self::Delete { path, .. } => vec![path],
            Self::SuggestName { parent, .. }
            | Self::Mkdir { parent, .. }
            | Self::UploadFast { parent, .. } => vec![parent],
            Self::Move {
                path, destination, ..
            }
            | Self::Copy {
                path, destination, ..
            } => vec![path, destination],
            Self::DownloadPrepare { paths } => paths.iter().map(String::as_str).collect(),
            Self::Share {
                command:
                    BhpanShareCommand::Records { path }
                    | BhpanShareCommand::Create { path, .. }
                    | BhpanShareCommand::Open { path, .. },
            } => vec![path],
            Self::Share {
                command:
                    BhpanShareCommand::Save {
                        path, destination, ..
                    },
            } => vec![path, destination],
            _ => vec![],
        };
        for path in paths {
            crate::bhpan::validate_path(path)?;
        }
        match self {
            Self::Mkdir { name, .. }
            | Self::Rename { name, .. }
            | Self::SuggestName { name, .. } => UbaaClient::validate_bhpan_name(name)?,
            Self::UploadFast { file, name, .. } => {
                UbaaClient::validate_bhpan_name(name)?;
                if !std::fs::metadata(file).is_ok_and(|m| m.is_file()) {
                    return Err(UbaaError::invalid_input("秒传文件不可读"));
                }
            }
            Self::Share {
                command:
                    BhpanShareCommand::Create { settings, .. }
                    | BhpanShareCommand::Update { settings, .. },
            } => {
                UbaaClient::validate_bhpan_share_settings(&settings.settings(SecretValue::new("")))?
            }
            _ => {}
        }
        Ok(())
    }
}
/// 输入快照只保存密码行，不将密码放入 argv 或输出。
pub fn bhpan_password(bytes: &[u8]) -> Result<SecretValue> {
    if bytes.len() > 4096 {
        return Err(UbaaError::invalid_input("分享密码过长"));
    }
    let text =
        std::str::from_utf8(bytes).map_err(|_| UbaaError::invalid_input("分享密码必须为 UTF-8"))?;
    let value = text
        .strip_suffix("\r\n")
        .or_else(|| text.strip_suffix('\n'))
        .unwrap_or(text);
    if value.contains(['\r', '\n', '\0']) {
        return Err(UbaaError::invalid_input("分享密码只能有一行"));
    }
    Ok(SecretValue::new(value))
}
