//! Cookie jar and restricted on-disk session persistence.
#![allow(clippy::missing_errors_doc, clippy::needless_continue)]

use std::fs::{self, File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use url::Url;

use crate::domain::ConnectionMode;
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::HttpResponse;

const MAX_SESSION_FILE_BYTES: usize = 1024 * 1024;
const MAX_TEMP_FILE_ATTEMPTS: usize = 128;
const REVISION_FILE_BYTES: usize = 17;
static NEXT_TEMP_FILE: AtomicU64 = AtomicU64::new(0);

/// Cookie attributes retained for safe request filtering and persistence.
#[derive(Clone, Deserialize, Eq, PartialEq, Serialize)]
pub struct StoredCookie {
    /// Cookie name.
    pub name: String,
    /// Cookie value; this is session material and is never logged.
    pub value: String,
    /// Effective domain.
    pub domain: String,
    /// Whether the cookie was host-only.
    pub host_only: bool,
    /// Effective path.
    pub path: String,
    /// Secure-only flag.
    pub secure: bool,
    /// Absolute expiration timestamp in Unix seconds.
    pub expires_at: Option<i64>,
    /// Creation timestamp in Unix seconds, used with Max-Age.
    pub created_at: i64,
    /// Max-Age in seconds when supplied.
    pub max_age: Option<i64>,
}

impl std::fmt::Debug for StoredCookie {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("StoredCookie")
            .field("name", &"[REDACTED]")
            .field("value", &"[REDACTED]")
            .field("domain", &"[REDACTED]")
            .field("host_only", &self.host_only)
            .field("path", &"[REDACTED]")
            .field("secure", &self.secure)
            .field("expires_at", &self.expires_at)
            .field("created_at", &self.created_at)
            .field("max_age", &self.max_age)
            .finish()
    }
}

impl StoredCookie {
    /// Construct a cookie fixture for deterministic tests.
    pub fn fixture(name: impl Into<String>, value: impl Into<String>) -> Self {
        Self {
            name: name.into(),
            value: value.into(),
            domain: "sso.buaa.edu.cn".into(),
            host_only: true,
            path: "/".into(),
            secure: true,
            expires_at: None,
            created_at: 1_000,
            max_age: None,
        }
    }
}

/// In-memory Cookie jar with RFC-inspired domain/path/expiry filtering.
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct CookieJar {
    cookies: Vec<StoredCookie>,
}

impl CookieJar {
    /// Store all response `Set-Cookie` values for a request URL.
    ///
    /// # Errors
    ///
    /// Returns an internal session error for malformed request URLs, clock values, or cookies.
    pub fn store_response(
        &mut self,
        response: &HttpResponse,
        request_url: &str,
        now: SystemTime,
    ) -> Result<()> {
        let url =
            Url::parse(request_url).map_err(|_| session_error("invalid Cookie request URL"))?;
        let now_seconds = unix_seconds(now)?;
        for raw in header_values(&response.headers, "set-cookie") {
            let Some(cookie) = parse_cookie(raw, &url, now_seconds)? else {
                continue;
            };
            self.cookies.retain(|existing| {
                !(existing.name == cookie.name
                    && existing.domain == cookie.domain
                    && existing.path == cookie.path)
            });
            if cookie.max_age.is_none_or(|age| age > 0)
                && cookie
                    .expires_at
                    .is_none_or(|expires| expires > now_seconds)
            {
                self.cookies.push(cookie);
            }
        }
        self.purge_expired(now_seconds);
        Ok(())
    }

    /// Build the filtered Cookie request header for a URL.
    ///
    /// # Errors
    ///
    /// Returns an internal session error for a malformed URL or clock value.
    pub fn cookie_header(&mut self, request_url: &str, now: SystemTime) -> Result<String> {
        let url = Url::parse(request_url).map_err(|_| session_error("invalid Cookie URL"))?;
        let now_seconds = unix_seconds(now)?;
        self.purge_expired(now_seconds);
        Ok(self
            .cookies
            .iter()
            .filter(|cookie| cookie_matches(cookie, &url, now_seconds))
            .map(|cookie| format!("{}={}", cookie.name, cookie.value))
            .collect::<Vec<_>>()
            .join("; "))
    }

    /// Borrow currently retained cookies for session serialization.
    #[must_use]
    pub fn cookies(&self) -> &[StoredCookie] {
        &self.cookies
    }

