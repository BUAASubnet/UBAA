use clap::{Args, Subcommand};

use super::LoginArgs;

/// 认证命令组。
#[derive(Debug, Args)]
pub struct AuthArgs {
    #[command(subcommand)]
    pub command: AuthCommand,
}

/// 认证操作。
#[derive(Debug, Subcommand)]
pub enum AuthCommand {
    /// 通过 SSO 登录并持久化会话。
    Login(LoginArgs),
    /// 通过用户中心验证已持久化的会话。
    Status,
    /// 尽可能远程退出，并始终清理本地状态。
    Logout,
}
