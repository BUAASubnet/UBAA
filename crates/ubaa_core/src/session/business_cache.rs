//! 只读 worker 在同一账号与路线内共享的业务会话材料。
mod cookies;
mod file;
mod writer;
pub(crate) use cookies::reusable_cookie_scope;

use super::{FileSessionStore, StoredCookie};
use crate::domain::ConnectionMode;
use crate::internal::route_state::{
    RouteFeatureState, SpocCredential, StudentKind, YgdkCredential,
};
use serde::{Deserialize, Serialize};
use std::sync::{
    Arc, Mutex, MutexGuard, OnceLock, Weak,
    atomic::{AtomicU64, Ordering},
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
    }
}

pub(crate) type BusinessSeeds = [BusinessSeed; BusinessScope::ALL.len()];

type ClearNonce = [u8; 16];

#[derive(Clone, Copy)]
pub(crate) enum Invalidation {
    RevokeAll,
    AccountChanged,
    SameAccountLogin(ConnectionMode),
}

#[derive(Clone, PartialEq)]
pub(crate) struct BusinessCacheStamp {
    generation: u64,
    nonce: CacheNonce,
}

#[derive(Clone)]
enum CacheNonce {
    Disk(Option<ClearNonce>),
    Rejection(Arc<RejectionNonce>),
}

struct RejectionNonce {
    proposed: ClearNonce,
    completed: OnceLock<Option<ClearNonce>>,
}

#[derive(PartialEq)]
enum ResolvedNonce {
    Pending,
    Ready(Option<ClearNonce>),
}

impl CacheNonce {
    fn resolved(&self) -> ResolvedNonce {
        match self {
            Self::Disk(nonce) => ResolvedNonce::Ready(*nonce),
            Self::Rejection(pending) => pending
                .completed
                .get()
                .map_or(ResolvedNonce::Pending, |nonce| ResolvedNonce::Ready(*nonce)),
        }
    }
}

impl PartialEq for CacheNonce {
    fn eq(&self, other: &Self) -> bool {
        matches!((self, other), (Self::Rejection(a), Self::Rejection(b)) if Arc::ptr_eq(a, b))
            || matches!(self.resolved(), ResolvedNonce::Ready(nonce) if other.resolved() == ResolvedNonce::Ready(nonce))
    }
}

#[derive(Default)]
struct RouteSeeds {
    entries: BusinessSeeds,
    nonce: Option<CacheNonce>,
    disk_nonce: Option<ClearNonce>,
}