    /// Replace the jar contents from a persisted session.
    pub fn replace(&mut self, cookies: Vec<StoredCookie>) {
        self.cookies = cookies;
    }

    fn purge_expired(&mut self, now: i64) {
        self.cookies.retain(|cookie| !is_expired(cookie, now));
    }
}

/// Snapshot persisted across CLI processes.
#[derive(Clone, Deserialize, Eq, PartialEq, Serialize)]
pub struct SessionSnapshot {
    /// Connection strategy used by this session.
    pub mode: ConnectionMode,
    /// Filtered upstream cookies.
    pub cookies: Vec<StoredCookie>,
    /// Unix timestamp when authentication succeeded.
    pub authenticated_at: i64,
    /// Unix timestamp of the last successful validation.
    pub last_activity: i64,
}

/// One persisted route slot in the schema-v2 session file.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RouteSessionSnapshot {
    /// Filtered upstream Cookies scoped to this route.
    pub cookies: Vec<StoredCookie>,
    /// Unix timestamp when authentication succeeded.
    pub authenticated_at: i64,
    /// Unix timestamp of the last successful validation.
    pub last_activity: i64,
}

impl RouteSessionSnapshot {
    /// Convert an existing legacy snapshot without changing or copying its Cookies.
    #[must_use]
    pub fn from_legacy(snapshot: &SessionSnapshot) -> Self {
        Self {
            cookies: snapshot.cookies.clone(),
            authenticated_at: snapshot.authenticated_at,
            last_activity: snapshot.last_activity,
        }
    }

    /// Convert this slot to the legacy route-scoped runtime value.
    #[must_use]
    pub fn into_legacy(self, mode: ConnectionMode) -> SessionSnapshot {
        SessionSnapshot {
            mode,
            cookies: self.cookies,
            authenticated_at: self.authenticated_at,
            last_activity: self.last_activity,
        }
    }
}

/// Direct and `WebVPN` slots persisted atomically in schema version 2.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DualSessionSnapshot {
    /// Schema discriminator.
    pub schema_version: u32,
    /// Route-scoped sessions.
    pub sessions: RouteSessions,
}

/// Dual snapshot plus the revision used for compare-and-exchange.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct VersionedDualSession {
    /// Current schema-v2 snapshot, if present.
    pub snapshot: Option<DualSessionSnapshot>,
    /// Monotonic revision under the same lock as the snapshot.
    pub revision: u64,
}

/// Route slots inside a schema-v2 session file.
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct RouteSessions {
    /// Direct route session.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub direct: Option<RouteSessionSnapshot>,
    /// `WebVPN` route session.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub webvpn: Option<RouteSessionSnapshot>,
}

impl DualSessionSnapshot {
    /// Construct a schema-v2 snapshot.
    #[must_use]
    pub const fn new(
        direct: Option<RouteSessionSnapshot>,
        webvpn: Option<RouteSessionSnapshot>,
    ) -> Self {
        Self {
            schema_version: 2,
            sessions: RouteSessions { direct, webvpn },
        }
    }

    /// Direct route slot.
    #[must_use]
    pub fn direct(&self) -> Option<&RouteSessionSnapshot> {
        self.sessions.direct.as_ref()
    }

    /// `WebVPN` route slot.
    #[must_use]
    pub fn webvpn(&self) -> Option<&RouteSessionSnapshot> {
        self.sessions.webvpn.as_ref()
    }
}

impl std::ops::Deref for DualSessionSnapshot {
    type Target = RouteSessions;

    fn deref(&self) -> &Self::Target {
        &self.sessions
    }
}

impl std::fmt::Debug for SessionSnapshot {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("SessionSnapshot")
            .field("mode", &self.mode)
            .field("cookie_count", &self.cookies.len())
            .field("authenticated_at", &self.authenticated_at)
            .field("last_activity", &self.last_activity)
            .finish()
    }
}

/// Result of validating a persisted session.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SessionValidation {
    /// Upstream confirmed a valid session.
    Valid,
    /// Upstream explicitly rejected or redirected the session.
    Invalid,
    /// Upstream returned a temporary server failure.
    ServerError,
    /// The request timed out before a conclusion.
    Timeout,
}

