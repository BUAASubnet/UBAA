//! 门户资料、账户指标和网费流量命令。
use clap::{Args, Subcommand};

#[derive(Debug, Args)]
pub struct PortalArgs {
    #[command(subcommand)]
    pub command: PortalCommand,
}

#[derive(Debug, Subcommand)]
pub enum PortalCommand {
    /// 查询门户身份与学院。
    Profile,
    /// 查询余额、邮件和图书数量、云盘剩余空间。
    Metrics,
}

#[derive(Debug, Args)]
pub struct NetworkArgs {
    #[command(subcommand)]
    pub command: NetworkCommand,
}

#[derive(Debug, Subcommand)]
pub enum NetworkCommand {
    /// 查询已用流量、免费和计费剩余流量。
    Usage,
}
