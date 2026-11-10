//! 构建配置与仅能关闭遥测的运行时条件。

use super::types::{Channel, Platform, valid_app_version};
use url::{Host, Url};

#[derive(Clone)]
pub struct AppServiceConfig(Option<AvailableConfig>);

#[derive(Clone)]
pub(super) struct AvailableConfig {
    pub(super) url: Url,
    pub(super) channel: Channel,
    pub(super) version: String,
    pub(super) platform: Platform,
}

impl AppServiceConfig {
    /// 使用宿主构建配置及安装包版本。任一值不合法时完全停用应用服务。
    #[must_use]
    pub fn from_build(
        service_url: Option<&str>,
        channel: Option<&str>,
        version: Option<&str>,
        platform: Platform,
        release: bool,
    ) -> Self {
        Self((|| {
            let url = Url::parse(service_url?).ok()?;
            let channel = Channel::parse(channel?)?;
            let version = version?.to_owned();
            if !valid_app_version(&version) || !valid_endpoint(&url, release) {
                return None;
            }
            Some(AvailableConfig {
                url,
                channel,
                version,
                platform,
            })
        })())
    }

    pub(super) fn available(&self) -> Option<&AvailableConfig> {
        self.0.as_ref()
    }
}

fn valid_endpoint(url: &Url, release: bool) -> bool {
    if !matches!(url.scheme(), "https" | "http")
        || !url.username().is_empty()
        || url.password().is_some()
        || url.query().is_some()
        || url.fragment().is_some()
    {
        return false;
    }
    let domain = match url.host() {
        Some(Host::Domain(domain)) => Some(domain.trim_end_matches('.')),
        _ => None,
    };
    if release {
        return url.scheme() == "https"
            && domain.is_some_and(|domain| {
                domain.contains('.')
                    && domain != "workers.dev"
                    && !domain.ends_with(".workers.dev")
                    && !domain.ends_with(".localhost")
            });
    }
    match url.host() {
        Some(Host::Ipv4(ip)) => ip.is_loopback(),
        Some(Host::Ipv6(ip)) => ip.is_loopback(),
        Some(Host::Domain(_)) => domain == Some("localhost"),
        None => false,
    }
}

pub(super) fn telemetry_hard_closed() -> bool {
    std::env::var_os("UBAA_TELEMETRY").is_some_and(|value| value == "0")
        || std::env::var_os("CI").is_some_and(|value| !value.is_empty())
}