#[derive(Default)]
struct State {
    account: Option<String>,
    direct: RouteSeeds,
    webvpn: RouteSeeds,
    generation: Arc<AtomicU64>,
    writer: writer::Writer,
    conflicted: bool,
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
        seeds.nonce = None;
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
            && self.generation.load(Ordering::Acquire) == stamp.generation
            && self.account.as_deref() == Some(account)
            && self.route(route).nonce.as_ref() == Some(&stamp.nonce)
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
        if state.conflicted {
            return (
                BusinessCacheStamp {
                    generation: state.generation.load(Ordering::Acquire),
                    nonce: CacheNonce::Disk(None),
                },
                state.route(route).entries.clone(),
            );
        }
        if state.account.as_deref() != Some(account) {
            state.invalidate_all();
            state.account = Some(account.to_owned());
        }
        let generation = state.generation.load(Ordering::Acquire);
        let previous = state.route(route).nonce.as_ref().map(CacheNonce::resolved);
        let Ok(mut document) = self.file.read() else {
            tracing::warn!("业务会话缓存读取失败");
            state.invalidate(route);
            return (
                BusinessCacheStamp {
                    generation,
                    nonce: CacheNonce::Disk(None),
                },
                state.route(route).entries.clone(),
            );
        };
        // 旧 schema 2 与尚未写过旁车的路线都没有清理令牌，普通写入可以互相合并。
        let nonce = document.as_ref().and_then(|document| document.nonce(route));
        let seeds = state.route(route);
        let matches_disk = match previous {
            Some(ResolvedNonce::Ready(resolved)) => resolved == nonce,
            // 文件读取可能与本进程的原子替换重叠。无论读到哪一版，都保留已清除的内存条目。
            Some(ResolvedNonce::Pending) => {
                matches!(&seeds.nonce, Some(CacheNonce::Rejection(pending))
                if seeds.disk_nonce == nonce || Some(pending.proposed) == nonce)
            }
            None => false,
        };
        if !matches_disk {
            for entry in &mut seeds.entries {
                entry.invalidate();
            }
            seeds.nonce = Some(CacheNonce::Disk(nonce));
            if let Some(document) = document
                .as_mut()
                .filter(|document| document.account.as_deref() == Some(account))
            {
                for (scope, entry) in std::mem::take(document.route(route)) {
                    let slot = &mut seeds.entries[scope as usize];
                    slot.saved_at = entry.saved_at;
                    slot.material = entry.material.for_scope(route, scope);
                }
            }
        }
        seeds.disk_nonce = nonce;
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
                nonce: seeds.nonce.clone().expect("已加载路线"),
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
            (|| true, current, None),
        )
    }

    pub(crate) fn write_after_revision_check(
        &self,
        account: &str,
        stamp: BusinessCacheStamp,
        route: ConnectionMode,
        changes: Vec<(BusinessScope, Option<BusinessMaterial>)>,
        saved_at: i64,
        checks: (
            impl FnOnce() -> bool + Send + 'static,
            impl FnOnce() -> bool + Send + 'static,
            Option<SeedSource>,
        ),
    ) -> Option<BusinessSeeds> {
        let mut state = self.lock();
        if !state.accepts(account, route, &stamp) {
            return None;
        }
        let account = account.to_owned();
        let pending = changes.clone();
        let generation = Arc::clone(&state.generation);
        let (revision_current, lifecycle_current, source) = checks;
        #[cfg(test)]
        let before_file_job = state.before_file_job.take();
        if !state.writer.submit(&self.file, move |file| {
            if !revision_current() {
                return;
            }
            #[cfg(test)]
            if let Some(pause) = before_file_job {
                pause();
            }
            // 同一路线拒绝与重新激活后的写回按队列顺序执行。
            let ResolvedNonce::Ready(nonce) = stamp.nonce.resolved() else {
                return;
            };
            if file
                .write(&account, route, nonce, &pending, saved_at, || {
                    generation.load(Ordering::Acquire) == stamp.generation && lifecycle_current()
                })
                .is_err()
            {
                tracing::warn!("业务会话缓存写回失败");
            }
        }) {
            tracing::warn!("业务会话缓存写回失败");
            return None;
        }
        let entries = &mut state.route(route).entries;
        for (scope, material) in changes {
            let slot = &mut entries[scope as usize];
            slot.version = slot.version.saturating_add(1);
            slot.saved_at = saved_at;
            slot.material = material;
            slot.source.clone_from(&source);
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
    ) -> Option<BusinessCacheStamp> {
        let mut state = self.lock();
        if !state.accepts(account, route, &stamp) {
            return None;
        }
        let entry = &mut state.route(route).entries[scope as usize];
        if same_material(entry.material.as_ref(), Some(&rejected)) {
            entry.invalidate();
        }
        let pending = Arc::new(RejectionNonce {
            proposed: rand::random(),
            completed: OnceLock::new(),
        });
        let completion = Arc::clone(&pending);
        let generation = Arc::clone(&state.generation);
        let epoch = stamp.generation;
        let account = account.to_owned();
        #[cfg(test)]
        let before_file_job = state.before_file_job.take();
        if !state.writer.submit(&self.file, move |file| {
            #[cfg(test)]
            if let Some(pause) = before_file_job {
                pause();
            }
            let ResolvedNonce::Ready(prior) = stamp.nonce.resolved() else {
                return;
            };
            let nonce = match file.reject(
                &account,
                route,
                prior,
                completion.proposed,
                (scope, &rejected),
                || generation.load(Ordering::Acquire) == epoch,
            ) {
                Ok(true) => Some(completion.proposed),
                Ok(false) => prior,
                Err(_) => {
                    tracing::warn!("业务会话缓存失效写回失败");
                    prior
                }
            };
            let _ = completion.completed.set(nonce);
        }) {
            tracing::warn!("业务会话缓存失效写回失败");
            return None;
        }
        let nonce = CacheNonce::Rejection(pending);
        state.route(route).nonce = Some(nonce.clone());
        Some(BusinessCacheStamp {
            generation: epoch,
            nonce,
        })
    }

    pub(crate) fn invalidate(&self, event: Invalidation) {
        let mut state = self.lock();
        if state.conflicted {
            return;
        }
        match event {
            Invalidation::SameAccountLogin(route) => {
                state.invalidate(route);
                state.writer.drain();
                if self.file.clear_route(route).is_err() {
                    tracing::warn!("业务会话缓存单路线登录清理失败");
                }
            }
            Invalidation::RevokeAll | Invalidation::AccountChanged => {
                state.invalidate_all();
                state.writer.drain();
                if self.file.clear().is_err() {
                    tracing::warn!("业务会话缓存全量清理失败");
                }
            }
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

pub(super) fn revoke_disk(store: &FileSessionStore, route: Option<ConnectionMode>) {
    let file = file::BusinessSessionFile::new(store.directory());
    let result = match route {
        Some(route) => file.clear_route(route),
        None => file.clear(),
    };
    if result.is_err() {
        tracing::warn!("业务会话缓存会话撤销失败");
    }
}
#[cfg(test)]
#[path = "business_cache_p2_tests.rs"]
mod p2_tests;
