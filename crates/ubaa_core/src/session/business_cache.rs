//! 只读 worker 在同一账号与路线内共享的业务会话材料。
mod cookies;
mod file;
mod writer;
pub(crate) use cookies::reusable_cookie_scope;

use super::{FileSessionStore, StoredCookie};
use crate::domain::ConnectionMode;
use crate::error::Result;
use crate::internal::route_state::{
    RouteFeatureState, SpocCredential, StudentKind, YgdkCredential,
};
use serde::{Deserialize, Serialize};
use std::sync::{
    Arc, Mutex, MutexGuard, Weak,
    atomic::{AtomicBool, AtomicU64, Ordering},
};

#[derive(Clone, Copy, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "lowercase")]
pub(crate) enum BusinessScope {
    Byxt,
    Portal,
    Identity,
    Spoc,
    Ygdk,
}

impl BusinessScope {
    pub(crate) const ALL: [Self; 5] = [
        Self::Byxt,
        Self::Portal,
        Self::Identity,
        Self::Spoc,
        Self::Ygdk,
    ];

    fn is_expired(self, saved_at: i64, now: i64) -> bool {
        if saved_at > now {
            return true;
        }
        let ttl = match self {
            Self::Byxt | Self::Portal => return false,
            Self::Identity => 7 * 24 * 60 * 60,
            Self::Spoc => 3 * 60 * 60,
            Self::Ygdk => 12 * 60 * 60,
        };
        now.saturating_sub(saved_at) > ttl
    }

    pub(crate) fn owns(self, route: ConnectionMode, cookie: &StoredCookie) -> bool {
        let host = match self {
            Self::Byxt => "byxt.buaa.edu.cn",
            Self::Portal => "it.buaa.edu.cn",
            Self::Identity | Self::Spoc | Self::Ygdk => return false,
        };
        reusable_cookie_scope(route, cookie) == Some(host)
    }
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub(crate) enum BusinessMaterial {
    Cookies(Vec<StoredCookie>),
    Identity(StudentKind),
    Spoc(SpocCredential),
    Ygdk(YgdkCredential),
}

impl BusinessMaterial {
    fn matches(&self, other: &Self) -> bool {
        match (self, other) {
            (Self::Cookies(left), Self::Cookies(right)) => {
                left.len() == right.len()
                    && left
                        .iter()
                        .all(|cookie| right.iter().any(|other| cookie.same_for_persistence(other)))
            }
            (Self::Identity(left), Self::Identity(right)) => left == right,
            (Self::Spoc(left), Self::Spoc(right)) => left == right,
            (Self::Ygdk(left), Self::Ygdk(right)) => left == right,
            _ => false,
        }
    }

