//! 日程只组合公开云盘 facade，版本与 HTTP 协议继续由云盘维护。
mod remote;
mod scratch;
#[cfg(all(test, feature = "test-contract"))]
mod tests;
use crate::{
    agenda::{
        AgendaStore,
        sync::coordinator::{Committed, SyncCoordinator},
    },
    cache::CacheError,
    config::FeatureRouteConfig,
    connection::{NetworkState, resolve_route_from_network},
    domain::{ConnectionMode, RoutePolicy, bhpan::BhpanFileVersion},
    facade::{AgendaSyncAction, AgendaSyncError, AgendaSyncReport, AgendaTime, UbaaClient},
};
use std::path::PathBuf;

#[derive(Clone, Eq, PartialEq)]
struct Binding {
    authentication: uuid::Uuid,
    route: u64,
    lifecycle: u64,
}

impl Binding {
    fn capture(client: &UbaaClient) -> Self {
        Self {
            authentication: client.direct_runtime.authentication_generation(),
            route: client.route_generation,
            lifecycle: client.direct_runtime.feature_state().lifecycle_generation(),
        }
    }
}

/// 首次创建确认绑定当时的客户端和可用的云盘实际路线。
pub struct AgendaSyncScope {
    binding: Binding,
    mode: ConnectionMode,
}

tokio::task_local! {
    static CONFIRMED_AGENDA_ROUTE: ConnectionMode;
}

pub(super) fn confirmed_agenda_route() -> Option<ConnectionMode> {
    CONFIRMED_AGENDA_ROUTE.try_with(|mode| *mode).ok()
}

impl UbaaClient {
    /// 只使用固定策略或尚未过期的 Auto 观察，不发起探测或云盘请求。
    /// # Errors
    /// 当前路线无法确认或不支持创建时，调用方应先重新拉取。
    pub fn agenda_sync_scope(&self) -> Result<AgendaSyncScope, AgendaSyncError> {
        let policy = self.default_route_policy();
        let network = if policy == RoutePolicy::Auto {
            self.probe.cached_network().ok_or(CacheError::Superseded)?
        } else {
            NetworkState::Unknown
        };
        let mode =
            resolve_route_from_network(policy, FeatureRouteConfig::SAFE_DEFAULT, network).mode;
        if mode != ConnectionMode::Direct {
            return Err(CacheError::Superseded.into());
        }
        Ok(AgendaSyncScope {
            binding: Binding::capture(self),
            mode,
        })
    }
}

/// GUI 与 App 命令共用的同步作业。每次作业从本机库恢复待核对尝试。
pub struct AgendaSyncService {
    store: AgendaStore,
    scratch_root: PathBuf,
    committed: Option<Committed<BhpanFileVersion>>,
    binding: Option<Binding>,
}
impl AgendaSyncService {
    #[must_use]
    pub fn new(store: AgendaStore, scratch_root: PathBuf) -> Self {
        Self {
            store,
            scratch_root,
            committed: None,
            binding: None,
        }
    }
    /// 在创建作业的各次云盘路线解析中核对原确认路线。
    /// # Errors
    /// 原客户端、路线或会话已失效，或者同步失败时拒绝。
    pub async fn run_confirmed(
        &mut self,
        client: &mut UbaaClient,
        scope: &AgendaSyncScope,
        now: AgendaTime,
    ) -> Result<AgendaSyncReport, AgendaSyncError> {
        let current = client.agenda_sync_scope()?;
        if scope.binding != current.binding || scope.mode != current.mode {
            return Err(CacheError::Superseded.into());
        }
        let result = CONFIRMED_AGENDA_ROUTE
            .scope(
                scope.mode,
                self.run(client, AgendaSyncAction::CreateConfirmed, now),
            )
            .await;
        match result {
            Err(AgendaSyncError::Remote(error)) if error.is_agenda_creation_route_changed() => {
                Err(CacheError::Superseded.into())
            }
            result => result,
        }
    }
    /// 一次触发只尝试一次上传。未知结果在后续触发时只做当前版本核对。
    ///
    /// # Errors
    /// 保留本机存储和云盘的原错误。账号、路线或客户端生命期变化后拒绝旧作业。
    pub async fn run(
        &mut self,
        client: &mut UbaaClient,
        action: AgendaSyncAction,
        now: AgendaTime,
    ) -> Result<AgendaSyncReport, AgendaSyncError> {
        client
            .direct_runtime
            .ensure_primary_client()
            .map_err(AgendaSyncError::Remote)?;
        let binding = Binding::capture(client);
        if !self
            .store
            .matches_sync_guard(client.shared_account_guard().as_ref())
        {
            return Err(crate::cache::CacheError::Superseded.into());
        }
        if action == AgendaSyncAction::CreateConfirmed {
            client.agenda_sync_scope()?;
            // 明确确认已进入当前客户端和账号作用域，网络失败也保留用户许可。
            self.store.enable_sync()?;
        }
        if self.binding.as_ref().is_some_and(|old| old != &binding) {
            self.committed = None;
        }
        self.binding = Some(binding.clone());
        let mut coordinator = SyncCoordinator::new(
            self.store.clone(),
            remote::BhpanRemote::new(client, binding, &self.scratch_root),
        );
        coordinator.committed = self.committed.take();
        let result = coordinator.run(action, now).await;
        self.committed = coordinator.committed;
        result
    }
}
