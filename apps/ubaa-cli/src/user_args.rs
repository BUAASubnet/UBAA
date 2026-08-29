use clap::{Args, Subcommand};

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