    fn for_scope(mut self, route: ConnectionMode, scope: BusinessScope) -> Option<Self> {
        match (scope, &mut self) {
            (BusinessScope::Byxt | BusinessScope::Portal, Self::Cookies(cookies)) => {
                cookies.retain(|cookie| scope.owns(route, cookie));
                if cookies.is_empty() {
                    return None;
                }
            }
            (BusinessScope::Identity, Self::Identity(_))
            | (BusinessScope::Spoc, Self::Spoc(_))
            | (BusinessScope::Ygdk, Self::Ygdk(_)) => {}
            _ => return None,
        }
        Some(self)
    }
}

pub(crate) fn same_material(
    left: Option<&BusinessMaterial>,
    right: Option<&BusinessMaterial>,
) -> bool {
    match (left, right) {
        (Some(left), Some(right)) => left.matches(right),
        (None, None) => true,
        _ => false,
    }
}

#[derive(Clone, Default)]
pub(crate) struct BusinessSeed {
    pub(crate) version: u64,
    pub(crate) material: Option<BusinessMaterial>,
    saved_at: i64,
    source: Option<SeedSource>,
    pending: Option<Arc<AtomicBool>>,
}

#[derive(Clone)]
pub(crate) struct SeedSource(pub(crate) Weak<RouteFeatureState>, pub(crate) u64);

impl SeedSource {
    fn is_current(&self) -> bool {
        self.0
            .upgrade()
            .is_some_and(|state| state.lifecycle_generation() == self.1)
    }
}

impl BusinessSeed {
    fn invalidate(&mut self) {
        self.version = self.version.saturating_add(1);
        self.material = None;
        self.source = None;
        self.pending = None;
    }
}

pub(crate) type BusinessSeeds = [BusinessSeed; BusinessScope::ALL.len()];

type ClearNonce = [u8; 16];
type ContentVersion = [u8; 16];

#[derive(Clone, Copy)]
pub(crate) enum Invalidation {
    RevokeAll,
    RevokeRoute(ConnectionMode),
    AccountChanged,
    SameAccountLogin(ConnectionMode),
}

impl Invalidation {
    fn routes(self) -> RevocationRoutes {
        match self {
            Self::RevokeRoute(route) | Self::SameAccountLogin(route) => {
                RevocationRoutes::One(route)
            }
            Self::RevokeAll | Self::AccountChanged => RevocationRoutes::Both,
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum RevocationRoutes {
    One(ConnectionMode),
    Both,
}

#[derive(Clone, Copy, PartialEq)]
pub(crate) struct BusinessCacheStamp {
    generation: u64,
    nonce: Option<ClearNonce>,
}

#[derive(Default)]
struct RouteSeeds {
    entries: BusinessSeeds,
    observed: Option<(Option<ClearNonce>, Option<ContentVersion>)>,
}

#[derive(Default)]
struct State {
    account: Option<String>,
    direct: RouteSeeds,
    webvpn: RouteSeeds,
    generation: Arc<AtomicU64>,
    writer: writer::Writer,
    conflicted: bool,
    pending_revocation: Option<RevocationRoutes>,
    #[cfg(test)]
    before_revocation: Option<Box<dyn FnOnce() + Send>>,
    #[cfg(test)]
    before_file_job: Option<Box<dyn FnOnce() + Send>>,
}

impl State {
    fn route(&mut self, route: ConnectionMode) -> &mut RouteSeeds {
        match route {
            ConnectionMode::Direct => &mut self.direct,
            ConnectionMode::WebVpn => &mut self.webvpn,
        }
    }

    fn invalidate(&mut self, route: ConnectionMode) {
        let seeds = self.route(route);
        for entry in &mut seeds.entries {
            entry.invalidate();
        }
        seeds.observed = None;
    }

    fn invalidate_all(&mut self) {
        self.generation.fetch_add(1, Ordering::AcqRel);
        self.invalidate(ConnectionMode::Direct);
        self.invalidate(ConnectionMode::WebVpn);
    }

    fn accepts(
        &mut self,
        account: &str,
        route: ConnectionMode,
        stamp: &BusinessCacheStamp,
    ) -> bool {
        !self.conflicted
            && self.pending_revocation.is_none()
            && self.generation.load(Ordering::Acquire) == stamp.generation
            && self.account.as_deref() == Some(account)
            && self
                .route(route)
                .observed
                .is_some_and(|(nonce, _)| nonce == stamp.nonce)
    }
}

pub(crate) struct BusinessSessionCache {
    file: Arc<file::BusinessSessionFile>,
    state: Mutex<State>,
}

impl BusinessSessionCache {
    pub(crate) fn new(store: &FileSessionStore) -> Self {
        Self {
            file: Arc::new(file::BusinessSessionFile::new(store.directory())),
            state: Mutex::default(),
        }
    }

    fn lock(&self) -> MutexGuard<'_, State> {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }

    pub(crate) fn seeds(
        &self,
        account: &str,
        route: ConnectionMode,
        now: i64,
    ) -> (BusinessCacheStamp, BusinessSeeds) {
        let mut state = self.lock();
        if state.conflicted || state.pending_revocation.is_some() {
            return (
                BusinessCacheStamp {
                    generation: state.generation.load(Ordering::Acquire),
                    nonce: None,
                },
                state.route(route).entries.clone(),
            );
        }
        if state.account.as_deref() != Some(account) {
            state.invalidate_all();
            state.account = Some(account.to_owned());
        }
        let generation = state.generation.load(Ordering::Acquire);
        // 在读磁盘前取完成状态，避免把读到旧文件后刚提交的条目当成已加载条目。
        let pending = state.route(route).entries.each_ref().map(|entry| {
            entry
                .pending
                .as_ref()
                .is_some_and(|job| !job.load(Ordering::Acquire))
        });
        let Ok(mut document) = self.file.read() else {
            tracing::warn!("业务会话缓存读取失败");
            state.invalidate(route);
            return (
                BusinessCacheStamp {
                    generation,
                    nonce: None,
                },
                state.route(route).entries.clone(),
            );
        };
        let observed = (
            document.as_ref().and_then(|document| document.nonce(route)),
            document
                .as_ref()
                .map(|document| document.content_version(route)),
        );
        let seeds = state.route(route);
        let revoked = seeds.observed.is_none_or(|(nonce, _)| nonce != observed.0);
        let content_changed = seeds.observed != Some(observed);
        let entries = document
            .as_mut()
            .filter(|document| document.account.as_deref() == Some(account))
            .map(|document| document.route(route));
        for (scope, in_flight) in BusinessScope::ALL.into_iter().zip(pending) {
            let slot = &mut seeds.entries[scope as usize];
            if !revoked && in_flight {
                continue;
            }
            if content_changed || slot.pending.is_some() {
                slot.invalidate();
                if let Some(entry) = entries.as_ref().and_then(|entries| entries.get(&scope)) {
                    slot.saved_at = entry.saved_at;
                    slot.material = entry.material.clone().for_scope(route, scope);
                }
            }
        }
        seeds.observed = Some(observed);
        for (scope, seed) in BusinessScope::ALL.into_iter().zip(&mut seeds.entries) {
            if seed.material.is_some()
                && (scope.is_expired(seed.saved_at, now)
                    || seed
                        .source
                        .as_ref()
                        .is_some_and(|source| !source.is_current()))
            {
                seed.invalidate();
            }
        }
        (
            BusinessCacheStamp {
                generation,
                nonce: observed.0,
            },
            seeds.entries.clone(),
        )
    }

    #[cfg(test)]
    fn write(
        &self,
        account: &str,
        stamp: BusinessCacheStamp,
        route: ConnectionMode,
        changes: Vec<(BusinessScope, Option<BusinessMaterial>)>,
        saved_at: i64,
        current: impl FnOnce() -> bool + Send + 'static,
    ) -> Option<BusinessSeeds> {
        self.write_after_revision_check(
            account,
            stamp,
            route,
            changes,
            saved_at,
            (true, || true, current, None),
        )
    }

    pub(crate) fn write_after_revision_check(
        &self,
        account: &str,
        stamp: BusinessCacheStamp,
        route: ConnectionMode,
        changes: Vec<(BusinessScope, Option<BusinessMaterial>)>,
        saved_at: i64,
        persistence: (
            bool,
            impl FnOnce() -> bool + Send + 'static,
            impl FnOnce() -> bool + Send + 'static,
            Option<SeedSource>,
        ),
    ) -> Option<BusinessSeeds> {
        let mut state = self.lock();
        if !state.accepts(account, route, &stamp) {
            return None;
        }
        let (persist, revision_current, lifecycle_current, source) = persistence;
        let pending_job = if persist {
            let account = account.to_owned();
            let pending = changes.clone();
            let generation = Arc::clone(&state.generation);
            #[cfg(test)]
            let before_file_job = state.before_file_job.take();
            let job = Arc::new(AtomicBool::new(false));
            let completed = Arc::clone(&job);
            if !state.writer.submit(&self.file, move |file| {
                if revision_current() {
                    #[cfg(test)]
                    if let Some(pause) = before_file_job {
                        pause();
                    }
                    if file
                        .write(&account, route, stamp.nonce, &pending, saved_at, || {
                            generation.load(Ordering::Acquire) == stamp.generation
                                && lifecycle_current()
                        })
                        .is_err()
                    {
                        tracing::warn!("业务会话缓存写回失败");
                    }
                }
                completed.store(true, Ordering::Release);
            }) {
                tracing::warn!("业务会话缓存写回失败");
                return None;
            }
            Some(job)
        } else {
            None
        };
        let entries = &mut state.route(route).entries;
        for (scope, material) in changes {
            let slot = &mut entries[scope as usize];
            slot.version = slot.version.saturating_add(1);
            slot.saved_at = saved_at;
            slot.material = material;
            slot.source.clone_from(&source);
            slot.pending.clone_from(&pending_job);
        }
        Some(entries.clone())
    }

    pub(crate) fn reject(
        &self,
        account: &str,
        stamp: BusinessCacheStamp,
        route: ConnectionMode,
        scope: BusinessScope,
        rejected: BusinessMaterial,
        persist: bool,
    ) -> bool {
        let mut state = self.lock();
        if !state.accepts(account, route, &stamp) {
            return false;
        }
        let entry = &mut state.route(route).entries[scope as usize];
        if same_material(entry.material.as_ref(), Some(&rejected)) {
            entry.invalidate();
        }
        if !persist {
            return true;
        }
        let generation = Arc::clone(&state.generation);
        let account = account.to_owned();
        #[cfg(test)]
        let before_file_job = state.before_file_job.take();
        let queued = state.writer.submit(&self.file, move |file| {
            #[cfg(test)]
            if let Some(pause) = before_file_job {
                pause();
            }
            if file
                .reject(&account, route, stamp.nonce, scope, &rejected, || {
                    generation.load(Ordering::Acquire) == stamp.generation
                })
                .is_err()
            {
                tracing::warn!("业务会话缓存失效写回失败");
            }
        });
        if !queued {
            tracing::warn!("业务会话缓存失效写回失败");
        }
        queued
    }

    pub(crate) fn invalidate(&self, event: Invalidation) -> Result<()> {
        let mut state = self.lock();
        if state.conflicted {
            return Err(crate::error::UbaaError::session_conflict());
        }
        #[cfg(test)]
        if let Some(before_revocation) = state.before_revocation.take() {
            before_revocation();
        }
        let requested = event.routes();
        let routes = match state.pending_revocation {
            Some(pending) if pending != requested => RevocationRoutes::Both,
            _ => requested,
        };
        let result = revoke(&self.file, routes);
        if result.is_err() || state.pending_revocation.is_some() {
            state.invalidate_all();
        } else {
            match routes {
                RevocationRoutes::One(route) => state.invalidate(route),
                RevocationRoutes::Both => state.invalidate_all(),
            }
        }
        state.pending_revocation = result.is_err().then_some(routes);
        result
    }

    pub(crate) fn inherit_revocation_failure(&self, previous: &Self) {
        let pending = previous.lock().pending_revocation;
        if let Some(routes) = pending {
            let mut state = self.lock();
            state.invalidate_all();
            state.pending_revocation = Some(routes);
        }
    }

    pub(crate) fn discard_seeds(&self) {
        self.lock().invalidate_all();
    }

    pub(crate) fn discard_on_conflict(&self) {
        let mut state = self.lock();
        state.invalidate_all();
        state.account = None;
        state.conflicted = true;
    }
}

pub(crate) fn revoke_disk(store: &FileSessionStore, event: Invalidation) -> Result<()> {
    revoke(
        &file::BusinessSessionFile::new(store.directory()),
        event.routes(),
    )
}

fn revoke(file: &file::BusinessSessionFile, routes: RevocationRoutes) -> Result<()> {
    match routes {
        RevocationRoutes::One(route) => file.clear_route(route),
        RevocationRoutes::Both => file.clear(),
    }
}
#[cfg(test)]
#[path = "business_cache_p2_tests.rs"]
mod p2_tests;
