//! 认证、连接模式与用户中心命令参数。

use clap::{Args, Subcommand, ValueEnum};
use ubaa_core::domain::ConnectionMode;

/// CLI 中的连接模式写法。
#[derive(Clone, Copy, Debug, ValueEnum)]
pub enum CliConnectionMode {
    /// 直接访问北航服务。
    Direct,
    /// 通过 `WebVPN` 访问北航服务。
    Webvpn,
}

impl From<CliConnectionMode> for ConnectionMode {
    fn from(value: CliConnectionMode) -> Self {
        match value {
            CliConnectionMode::Direct => Self::Direct,
            CliConnectionMode::Webvpn => Self::WebVpn,
        }
    }
}

/// 登录参数。
#[derive(Args)]
pub struct LoginArgs {
    /// 每个请求使用的网络路由；省略时复用已保存的模式。
    #[arg(long, value_enum, hide = true)]
    pub mode: Option<CliConnectionMode>,

    /// SSO 用户名；人类可读模式下省略时会交互询问。
    #[arg(long)]
    pub username: Option<String>,

    /// 从标准输入读取一行用户名（供隐藏的验证与自动化流程使用）。
    #[arg(long, hide = true)]
    pub username_stdin: bool,

    /// 从标准输入读取一行密码。
    #[arg(long)]
    pub password_stdin: bool,
}

impl std::fmt::Debug for LoginArgs {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("LoginArgs")
            .field("mode", &self.mode)
            .field("username", &self.username.as_ref().map(|_| "[REDACTED]"))
            .field("username_stdin", &self.username_stdin)
            .field("password_stdin", &self.password_stdin)
            .finish()
    }
}

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

/// 用户中心命令组。
#[derive(Debug, Args)]
pub struct UserArgs {
    #[command(subcommand)]
    pub command: UserCommand,
}

/// 用户中心操作。
#[derive(Debug, Subcommand)]
pub enum UserCommand {
    /// 显示已认证的用户中心资料。
    Show,
}