impl SessionValidation {
    /// Whether local authentication state must be cleared.
    #[must_use]
    pub const fn should_clear(self) -> bool {
        matches!(self, Self::Invalid)
    }
}

/// One atomically loaded persisted snapshot and its mutation revision.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct VersionedSession {
    /// Persisted session, if present.
    pub snapshot: Option<SessionSnapshot>,
    /// Monotonic local revision used to reject stale writers.
    pub revision: u64,
}

/// Result of a compare-exchange session mutation.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SessionMutation {
    /// The mutation was applied and produced this revision.
    Applied {
        /// New monotonic local revision.
        revision: u64,
    },
    /// Another process changed the session after the caller loaded it.
    Conflict,
}

/// Result of a schema-v2 dual-session compare-exchange.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DualSessionMutation {
    /// Mutation applied and revision advanced.
    Applied { revision: u64 },
    /// Another process changed either route slot.
    Conflict,
}

/// Persistence port for one client-owned session.
pub trait SessionStore: Send + Sync {
    /// Atomically load a session snapshot and its current revision.
    ///
    /// # Errors
    ///
    /// Returns a safe persistence or parsing error.
    fn load_versioned(&self) -> Result<VersionedSession>;
    /// Atomically replace the session only when `expected_revision` is still current.
    ///
    /// `replacement=None` clears the persisted session. Applied mutations always advance the
    /// revision, including clears, so deleting and recreating equal JSON cannot fool stale writers.
    ///
    /// # Errors
    ///
    /// Returns a safe persistence or serialization error.
    fn compare_exchange(
        &self,
        expected_revision: u64,
        replacement: Option<&SessionSnapshot>,
    ) -> Result<SessionMutation>;
    /// Load a session snapshot, if present.
    ///
    /// # Errors
    ///
    /// Returns a safe persistence or parsing error.
    fn load(&self) -> Result<Option<SessionSnapshot>> {
        self.load_versioned().map(|state| state.snapshot)
    }
    /// Replace the persisted snapshot.
    ///
    /// # Errors
    ///
    /// Returns a safe persistence or serialization error.
    fn save(&self, snapshot: &SessionSnapshot) -> Result<()> {
        loop {
            let current = self.load_versioned()?;
            if matches!(
                self.compare_exchange(current.revision, Some(snapshot))?,
                SessionMutation::Applied { .. }
            ) {
                return Ok(());
            }
        }
    }
    /// Remove local session state.
    ///
    /// # Errors
    ///
    /// Returns a safe persistence error when the state cannot be removed.
    fn clear(&self) -> Result<()> {
        loop {
            let current = self.load_versioned()?;
            if matches!(
                self.compare_exchange(current.revision, None)?,
                SessionMutation::Applied { .. }
            ) {
                return Ok(());
            }
        }
    }
}

/// File-backed session store using `<config-dir>/session.json`.
#[derive(Clone)]
pub struct FileSessionStore {
    path: PathBuf,
    process_lock: Arc<Mutex<()>>,
}

/// A route-scoped view over the schema-v2 dual session file.
///
/// The view implements the legacy `SessionStore` port so existing runtime code can remain
/// route-local while reads and compare-exchanges are still performed against the shared dual
/// file and its single revision lock.
#[derive(Clone)]
pub struct RouteSessionStore {
    inner: FileSessionStore,
    mode: ConnectionMode,
}

/// One client-owned view of a complete dual-session snapshot and revision.
///
/// Route adapters share this coordinator so a mutation by one route is visible to the other
/// without reloading and adopting an external process's revision.
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

/// Route-local `SessionStore` adapter backed by one client-owned dual coordinator.
#[derive(Clone)]
pub(crate) struct CoordinatedRouteSessionStore {
    coordinator: DualSessionCoordinator,
    mode: ConnectionMode,
}

impl std::fmt::Debug for RouteSessionStore {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("RouteSessionStore")
            .field("mode", &self.mode)
            .field("inner", &self.inner)
            .finish()
    }
}

impl RouteSessionStore {
    /// Construct a route-scoped store over an existing dual-file store.
    #[must_use]
    pub const fn new(inner: FileSessionStore, mode: ConnectionMode) -> Self {
        Self { inner, mode }
    }
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
        let route_revision = match self.mode {
            ConnectionMode::Direct => state.direct_revision,
            ConnectionMode::WebVpn => state.webvpn_revision,
        };
        if state.conflicted {
            return Ok(SessionMutation::Conflict);
        }
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
}

