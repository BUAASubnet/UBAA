//! Core-live 参数合同。

use std::path::PathBuf;

use clap::Parser;

#[derive(Debug, Parser)]
#[command(name = "ubaa-core-live", about = "Core 单路线真实只读验证")]
pub(crate) struct Args {
    /// 只允许显式 Direct 或 WebVPN，真实验证不执行 auto。
    #[arg(long)]
    pub(crate) route: String,
    /// 要验证的功能，或 all。
    #[arg(long, default_value = "all")]
    pub(crate) feature: String,
    /// 专用验证目录；登录会重建目录内的会话和固定路线配置。
    #[arg(long)]
    pub(crate) config_dir: PathBuf,
    /// 从 stdin 读取用户名第一行。
    #[arg(long)]
    pub(crate) username_stdin: bool,
    /// 从 stdin 读取密码第二行。
    #[arg(long)]
    pub(crate) password_stdin: bool,
    /// 只读日期参数，由外层安全入口提供。
    #[arg(long)]
    pub(crate) date: String,
    /// 空教室校区编号。
    #[arg(long, default_value_t = 1)]
    pub(crate) campus_id: i32,
    #[arg(long, help = "可选诊断文件，路径必须位于仓库根目录的 .ubaa_local/ 内")]
    pub(crate) diagnostics: Option<PathBuf>,
}

pub(crate) const FEATURES: &[&str] = &[
    "all",
    "auth",
    "user",
    "schedule",
    "exam",
    "grades",
    "classroom",
    "spoc",
    "spoc_classroom",
    "judge",
    "signin",
    "ygdk",
    "libbook",
    "bykc",
    "cgyy",
    "evaluation",
    "ihome",
    "health_cloud",
    "portal",
    "network",
    "finance",
    "library_loans",
];
