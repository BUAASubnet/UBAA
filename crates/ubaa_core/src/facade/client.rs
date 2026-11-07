//! 聚合客户端字段、构造与全局配置。

use std::path::{Path, PathBuf};
use std::sync::Arc;
#[cfg(feature = "test-contract")]
use std::time::Duration;

use crate::auth::AuthWorkflow;
use crate::config::RouteConfig;
use crate::connection::{CachingGatewayProbe, GatewayProbe, SystemGatewayProbe};
use crate::domain::{ConnectionMode, RoutePolicy};
use crate::error::{ErrorCode, ErrorKind, InitializationFailure, Result, UbaaError};
use crate::ports::{HttpTransport, ReqwestTransport};
use crate::runtime::ClientRuntime;
use crate::session::{DualSessionCoordinator, FileSessionStore};

pub struct UbaaClient {
    pub(super) read_recovery_batch: super::required_recovery::ReadRecoveryBatch,
    pub(super) domain_routes: Arc<std::sync::Mutex<super::routing::domains::DomainRoutes>>,
    pub(super) config_dir: Option<PathBuf>,
    pub(super) verified_login: Option<(String, uuid::Uuid, bool, std::time::Instant)>,
    pub(super) config: RouteConfig,
    pub(super) verified_login_generations: Option<(uuid::Uuid, uuid::Uuid)>,
    pub(super) route_generation: u64,
    pub(super) probe: Arc<CachingGatewayProbe<Box<dyn GatewayProbe>>>,
    pub(super) direct_runtime: ClientRuntime,
    pub(super) webvpn_runtime: ClientRuntime,
    pub(super) direct_auth: AuthWorkflow,
    pub(super) webvpn_auth: AuthWorkflow,
    pub(super) sessions: DualSessionCoordinator,
    pub(super) interactive: super::interactive_auth::state::InteractiveAuthState,
    pub(super) bhpan: Box<super::bhpan::state::BhpanState>,
}

impl UbaaClient {
    /// 本客户端及其派生任务的本进程关闭控制，不注销共享账号。
    #[must_use]
    pub fn close_control(&self) -> super::ClientCloseControl {
        super::ClientCloseControl {
            direct: self.direct_runtime.consumer_closed.clone(),
            webvpn: self.webvpn_runtime.consumer_closed.clone(),
        }
    }

    /// 当前固定共享归属，供受限退出在同一客户端锁内临时替换并恢复。
    #[must_use]
    pub fn shared_account_guard(&self) -> Option<super::SharedAccountGuard> {
        self.direct_runtime.shared_account.clone()
    }
    /// 绑定已捕获的本机撤销版本，不采用或恢复新会话。
    pub fn bind_shared_account(&mut self, guard: Option<super::SharedAccountGuard>) {
        let same = match (&self.direct_runtime.shared_account, &guard) {
            (Some(previous), Some(next)) => previous.same_scope(next),
            (None, None) => true,
            _ => false,
        };
        if !same {
            self.invalidate_read_recovery_batch();
        }
        self.direct_runtime.shared_account.clone_from(&guard);
        self.webvpn_runtime.shared_account = guard;
    }

    /// 在路线配置更新后重开，保留本消费者的关闭标记与固定共享归属。
    ///
    /// # Errors
    /// 客户端没有持久目录、已关闭、共享归属失效或重开失败时拒绝。
    pub fn reopen_for_route_policy(&self) -> Result<Self> {
        let directory = self.config_dir.as_ref().ok_or_else(|| {
            UbaaError::new(
                ErrorCode::InvalidInput,
                ErrorKind::Input,
                false,
                "客户端没有持久配置目录",
            )
        })?;
        let mut reopened = Self::open(directory)?;
        reopened.direct_runtime.consumer_closed = self.direct_runtime.consumer_closed.clone();
        reopened.webvpn_runtime.consumer_closed = self.webvpn_runtime.consumer_closed.clone();
        reopened.bind_shared_account(self.shared_account_guard());
        reopened.direct_runtime.ensure_session_revision()?;
        reopened.webvpn_runtime.ensure_session_revision()?;
        Ok(reopened)
    }

    /// 基于一个双槽位会话文件打开生产 Direct 和 `WebVPN` 运行时。
    ///
    /// # Errors
    ///
    /// 路线配置、HTTP 传输、会话存储或任一路线运行时无法初始化时返回错误。
    pub fn open(config_dir: impl AsRef<Path>) -> Result<Self> {
        let config_dir = config_dir.as_ref();
        let config = RouteConfig::load(config_dir).map_err(|error| {
            error.with_initialization_failure(InitializationFailure::Configuration)
        })?;
        let transport = || {
            ReqwestTransport::new().map_err(|error| {
                error.with_initialization_failure(InitializationFailure::ComponentUnavailable)
            })
        };
        let mut client = Self::build_with_routing(
            transport()?,
            transport()?,
            FileSessionStore::new(config_dir).map_err(|error| {
                error.with_initialization_failure(InitializationFailure::Session)
            })?,
            config,
            SystemGatewayProbe,
        )
        .map_err(|error| error.with_initialization_failure(InitializationFailure::Session))?;
        client.config_dir = Some(config_dir.to_path_buf());
        client.domain_routes = Arc::new(std::sync::Mutex::new(
            super::routing::domains::DomainRoutes::load(config_dir),
        ));
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
            CachingGatewayProbe::new(Box::new(probe), probe_ttl),
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
            CachingGatewayProbe::with_default_ttl(Box::new(probe)),
        )
    }

    fn build_with_probe<TDirect, TWebVpn>(
        direct_transport: TDirect,
        webvpn_transport: TWebVpn,
        store: FileSessionStore,
        config: RouteConfig,
        probe: CachingGatewayProbe<Box<dyn GatewayProbe>>,
    ) -> Result<Self>
    where
        TDirect: HttpTransport + 'static,
        TWebVpn: HttpTransport + 'static,
    {
        let sessions = DualSessionCoordinator::new(store)?;
        let direct_store = sessions.route_store(ConnectionMode::Direct);
        let webvpn_store = sessions.route_store(ConnectionMode::WebVpn);
        Ok(Self {
            read_recovery_batch: super::required_recovery::ReadRecoveryBatch::default(),
            domain_routes: Arc::default(),
            config_dir: None,
            verified_login: None,
            verified_login_generations: None,
            route_generation: 0,
            config,
            probe: Arc::new(probe),
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
            interactive: super::interactive_auth::state::InteractiveAuthState::default(),
            bhpan: Box::default(),
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
        self.direct_runtime.ensure_primary_client()?;
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
        let generation = self.route_generation.checked_add(1).ok_or_else(|| {
            UbaaError::new(
                ErrorCode::InternalError,
                ErrorKind::Internal,
                false,
                "路线代次已耗尽",
            )
        })?;
        replacement.save(config_dir)?;
        self.route_generation = generation;
        *self.bhpan = super::bhpan::state::BhpanState::default();
        self.config = replacement;
        self.clear_interactive_context();
        Ok(())
    }
}