impl SessionStore for RouteSessionStore {
    fn load_versioned(&self) -> Result<VersionedSession> {
        let current = self.inner.load_dual_versioned()?;
        let snapshot = current.snapshot.and_then(|dual| match self.mode {
            ConnectionMode::Direct => dual.sessions.direct,
            ConnectionMode::WebVpn => dual.sessions.webvpn,
        });
        Ok(VersionedSession {
            revision: current.revision,
            snapshot: snapshot.map(|slot| slot.into_legacy(self.mode)),
        })
    }

    fn compare_exchange(
        &self,
        expected_revision: u64,
        replacement: Option<&SessionSnapshot>,
    ) -> Result<SessionMutation> {
        let current = self.inner.load_dual_versioned()?;
        if current.revision != expected_revision {
            return Ok(SessionMutation::Conflict);
        }
        let mut dual = current
            .snapshot
            .unwrap_or_else(|| DualSessionSnapshot::new(None, None));
        let slot = replacement.map(RouteSessionSnapshot::from_legacy);
        match self.mode {
            ConnectionMode::Direct => dual.sessions.direct = slot,
            ConnectionMode::WebVpn => dual.sessions.webvpn = slot,
        }
        let replacement = if dual.sessions.direct.is_none() && dual.sessions.webvpn.is_none() {
            None
        } else {
            Some(&dual)
        };
        match self
            .inner
            .compare_exchange_dual(expected_revision, replacement)?
        {
            DualSessionMutation::Applied { revision } => Ok(SessionMutation::Applied { revision }),
            DualSessionMutation::Conflict => Ok(SessionMutation::Conflict),
        }
    }
}

impl std::fmt::Debug for FileSessionStore {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("FileSessionStore")
            .field("path", &"[REDACTED]")
            .finish()
    }
}

impl FileSessionStore {
    /// Create a restricted configuration directory and session path.
    ///
    /// # Errors
    ///
    /// Returns a safe persistence error when the directory cannot be created or restricted.
    pub fn new(config_dir: impl AsRef<Path>) -> Result<Self> {
        let config_dir = config_dir.as_ref();
        fs::create_dir_all(config_dir)
            .map_err(|_| session_error("could not create config directory"))?;
        validate_directory(config_dir)?;
        restrict_directory(config_dir)?;
        let store = Self {
            path: config_dir.join("session.json"),
            process_lock: Arc::new(Mutex::new(())),
        };
        drop(store.open_lock_file()?);
        Ok(store)
    }

    /// Return the exact session path for diagnostics and tests.
    #[must_use]
    pub fn path(&self) -> &Path {
        &self.path
    }

    /// Load schema v2 or migrate one legacy single-route snapshot under the session lock.
    pub fn load_dual(&self) -> Result<Option<DualSessionSnapshot>> {
        self.load_dual_versioned().map(|current| current.snapshot)
    }

    /// Load the dual snapshot and its synchronized revision.
    pub fn load_dual_versioned(&self) -> Result<VersionedDualSession> {
        let mut lock = self.acquire_lock()?;
        let mut revision = read_revision(&mut lock.file)?;
        let snapshot = match self.read_body_unlocked()? {
            None => None,
            Some(body) => {
                if let Ok(snapshot) = serde_json::from_slice::<DualSessionSnapshot>(&body) {
                    if snapshot.schema_version != 2 {
                        return Err(session_error("session format is invalid"));
                    }
                    Some(snapshot)
                } else {
                    let legacy: SessionSnapshot = serde_json::from_slice(&body)
                        .map_err(|_| session_error("session format is invalid"))?;
                    let slot = RouteSessionSnapshot::from_legacy(&legacy);
                    let migrated = match legacy.mode {
                        ConnectionMode::Direct => DualSessionSnapshot::new(Some(slot), None),
                        ConnectionMode::WebVpn => DualSessionSnapshot::new(None, Some(slot)),
                    };
                    revision = revision
                        .checked_add(1)
                        .ok_or_else(|| session_error("session revision is exhausted"))?;
                    write_revision(&mut lock.file, revision)?;
                    self.save_unlocked(&encode_dual_snapshot(&migrated)?)?;
                    Some(migrated)
                }
            }
        };
        Ok(VersionedDualSession { snapshot, revision })
    }

