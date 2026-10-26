//! 仅供 workspace 测试支持使用的最小注入合同。

pub use crate::config::RouteConfig;
pub use crate::connection::{GatewayProbe, from_webvpn_url, to_webvpn_url};
pub use crate::ports::{HttpMethod, HttpRequest, HttpResponse, HttpTransport};
pub use crate::session::{
    DualSessionMutation, DualSessionSnapshot, FileSessionStore, RouteSessionSnapshot,
    RouteSessions, SessionMutation, SessionSnapshot, SessionStore, StoredCookie,
    VersionedDualSession, VersionedSession,
};

/// 在合成配置目录中使用可注入传输和探测器，验证原子策略保存。
///
/// # Errors
///
/// 测试目录、配置或会话无法初始化时返回错误。
pub fn with_routing_in_config_directory<TDirect, TWebVpn, P>(
    direct: TDirect,
    webvpn: TWebVpn,
    directory: impl AsRef<std::path::Path>,
    probe: P,
) -> crate::error::Result<super::UbaaClient>
where
    TDirect: HttpTransport + 'static,
    TWebVpn: HttpTransport + 'static,
    P: GatewayProbe + 'static,
{
    let directory = directory.as_ref();
    let mut client = super::UbaaClient::with_routing(
        direct,
        webvpn,
        FileSessionStore::new(directory)?,
        RouteConfig::load(directory)?,
        probe,
    )?;
    client.config_dir = Some(directory.to_path_buf());
    Ok(client)
}
