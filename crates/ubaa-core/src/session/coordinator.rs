//! 客户端拥有的双路线会话协调器。

use std::sync::{Arc, Mutex};

use crate::domain::ConnectionMode;
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

use super::file_safety::session_error;
use super::file_store::FileSessionStore;
use super::ports::SessionStore;
use super::types::{
    DualSessionMutation, DualSessionSnapshot, RouteSessionSnapshot, SessionMutation,
    SessionSnapshot, VersionedSession,
};

/// 一个客户端拥有的完整双路线会话快照及版本号视图。
///
/// 两条路线适配器共享此协调器，使一条路线的变更对另一条路线可见，但不会重新加载并采用
/// 外部进程的修订。
#[derive(Clone)]
pub(crate) struct DualSessionCoordinator {
    state: Arc<Mutex<DualSessionState>>,
}

struct DualSessionState {
    store: FileSessionStore,
    snapshot: DualSessionSnapshot,
    revision: u64,
    direct_revision: u64,
    webvpn_revision: u64,
    conflicted: bool,
}

#[derive(Clone, Copy)]
pub(crate) struct DualRouteRevisions {
    pub(crate) direct: u64,
    pub(crate) webvpn: u64,
}

/// 由客户端拥有的双路线协调器支持的路线本地 `SessionStore` 适配器。
#[derive(Clone)]
pub(crate) struct CoordinatedRouteSessionStore {
    coordinator: DualSessionCoordinator,
    mode: ConnectionMode,
}

impl DualSessionCoordinator {
    pub(crate) fn new(store: FileSessionStore) -> Result<Self> {
        let current = store.load_dual_versioned()?;
        Ok(Self {
            state: Arc::new(Mutex::new(DualSessionState {
                store,
                snapshot: current
                    .snapshot
                    .unwrap_or_else(|| DualSessionSnapshot::new(None, None)),
                revision: current.revision,
                direct_revision: current.revision,
                webvpn_revision: current.revision,
                conflicted: false,
            })),
        })
    }

    pub(crate) fn route_store(&self, mode: ConnectionMode) -> CoordinatedRouteSessionStore {
        CoordinatedRouteSessionStore {
            coordinator: self.clone(),
            mode,
        }
    }

    pub(crate) fn active_routes(&self) -> Vec<ConnectionMode> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        [
            (
                ConnectionMode::Direct,
                state.snapshot.sessions.direct.is_some(),
            ),
            (
                ConnectionMode::WebVpn,
                state.snapshot.sessions.webvpn.is_some(),
            ),
        ]
        .into_iter()
        .filter_map(|(mode, active)| active.then_some(mode))
        .collect()
    }

    pub(crate) fn is_conflicted(&self) -> bool {
        self.state.lock().map_or(true, |state| state.conflicted)
    }

    pub(crate) fn conflict_error() -> UbaaError {
        dual_session_conflict()
    }

    pub(crate) fn is_revision_current(
        &self,
        mode: ConnectionMode,
        expected_revision: u64,
    ) -> Result<bool> {
        let mut state = self
            .state
            .lock()
            .map_err(|_| session_error("dual session coordinator is unavailable"))?;
        if state.conflicted {
            return Ok(false);
        }
        let current = state.store.load_dual_versioned()?;
        let route_revision = match mode {
            ConnectionMode::Direct => state.direct_revision,
            ConnectionMode::WebVpn => state.webvpn_revision,
        };
        if current.revision != state.revision || expected_revision != route_revision {
            // 只进入终态并丢弃内存快照，绝不采用外部快照继续写入。
            state.snapshot = DualSessionSnapshot::new(None, None);
            state.conflicted = true;
            return Ok(false);
        }
        Ok(true)
    }

    pub(crate) fn clear_both(&self) -> Result<DualRouteRevisions> {
        let mut state = self
            .state
            .lock()
            .map_err(|_| session_error("dual session coordinator is unavailable"))?;
        if state.conflicted {
            return Err(dual_session_conflict());
        }
        let next_direct = state
            .direct_revision
            .checked_add(1)
            .ok_or_else(|| session_error("session revision is exhausted"))?;
        let next_webvpn = state
            .webvpn_revision
            .checked_add(1)
            .ok_or_else(|| session_error("session revision is exhausted"))?;
        let mutation = match state.store.compare_exchange_dual(state.revision, None) {
            Ok(mutation) => mutation,
            Err(error) => {
                state.snapshot = DualSessionSnapshot::new(None, None);
                state.conflicted = true;
                return Err(error);
            }
        };
        match mutation {
            DualSessionMutation::Applied { revision } => {
                state.snapshot = DualSessionSnapshot::new(None, None);
                state.revision = revision;
                state.direct_revision = next_direct;
                state.webvpn_revision = next_webvpn;
                Ok(DualRouteRevisions {
                    direct: next_direct,
                    webvpn: next_webvpn,
                })
            }
            DualSessionMutation::Conflict => {
                state.snapshot = DualSessionSnapshot::new(None, None);
                state.conflicted = true;
                Err(dual_session_conflict())
            }
        }
    }
}