    /// Persist a complete schema-v2 dual snapshot atomically.
    pub fn save_dual(&self, snapshot: &DualSessionSnapshot) -> Result<DualSessionSnapshot> {
        loop {
            let current = self.load_dual_versioned()?;
            match self.compare_exchange_dual(current.revision, Some(snapshot))? {
                DualSessionMutation::Applied { .. } => return Ok(snapshot.clone()),
                DualSessionMutation::Conflict => continue,
            }
        }
    }

    /// Compare-exchange a schema-v2 snapshot while holding the same OS lock as its revision.
    pub fn compare_exchange_dual(
        &self,
        expected_revision: u64,
        replacement: Option<&DualSessionSnapshot>,
    ) -> Result<DualSessionMutation> {
        if replacement.is_some_and(|snapshot| snapshot.schema_version != 2) {
            return Err(session_error("session format is invalid"));
        }
        let body = replacement.map(encode_dual_snapshot).transpose()?;
        let mut lock = self.acquire_lock()?;
        let current_revision = read_revision(&mut lock.file)?;
        if current_revision != expected_revision {
            return Ok(DualSessionMutation::Conflict);
        }
        let revision = current_revision
            .checked_add(1)
            .ok_or_else(|| session_error("session revision is exhausted"))?;
        write_revision(&mut lock.file, revision)?;
        match body {
            Some(body) => self.save_unlocked(&body)?,
            None => self.clear_unlocked()?,
        }
        Ok(DualSessionMutation::Applied { revision })
    }
}

impl SessionStore for FileSessionStore {
    fn load_versioned(&self) -> Result<VersionedSession> {
        let mut lock = self.acquire_lock()?;
        Ok(VersionedSession {
            revision: read_revision(&mut lock.file)?,
            snapshot: self.load_unlocked()?,
        })
    }

    fn compare_exchange(
        &self,
        expected_revision: u64,
        replacement: Option<&SessionSnapshot>,
    ) -> Result<SessionMutation> {
        let body = replacement.map(encode_snapshot).transpose()?;
        let mut lock = self.acquire_lock()?;
        let current_revision = read_revision(&mut lock.file)?;
        if current_revision != expected_revision {
            return Ok(SessionMutation::Conflict);
        }
        let revision = current_revision
            .checked_add(1)
            .ok_or_else(|| session_error("session revision is exhausted"))?;
        write_revision(&mut lock.file, revision)?;
        match body {
            Some(body) => self.save_unlocked(&body)?,
            None => self.clear_unlocked()?,
        }
        Ok(SessionMutation::Applied { revision })
    }
}

impl FileSessionStore {
    fn read_body_unlocked(&self) -> Result<Option<Vec<u8>>> {
        let Some(file) = open_existing_session_file(&self.path)? else {
            return Ok(None);
        };
        restrict_open_file(&file, "could not restrict session file")?;
        let mut body = Vec::new();
        file.take(MAX_SESSION_FILE_BYTES as u64 + 1)
            .read_to_end(&mut body)
            .map_err(|_| session_error("could not read session"))?;
        if body.len() > MAX_SESSION_FILE_BYTES {
            return Err(session_error("session file exceeds the allowed size"));
        }
        Ok(Some(body))
    }

    fn load_unlocked(&self) -> Result<Option<SessionSnapshot>> {
        let Some(body) = self.read_body_unlocked()? else {
            return Ok(None);
        };
        serde_json::from_slice(&body)
            .map(Some)
            .map_err(|_| session_error("session format is invalid"))
    }

    fn save_unlocked(&self, body: &[u8]) -> Result<()> {
        validate_regular_file(&self.path, "session path is not a regular file")?;
        let parent = self
            .path
            .parent()
            .ok_or_else(|| session_error("session path has no parent directory"))?;
        let (temporary, mut file) = create_temporary_file(parent)?;
        let mut cleanup = TemporaryFile::new(temporary);
        restrict_open_file(&file, "could not restrict session file")?;
        file.write_all(body)
            .map_err(|_| session_error("could not write session"))?;
        file.flush()
            .map_err(|_| session_error("could not flush session"))?;
        file.sync_all()
            .map_err(|_| session_error("could not sync session"))?;
        drop(file);

        validate_regular_file(&self.path, "session path is not a regular file")?;
        fs::rename(cleanup.path(), &self.path)
            .map_err(|_| session_error("could not replace session"))?;
        cleanup.persisted();
        sync_directory(parent)
    }

