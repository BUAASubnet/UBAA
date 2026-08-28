//! CLI 登录参数及其敏感字段脱敏。

use clap::Args;

use super::CliConnectionMode;

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
