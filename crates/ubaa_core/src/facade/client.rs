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
use crate::session::business_cache::Invalidation;
use crate::session::{DualSessionCoordinator, FileSessionStore};

pub struct UbaaClient {
    pub(super) raw_diagnostics: super::RawDiagnostics,
    pub(super) network: super::ClientNetworkControl,
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
    pub(super) session_conflict_seen: bool,
    pub(super) business_sessions: Arc<crate::session::business_cache::BusinessSessionCache>,
    pub(super) interactive: super::interactive_auth::state::InteractiveAuthState,
    pub(super) bhpan: Box<super::bhpan::state::BhpanState>,
    pub(super) cloud_print: Option<Box<ClientRuntime>>,
}

impl UbaaClient {
    /// 是否存在可尝试恢复的本机会话。不验证会话，也不访问网络。
    #[must_use]
    pub fn has_saved_session(&self) -> bool {
        self.direct_runtime.has_local_session() || self.webvpn_runtime.has_local_session()
    }

    #[cfg(all(test, feature = "test-contract"))]
    pub(crate) fn business_cache_for_test(
        &self,
    ) -> Arc<crate::session::business_cache::BusinessSessionCache> {
        Arc::clone(&self.business_sessions)
    }

    /// 返回仅供用户主动导出的原始响应缓冲。
    #[must_use]
    pub fn raw_diagnostics(&self) -> super::RawDiagnostics {
        self.raw_diagnostics.clone()
    }

    /// 网络检测和只读取消不占用业务客户端锁。
    #[must_use]
    pub fn network_control(&self) -> super::ClientNetworkControl {
        self.network.clone()
    }
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
            self.cloud_print = None;
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
        let mut reopened = Self::open_with_diagnostics(directory, self.raw_diagnostics.clone())?;
        reopened
            .business_sessions
            .inherit_revocation_failure(&self.business_sessions);
        reopened.probe = self.probe.clone();
        reopened.network = self.network.clone();
        reopened.direct_runtime.consumer_closed = self.direct_runtime.consumer_closed.clone();
        reopened.webvpn_runtime.consumer_closed = self.webvpn_runtime.consumer_closed.clone();
        reopened.bind_shared_account(self.shared_account_guard());
        if let Some(service) = &self.direct_runtime.app_service {
            reopened.bind_app_service(service.clone());
        }
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
        Self::open_with_diagnostics(config_dir.as_ref(), super::RawDiagnostics::default())
    }

    fn open_with_diagnostics(
        config_dir: &Path,
        diagnostics: super::RawDiagnostics,
    ) -> Result<Self> {
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
            diagnostics,
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
            super::RawDiagnostics::default(),
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
        Self::build_with_routing(
            direct_transport,
            webvpn_transport,
            store,
            config,
            probe,
            super::RawDiagnostics::default(),
        )
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
            super::RawDiagnostics::default(),
        )
    }

    fn build_with_routing<TDirect, TWebVpn, P>(
        direct_transport: TDirect,
        webvpn_transport: TWebVpn,
        store: FileSessionStore,
        config: RouteConfig,
        probe: P,
        diagnostics: super::RawDiagnostics,
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
            diagnostics,
        )
    }

    fn build_with_probe<TDirect, TWebVpn>(
        direct_transport: TDirect,
        webvpn_transport: TWebVpn,
        store: FileSessionStore,
        config: RouteConfig,
        probe: CachingGatewayProbe<Box<dyn GatewayProbe>>,
        diagnostics: super::RawDiagnostics,
    ) -> Result<Self>
    where
        TDirect: HttpTransport + 'static,
        TWebVpn: HttpTransport + 'static,
    {
        let business_sessions = Arc::new(
            crate::session::business_cache::BusinessSessionCache::new(&store),
        );
        let sessions = DualSessionCoordinator::new(store)?.with_business_cache(&business_sessions);
        let probe = Arc::new(probe);
        let mut client = Self {
            raw_diagnostics: diagnostics.clone(),
            network: super::ClientNetworkControl::new(probe.clone()),
            read_recovery_batch: super::required_recovery::ReadRecoveryBatch::default(),
            domain_routes: Arc::default(),
            config_dir: None,
            verified_login: None,
            verified_login_generations: None,
            route_generation: 0,
            config,
            probe,
            direct_runtime: ClientRuntime::new_coordinated(
                ConnectionMode::Direct,
                crate::ports::diagnostics::RecordingTransport {
                    inner: direct_transport,
                    diagnostics: diagnostics.clone(),
                    route: ConnectionMode::Direct,
                },
                &sessions,
            )?,
            webvpn_runtime: ClientRuntime::new_coordinated(
                ConnectionMode::WebVpn,
                crate::ports::diagnostics::RecordingTransport {
                    inner: webvpn_transport,
                    diagnostics,
                    route: ConnectionMode::WebVpn,
                },
                &sessions,
            )?,
            direct_auth: AuthWorkflow::default(),
            webvpn_auth: AuthWorkflow::default(),
            sessions,
            session_conflict_seen: false,
            business_sessions,
            interactive: super::interactive_auth::state::InteractiveAuthState::default(),
            bhpan: Box::default(),
            cloud_print: None,
        };
        client.direct_runtime.business_sessions = Some(Arc::clone(&client.business_sessions));
        client.webvpn_runtime.business_sessions = Some(Arc::clone(&client.business_sessions));
        Ok(client)
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
        let policy_changed = !self.config.has_same_effective_routes(&replacement);
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
        self.cloud_print = None;
        self.config = replacement;
        if policy_changed
            && self
                .business_sessions
                .invalidate(Invalidation::RevokeAll)
                .is_err()
        {
            tracing::warn!("全量撤销业务会话缓存失败");
        }
        self.clear_interactive_context();
        Ok(())
    }
}