    fn clear_unlocked(&self) -> Result<()> {
        if !validate_regular_file(&self.path, "session path is not a regular file")? {
            return Ok(());
        }
        match fs::remove_file(&self.path) {
            Ok(()) => {
                if let Some(parent) = self.path.parent() {
                    sync_directory(parent)?;
                }
                Ok(())
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(_) => Err(session_error("could not clear session")),
        }
    }

    fn lock_path(&self) -> PathBuf {
        self.path.with_file_name(".session.lock")
    }

    fn open_lock_file(&self) -> Result<File> {
        let path = self.lock_path();
        let mut options = OpenOptions::new();
        options.read(true).write(true).create(true);
        restrict_file_creation(&mut options);
        prevent_symlink_following(&mut options);
        let Ok(file) = options.open(&path) else {
            validate_regular_file(&path, "session lock path is not a regular file")?;
            return Err(session_error("could not open session lock"));
        };
        validate_open_regular_file(
            &file,
            "session lock path is not a regular file",
            "could not inspect session lock",
        )?;
        restrict_open_file(&file, "could not restrict session lock")?;
        Ok(file)
    }

    fn acquire_lock(&self) -> Result<SessionFileLock<'_>> {
        let process_guard = self
            .process_lock
            .lock()
            .map_err(|_| session_error("session process lock is unavailable"))?;
        let parent = self
            .path
            .parent()
            .ok_or_else(|| session_error("session path has no parent directory"))?;
        validate_directory(parent)?;
        let file = self.open_lock_file()?;
        file.lock()
            .map_err(|_| session_error("could not lock session"))?;
        Ok(SessionFileLock {
            _process_guard: process_guard,
            file,
        })
    }
}

struct SessionFileLock<'a> {
    _process_guard: MutexGuard<'a, ()>,
    file: File,
}

impl Drop for SessionFileLock<'_> {
    fn drop(&mut self) {
        let _ = self.file.unlock();
    }
}

struct TemporaryFile {
    path: PathBuf,
    remove_on_drop: bool,
}

impl TemporaryFile {
    fn new(path: PathBuf) -> Self {
        Self {
            path,
            remove_on_drop: true,
        }
    }

    fn path(&self) -> &Path {
        &self.path
    }

    fn persisted(&mut self) {
        self.remove_on_drop = false;
    }
}

impl Drop for TemporaryFile {
    fn drop(&mut self) {
        if self.remove_on_drop {
            let _ = fs::remove_file(&self.path);
        }
    }
}

fn create_temporary_file(parent: &Path) -> Result<(PathBuf, File)> {
    for _ in 0..MAX_TEMP_FILE_ATTEMPTS {
        let sequence = NEXT_TEMP_FILE.fetch_add(1, Ordering::Relaxed);
        let path = parent.join(format!(
            ".session.json.{}.{sequence}.tmp",
            std::process::id()
        ));
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        restrict_file_creation(&mut options);
        match options.open(&path) {
            Ok(file) => return Ok((path, file)),
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {}
            Err(_) => return Err(session_error("could not create temporary session file")),
        }
    }
    Err(session_error("could not allocate temporary session file"))
}

fn encode_snapshot(snapshot: &SessionSnapshot) -> Result<Vec<u8>> {
    let body = serde_json::to_vec_pretty(snapshot)
        .map_err(|_| session_error("could not encode session"))?;
    if body.len() > MAX_SESSION_FILE_BYTES {
        return Err(session_error("encoded session exceeds the allowed size"));
    }
    Ok(body)
}

fn encode_dual_snapshot(snapshot: &DualSessionSnapshot) -> Result<Vec<u8>> {
    let body = serde_json::to_vec_pretty(snapshot)
        .map_err(|_| session_error("could not encode session"))?;
    if body.len() > MAX_SESSION_FILE_BYTES {
        return Err(session_error("encoded session exceeds the allowed size"));
    }
    Ok(body)
}