impl std::fmt::Debug for CoordinatedRouteSessionStore {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("CoordinatedRouteSessionStore")
            .field("mode", &self.mode)
            .finish_non_exhaustive()
    }
}

impl SessionStore for CoordinatedRouteSessionStore {
    fn load_versioned(&self) -> Result<VersionedSession> {
        let state = self
            .coordinator
            .state
            .lock()
            .map_err(|_| session_error("dual session coordinator is unavailable"))?;
        if state.conflicted {
            return Err(dual_session_conflict());
        }
        let snapshot = match self.mode {
            ConnectionMode::Direct => state.snapshot.sessions.direct.clone(),
            ConnectionMode::WebVpn => state.snapshot.sessions.webvpn.clone(),
        };
        let revision = match self.mode {
            ConnectionMode::Direct => state.direct_revision,
            ConnectionMode::WebVpn => state.webvpn_revision,
        };
        Ok(VersionedSession {
            revision,
            snapshot: snapshot.map(|slot| slot.into_legacy(self.mode)),
        })
    }

    fn compare_exchange(
        &self,
        expected_revision: u64,
        replacement: Option<&SessionSnapshot>,
    ) -> Result<SessionMutation> {
        let mut state = self
            .coordinator
            .state
            .lock()
            .map_err(|_| session_error("dual session coordinator is unavailable"))?;
        // 协调器冲突对当前客户端是终态。不要返回调用方可能误认为可以重试或触碰文件的第二个
        // `Conflict`。
        if state.conflicted {
            return Err(dual_session_conflict());
        }
        let route_revision = match self.mode {
            ConnectionMode::Direct => state.direct_revision,
            ConnectionMode::WebVpn => state.webvpn_revision,
        };
        if expected_revision != route_revision {
            state.snapshot = DualSessionSnapshot::new(None, None);
            state.conflicted = true;
            return Ok(SessionMutation::Conflict);
        }
        let next_route_revision = route_revision
            .checked_add(1)
            .ok_or_else(|| session_error("session revision is exhausted"))?;
        let mut candidate = state.snapshot.clone();
        let slot = replacement.map(RouteSessionSnapshot::from_legacy);
        match self.mode {
            ConnectionMode::Direct => candidate.sessions.direct = slot,
            ConnectionMode::WebVpn => candidate.sessions.webvpn = slot,
        }
        let replacement =
            if candidate.sessions.direct.is_none() && candidate.sessions.webvpn.is_none() {
                None
            } else {
                Some(&candidate)
            };
        let mutation = match state
            .store
            .compare_exchange_dual(state.revision, replacement)
        {
            Ok(mutation) => mutation,
            Err(error) => {
                state.snapshot = DualSessionSnapshot::new(None, None);
                state.conflicted = true;
                return Err(error);
            }
        };
        match mutation {
            DualSessionMutation::Applied { revision } => {
                state.snapshot = candidate;
                state.revision = revision;
                match self.mode {
                    ConnectionMode::Direct => state.direct_revision = next_route_revision,
                    ConnectionMode::WebVpn => state.webvpn_revision = next_route_revision,
                }
                Ok(SessionMutation::Applied {
                    revision: next_route_revision,
                })
            }
            DualSessionMutation::Conflict => {
                state.snapshot = DualSessionSnapshot::new(None, None);
                state.conflicted = true;
                Ok(SessionMutation::Conflict)
            }
        }
    }

    fn is_revision_current(&self, expected_revision: u64) -> Result<bool> {
        self.coordinator
            .is_revision_current(self.mode, expected_revision)
    }
}

fn dual_session_conflict() -> UbaaError {
    UbaaError::new(
        ErrorCode::InternalError,
        ErrorKind::Internal,
        true,
        "local session changed in another process",
    )
}

