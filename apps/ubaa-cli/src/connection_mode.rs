use clap::ValueEnum;
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