fn read_revision(file: &mut File) -> Result<u64> {
    file.seek(SeekFrom::Start(0))
        .map_err(|_| session_error("could not read session revision"))?;
    let mut body = Vec::new();
    file.take(REVISION_FILE_BYTES as u64 + 1)
        .read_to_end(&mut body)
        .map_err(|_| session_error("could not read session revision"))?;
    if body.is_empty() {
        return Ok(0);
    }
    if body.len() != REVISION_FILE_BYTES || body.last() != Some(&b'\n') {
        return Err(session_error("session revision format is invalid"));
    }
    let digits = std::str::from_utf8(&body[..REVISION_FILE_BYTES - 1])
        .map_err(|_| session_error("session revision format is invalid"))?;
    u64::from_str_radix(digits, 16).map_err(|_| session_error("session revision format is invalid"))
}

fn write_revision(file: &mut File, revision: u64) -> Result<()> {
    let body = format!("{revision:016x}\n");
    file.seek(SeekFrom::Start(0))
        .and_then(|_| file.write_all(body.as_bytes()))
        .and_then(|()| file.set_len(REVISION_FILE_BYTES as u64))
        .and_then(|()| file.flush())
        .and_then(|()| file.sync_all())
        .map_err(|_| session_error("could not sync session revision"))
}

fn validate_directory(path: &Path) -> Result<()> {
    let metadata = fs::symlink_metadata(path)
        .map_err(|_| session_error("could not inspect config directory"))?;
    if metadata.file_type().is_symlink() || !metadata.is_dir() {
        return Err(session_error("config path is not a directory"));
    }
    Ok(())
}

fn validate_regular_file(path: &Path, message: &'static str) -> Result<bool> {
    match fs::symlink_metadata(path) {
        Ok(metadata) if metadata.file_type().is_symlink() || !metadata.is_file() => {
            Err(session_error(message))
        }
        Ok(_) => Ok(true),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(_) => Err(session_error("could not inspect session file")),
    }
}

fn open_existing_session_file(path: &Path) -> Result<Option<File>> {
    let mut options = OpenOptions::new();
    options.read(true);
    prevent_symlink_following(&mut options);
    match options.open(path) {
        Ok(file) => {
            validate_open_regular_file(
                &file,
                "session path is not a regular file",
                "could not inspect session",
            )?;
            Ok(Some(file))
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(_) => {
            validate_regular_file(path, "session path is not a regular file")?;
            Err(session_error("could not read session"))
        }
    }
}

fn validate_open_regular_file(
    file: &File,
    type_message: &'static str,
    inspect_message: &'static str,
) -> Result<()> {
    let metadata = file
        .metadata()
        .map_err(|_| session_error(inspect_message))?;
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return Err(session_error(type_message));
    }
    Ok(())
}

fn prevent_symlink_following(options: &mut OpenOptions) {
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt as _;
        options.custom_flags(libc::O_NOFOLLOW);
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::OpenOptionsExt as _;
        // Rust 1.95 std uses this Win32 flag when opening a link without following it.
        const FILE_FLAG_OPEN_REPARSE_POINT: u32 = 0x0020_0000;
        options.custom_flags(FILE_FLAG_OPEN_REPARSE_POINT);
    }
    #[cfg(not(any(unix, windows)))]
    let _ = options;
}

fn sync_directory(path: &Path) -> Result<()> {
    #[cfg(unix)]
    {
        File::open(path)
            .and_then(|directory| directory.sync_all())
            .map_err(|_| session_error("could not sync config directory"))?;
    }
    Ok(())
}

fn parse_cookie(raw: &str, url: &Url, created_at: i64) -> Result<Option<StoredCookie>> {
    let mut parts = raw.split(';');
    let Some((name, value)) = parts.next().and_then(|part| part.trim().split_once('=')) else {
        return Err(session_error("upstream Set-Cookie has no name/value"));
    };
    let host = url
        .host_str()
        .ok_or_else(|| session_error("Cookie URL has no host"))?
        .to_ascii_lowercase();
    let mut cookie = StoredCookie {
        name: name.trim().to_string(),
        value: value.trim().to_string(),
        domain: host.clone(),
        host_only: true,
        path: default_cookie_path(url.path()),
        secure: false,
        expires_at: None,
        created_at,
        max_age: None,
    };
    if cookie.name.is_empty() {
        return Err(session_error("upstream Set-Cookie has an empty name"));
    }
    for attribute in parts {
        let attribute = attribute.trim();
        if attribute.eq_ignore_ascii_case("secure") {
            cookie.secure = true;
        } else if let Some((key, value)) = attribute.split_once('=') {
            match key.trim().to_ascii_lowercase().as_str() {
                "domain" => {
                    let domain = value.trim().trim_start_matches('.').to_ascii_lowercase();
                    if !domain_matches(&host, &domain) {
                        return Ok(None);
                    }
                    cookie.domain = domain;
                    cookie.host_only = false;
                }
                "path" if value.trim().starts_with('/') => cookie.path = value.trim().to_string(),
                "max-age" => cookie.max_age = value.trim().parse().ok(),
                "expires" => {
                    cookie.expires_at = httpdate::parse_http_date(value.trim())
                        .ok()
                        .and_then(|time| unix_seconds(time).ok());
                }
                _ => {}
            }
        }
    }
    Ok(Some(cookie))
}

