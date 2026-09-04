//! 聚合客户端字段、构造与全局配置。

use std::path::{Path, PathBuf};
#[cfg(feature = "test-contract")]
use std::time::Duration;

use crate::auth::AuthWorkflow;
use crate::config::RouteConfig;
use crate::connection::{CachingGatewayProbe, GatewayProbe, SystemGatewayProbe};
use crate::domain::{ConnectionMode, RoutePolicy};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::{HttpTransport, ReqwestTransport};
use crate::runtime::ClientRuntime;
use crate::session::{DualSessionCoordinator, FileSessionStore};

pub struct UbaaClient {
    pub(super) config_dir: Option<PathBuf>,
    pub(super) config: RouteConfig,
    pub(super) probe: Box<dyn GatewayProbe>,
    pub(super) direct_runtime: ClientRuntime,
    pub(super) webvpn_runtime: ClientRuntime,
    pub(super) direct_auth: AuthWorkflow,
    pub(super) webvpn_auth: AuthWorkflow,
    pub(super) sessions: DualSessionCoordinator,
}

impl UbaaClient {
    /// 基于一个双槽位会话文件打开生产 Direct 和 `WebVPN` 运行时。
    ///
    /// # Errors
    ///
    /// 路线配置、HTTP 传输、会话存储或任一路线运行时无法初始化时返回错误。
    pub fn open(config_dir: impl AsRef<Path>) -> Result<Self> {
        let config_dir = config_dir.as_ref();
        let config = RouteConfig::load(config_dir)?;
        let mut client = Self::build_with_routing(
            ReqwestTransport::new()?,
            ReqwestTransport::new()?,
            FileSessionStore::new(config_dir)?,
            config,
            SystemGatewayProbe,
        )?;
        client.config_dir = Some(config_dir.to_path_buf());
        Ok(client)
    }

    /// 使用可注入传输和默认路由构造聚合客户端。
    ///
    /// # Errors
    ///
    /// 双路线会话协调器或任一路线运行时无法初始化时返回错误。
    #[cfg(feature = "test-contract")]
    #[doc(hidden)]
    pub fn with_transports<TDirect, TWebVpn>(
        direct_transport: TDirect,
        webvpn_transport: TWebVpn,
        store: FileSessionStore,
    ) -> Result<Self>
    where
        TDirect: HttpTransport + 'static,
        TWebVpn: HttpTransport + 'static,
    {
        Self::build_with_routing(
            direct_transport,
            webvpn_transport,
            store,
            RouteConfig::default(),
            SystemGatewayProbe,
        )
    }

    /// 使用可注入传输和路由输入构造聚合客户端。
    ///
    /// # Errors
    ///
    /// 双路线会话协调器或任一路线运行时无法初始化时返回错误。
    #[cfg(feature = "test-contract")]
    #[doc(hidden)]
    pub fn with_routing<TDirect, TWebVpn, P>(
        direct_transport: TDirect,
        webvpn_transport: TWebVpn,
        store: FileSessionStore,
        config: RouteConfig,
        probe: P,
    ) -> Result<Self>
    where
        TDirect: HttpTransport + 'static,
        TWebVpn: HttpTransport + 'static,
        P: GatewayProbe + 'static,
    {
        Self::build_with_routing(direct_transport, webvpn_transport, store, config, probe)
    }

    /// 使用可注入传输、路由输入与探测缓存 TTL 构造测试客户端。
    ///
    /// # Errors
    ///
    /// 双路线会话协调器或任一路线运行时无法初始化时返回错误。
    #[cfg(feature = "test-contract")]
    #[doc(hidden)]
    pub fn with_routing_and_probe_ttl<TDirect, TWebVpn, P>(
        direct_transport: TDirect,
        webvpn_transport: TWebVpn,
        store: FileSessionStore,
        config: RouteConfig,
        probe: P,
        probe_ttl: Duration,
    ) -> Result<Self>
    where
        TDirect: HttpTransport + 'static,
        TWebVpn: HttpTransport + 'static,
        P: GatewayProbe + 'static,
    {
        Self::build_with_probe(
            direct_transport,
            webvpn_transport,
            store,
            config,
            Box::new(CachingGatewayProbe::new(probe, probe_ttl)),
        )
    }

    fn build_with_routing<TDirect, TWebVpn, P>(
        direct_transport: TDirect,
        webvpn_transport: TWebVpn,
        store: FileSessionStore,
        config: RouteConfig,
        probe: P,
    ) -> Result<Self>
    where
        TDirect: HttpTransport + 'static,
        TWebVpn: HttpTransport + 'static,
        P: GatewayProbe + 'static,
    {
        Self::build_with_probe(
            direct_transport,
            webvpn_transport,
            store,
            config,
            Box::new(CachingGatewayProbe::with_default_ttl(probe)),
        )
    }

    fn build_with_probe<TDirect, TWebVpn>(
        direct_transport: TDirect,
        webvpn_transport: TWebVpn,
        store: FileSessionStore,
        config: RouteConfig,
        probe: Box<dyn GatewayProbe>,
    ) -> Result<Self>
    where
        TDirect: HttpTransport + 'static,
        TWebVpn: HttpTransport + 'static,
    {
        let sessions = DualSessionCoordinator::new(store)?;
        let direct_store = sessions.route_store(ConnectionMode::Direct);
        let webvpn_store = sessions.route_store(ConnectionMode::WebVpn);
        Ok(Self {
            config_dir: None,
            config,
            probe,
            direct_runtime: ClientRuntime::new(
                ConnectionMode::Direct,
                direct_transport,
                direct_store,
            )?,
            webvpn_runtime: ClientRuntime::new(
                ConnectionMode::WebVpn,
                webvpn_transport,
                webvpn_store,
            )?,
            direct_auth: AuthWorkflow::default(),
            webvpn_auth: AuthWorkflow::default(),
            sessions,
        })
    }

    /// 返回当前客户端拥有的路线槽位。
    #[must_use]
    pub fn active_routes(&self) -> Vec<ConnectionMode> {
        self.sessions.active_routes()
    }

    /// 返回聚合认证操作使用的配置策略。
    #[must_use]
    pub const fn default_route_policy(&self) -> RoutePolicy {
        self.config.default
    }

    /// 原子保存新的全局路线策略并清除功能覆盖项。
    ///
    /// # Errors
    ///
    /// 客户端没有配置目录或替换后的路线配置无法持久化时返回错误。
    pub fn set_default_route_policy(&mut self, policy: RoutePolicy) -> Result<()> {
        let Some(config_dir) = self.config_dir.as_ref() else {
            return Err(UbaaError::new(
                ErrorCode::InternalError,
                ErrorKind::Internal,
                false,
                "route configuration directory is unavailable",
            ));
        };
        let mut replacement = self.config.clone();
        replacement.replace_default_policy(policy);
        replacement.save(config_dir)?;
        self.config = replacement;
        Ok(())
    }
}