#[cfg(test)]
mod tests {
    use super::super::cookies::StoredCookie;
    use super::*;

    #[test]
    fn coordinated_route_store_rejects_a_stale_same_route_revision() {
        let root = std::env::temp_dir().join(format!(
            "ubaa-coordinated-route-cas-{}-{:?}",
            std::process::id(),
            std::thread::current().id()
        ));
        let _ = std::fs::remove_dir_all(&root);
        let file_store = FileSessionStore::new(&root).unwrap();
        let coordinator =
            DualSessionCoordinator::new(file_store.clone()).expect("coordinator opens");
        let direct = coordinator.route_store(ConnectionMode::Direct);
        let loaded = direct.load_versioned().unwrap();
        let snapshot = SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: vec![StoredCookie::fixture("SESSION", "fixture-cookie")],
            authenticated_at: 1,
            last_activity: 1,
        };

        assert!(matches!(
            direct
                .compare_exchange(loaded.revision, Some(&snapshot))
                .unwrap(),
            SessionMutation::Applied { .. }
        ));
        assert_eq!(
            direct.compare_exchange(loaded.revision, None).unwrap(),
            SessionMutation::Conflict
        );
        assert!(coordinator.is_conflicted());
        let persisted = std::fs::read(file_store.path()).unwrap();
        std::fs::write(root.join(".session.lock"), b"invalid\n").unwrap();
        let error = direct.load_versioned().unwrap_err();
        assert_eq!(error.message, "local session changed in another process");
        let error = direct
            .compare_exchange(loaded.revision, None)
            .expect_err("a terminal coordinator must reject later CAS calls");
        assert_eq!(error.message, "local session changed in another process");
        assert_eq!(std::fs::read(file_store.path()).unwrap(), persisted);
        let persisted: DualSessionSnapshot = serde_json::from_slice(&persisted).unwrap();
        assert_eq!(
            persisted
                .sessions
                .direct
                .map(|slot| slot.into_legacy(ConnectionMode::Direct)),
            Some(snapshot)
        );
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn aggregate_clear_returns_route_revisions_that_allow_safe_client_reuse() {
        let root = std::env::temp_dir().join(format!(
            "ubaa-coordinated-clear-revisions-{}-{:?}",
            std::process::id(),
            std::thread::current().id()
        ));
        let _ = std::fs::remove_dir_all(&root);
        let coordinator = DualSessionCoordinator::new(FileSessionStore::new(&root).unwrap())
            .expect("coordinator opens");
        let direct = coordinator.route_store(ConnectionMode::Direct);
        let before_clear = direct.load_versioned().unwrap().revision;

        let revisions = coordinator.clear_both().unwrap();
        let snapshot = SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: vec![StoredCookie::fixture("SESSION", "fixture-cookie")],
            authenticated_at: 1,
            last_activity: 1,
        };

        assert!(revisions.direct > before_clear);
        assert!(matches!(
            direct
                .compare_exchange(revisions.direct, Some(&snapshot))
                .unwrap(),
            SessionMutation::Applied { .. }
        ));
        let _ = std::fs::remove_dir_all(root);
    }

    #[cfg(unix)]
    #[test]
    fn uncertain_file_cas_error_makes_the_coordinator_terminal() {
        use std::os::unix::fs::PermissionsExt;

        let root = std::env::temp_dir().join(format!(
            "ubaa-coordinated-uncertain-cas-{}-{:?}",
            std::process::id(),
            std::thread::current().id()
        ));
        let _ = std::fs::remove_dir_all(&root);
        let coordinator = DualSessionCoordinator::new(FileSessionStore::new(&root).unwrap())
            .expect("coordinator opens");
        let direct = coordinator.route_store(ConnectionMode::Direct);
        let loaded = direct.load_versioned().unwrap();
        let snapshot = SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: vec![StoredCookie::fixture("SESSION", "fixture-cookie")],
            authenticated_at: 1,
            last_activity: 1,
        };
        std::fs::set_permissions(&root, std::fs::Permissions::from_mode(0o500)).unwrap();

        let result = direct.compare_exchange(loaded.revision, Some(&snapshot));

        std::fs::set_permissions(&root, std::fs::Permissions::from_mode(0o700)).unwrap();
        assert!(result.is_err());
        assert!(coordinator.is_conflicted());
        assert!(direct.load_versioned().is_err());
        let _ = std::fs::remove_dir_all(root);
    }
}