fn cookie_matches(cookie: &StoredCookie, url: &Url, now: i64) -> bool {
    let Some(host) = url.host_str() else {
        return false;
    };
    let domain_match = if cookie.host_only {
        host.eq_ignore_ascii_case(&cookie.domain)
    } else {
        domain_matches(host, &cookie.domain)
    };
    let path_match = path_matches(url.path(), &cookie.path);
    let secure_match = !cookie.secure || url.scheme().eq_ignore_ascii_case("https");
    domain_match && path_match && secure_match && !is_expired(cookie, now)
}

fn is_expired(cookie: &StoredCookie, now: i64) -> bool {
    cookie.expires_at.is_some_and(|expires| expires <= now)
        || cookie
            .max_age
            .is_some_and(|age| age <= 0 || now >= cookie.created_at.saturating_add(age))
}

fn default_cookie_path(path: &str) -> String {
    if path.is_empty() || !path.starts_with('/') || path == "/" {
        return "/".into();
    }
    path.rsplit_once('/').map_or_else(
        || "/".into(),
        |(prefix, _)| {
            if prefix.is_empty() {
                "/".into()
            } else {
                prefix.into()
            }
        },
    )
}

fn path_matches(request: &str, cookie: &str) -> bool {
    if request == cookie {
        return true;
    }
    request
        .strip_prefix(cookie)
        .is_some_and(|rest| cookie.ends_with('/') || rest.starts_with('/'))
}

fn domain_matches(host: &str, domain: &str) -> bool {
    host.eq_ignore_ascii_case(domain) || host.to_ascii_lowercase().ends_with(&format!(".{domain}"))
}

fn header_values<'a>(
    headers: &'a std::collections::BTreeMap<String, Vec<String>>,
    name: &str,
) -> impl Iterator<Item = &'a str> {
    headers
        .iter()
        .filter(move |(key, _)| key.eq_ignore_ascii_case(name))
        .flat_map(|(_, values)| values.iter().map(String::as_str))
}

fn unix_seconds(time: SystemTime) -> Result<i64> {
    time.duration_since(UNIX_EPOCH)
        .map(|duration| i64::try_from(duration.as_secs()).unwrap_or(i64::MAX))
        .map_err(|_| session_error("system clock is before Unix epoch"))
}

fn session_error(message: impl Into<String>) -> UbaaError {
    UbaaError::new(
        ErrorCode::InternalError,
        ErrorKind::Internal,
        false,
        message,
    )
}

fn dual_session_conflict() -> UbaaError {
    UbaaError::new(
        ErrorCode::InternalError,
        ErrorKind::Internal,
        true,
        "local session changed in another process",
    )
}

fn restrict_directory(path: &Path) -> Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        File::open(path)
            .and_then(|directory| directory.set_permissions(fs::Permissions::from_mode(0o700)))
            .map_err(|_| session_error("could not restrict config directory"))?;
    }
    Ok(())
}

fn restrict_file_creation(options: &mut OpenOptions) {
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
}

fn restrict_open_file(file: &File, message: &'static str) -> Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        file.set_permissions(fs::Permissions::from_mode(0o600))
            .map_err(|_| session_error(message))?;
    }
    #[cfg(not(unix))]
    let _ = (file, message);
    Ok(())
}

#[cfg(test)]
mod coordinator_tests {
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
        let error = direct.load_versioned().unwrap_err();
        assert_eq!(error.message, "local session changed in another process");
        assert_eq!(
            file_store
                .load_dual()
                .unwrap()
                .and_then(|dual| dual.sessions.direct)
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
