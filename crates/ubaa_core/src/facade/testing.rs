//! 仅供 workspace 测试支持使用的最小注入合同。
mod sso;
pub use sso::{sso_fixture_response, sso_fixture_ticket};

pub use crate::config::RouteConfig;
pub use crate::connection::{GatewayProbe, from_webvpn_url, to_webvpn_url};
pub use crate::ports::{
    HttpFileRange, HttpMethod, HttpRequest, HttpResponse, HttpTransferObserver, HttpTransport,
    StreamSink,
};
pub use crate::session::{
    DualSessionMutation, DualSessionSnapshot, FileSessionStore, RouteSessionSnapshot,
    RouteSessions, SessionMutation, SessionSnapshot, SessionStore, StoredCookie,
    VersionedDualSession, VersionedSession,
};

/// 提供三种带进程内原因的错误，供宿主验证错误分类。
#[must_use]
pub fn client_lifecycle_errors() -> [crate::error::UbaaError; 3] {
    use crate::error::UbaaError;
    [
        UbaaError::client_closed(),
        UbaaError::captcha_required(),
        UbaaError::shared_account_conflict(),
    ]
}

/// 为两条独立认证流程注入合成验证码识别结果，不读取真实图像或模型。
pub fn set_captcha_recognizer(
    client: &mut super::UbaaClient,
    recognize: impl Fn(&crate::domain::CaptchaFrame) -> Option<String> + Send + Sync + 'static,
) {
    let recognize = std::sync::Arc::new(recognize);
    client.direct_auth.captcha_recognizer = Some(recognize.clone());
    client.webvpn_auth.captcha_recognizer = Some(recognize);
}

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
    client.domain_routes = std::sync::Arc::new(std::sync::Mutex::new(
        super::routing::domains::DomainRoutes::load(directory),
    ));
    Ok(client)
}
