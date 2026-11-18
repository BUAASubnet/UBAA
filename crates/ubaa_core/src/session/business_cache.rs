//! 只读 worker 在同一账号与路线内共享的业务会话材料。
mod cookies;
mod file;
mod writer;
pub(crate) use cookies::reusable_cookie_scope;

use super::{FileSessionStore, StoredCookie};
use crate::domain::ConnectionMode;
use crate::internal::route_state::{SpocCredential, StudentKind, YgdkCredential};
use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex, MutexGuard};

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
}

impl BusinessSeed {
    fn invalidate(&mut self) {
        self.version = self.version.saturating_add(1);
        self.material = None;
    }
}

pub(crate) type BusinessSeeds = [BusinessSeed; BusinessScope::ALL.len()];

#[derive(Default)]
struct State {
    account: Option<String>,
    direct: BusinessSeeds,
    webvpn: BusinessSeeds,
    generation: u64,
    writer: writer::Writer,
}

impl State {
    fn route(&mut self, route: ConnectionMode) -> &mut BusinessSeeds {
        match route {
            ConnectionMode::Direct => &mut self.direct,
            ConnectionMode::WebVpn => &mut self.webvpn,
        }
    }

    fn invalidate(&mut self, route: ConnectionMode) {
        for entry in self.route(route) {
            entry.invalidate();
        }
    }

    fn invalidate_all(&mut self) {
        self.invalidate(ConnectionMode::Direct);
        self.invalidate(ConnectionMode::WebVpn);
        self.generation = self.generation.saturating_add(1);
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
    ) -> (u64, BusinessSeeds) {
        let mut state = self.lock();
        if state.account.as_deref() != Some(account) {
            state.invalidate_all();
            state.account = Some(account.to_owned());
            match self.file.read() {
                Ok(Some(mut stored)) if stored.account == account => {
                    for route in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
                        for (scope, entry) in std::mem::take(stored.route(route)) {
                            let slot = &mut state.route(route)[scope as usize];
                            slot.saved_at = entry.saved_at;
                            slot.material = entry.material.for_scope(route, scope);
                        }
                    }
                }
                Ok(_) => {}
                Err(_) => tracing::warn!("业务会话缓存读取失败"),
            }
        }
        for (scope, seed) in BusinessScope::ALL.into_iter().zip(state.route(route)) {
            if seed.material.is_some() && scope.is_expired(seed.saved_at, now) {
                seed.invalidate();
            }
        }
        (state.generation, state.route(route).clone())
    }

    pub(crate) fn write(
        &self,
        account: &str,
        generation: u64,
        route: ConnectionMode,
        changes: Vec<(BusinessScope, Option<BusinessMaterial>)>,
        saved_at: i64,
        current: impl FnOnce() -> bool + Send + 'static,
    ) -> Option<BusinessSeeds> {
        let mut state = self.lock();
        if state.generation != generation || state.account.as_deref() != Some(account) {
            return None;
        }
        let account = account.to_owned();
        let pending = changes.clone();
        if !state.writer.submit(&self.file, move |file| {
            if file
                .write(&account, route, &pending, saved_at, current)
                .is_err()
            {
                tracing::warn!("业务会话缓存写回失败");
            }
        }) {
            tracing::warn!("业务会话缓存写回失败");
            return None;
        }
        let entries = state.route(route);
        for (scope, material) in changes {
            let slot = &mut entries[scope as usize];
            slot.version = slot.version.saturating_add(1);
            slot.saved_at = saved_at;
            slot.material = material;
        }
        Some(entries.clone())
    }

    pub(crate) fn reject(
        &self,
        account: &str,
        generation: u64,
        route: ConnectionMode,
        scope: BusinessScope,
        rejected: BusinessMaterial,
    ) {
        let mut state = self.lock();
        if state.generation != generation || state.account.as_deref() != Some(account) {
            return;
        }
        let entry = &mut state.route(route)[scope as usize];
        if same_material(entry.material.as_ref(), Some(&rejected)) {
            entry.invalidate();
        }
        let account = account.to_owned();
        if !state.writer.submit(&self.file, move |file| {
            if file.reject(&account, route, scope, &rejected).is_err() {
                tracing::warn!("业务会话缓存失效写回失败");
            }
        }) {
            tracing::warn!("业务会话缓存失效写回失败");
        }
    }

    pub(crate) fn clear_login(&self, account: Option<&str>, route: ConnectionMode) {
        let mut state = self.lock();
        if state.account.is_some() && state.account.as_deref() != account {
            state.invalidate_all();
        } else {
            state.invalidate(route);
        }
        state.writer.drain();
        if self.file.clear_login(account, route).is_err() {
            tracing::warn!("业务会话缓存登录清理失败");
        }
    }

    pub(crate) fn clear(&self) {
        let mut state = self.lock();
        state.invalidate_all();
        state.writer.drain();
        if self.file.clear().is_err() {
            tracing::warn!("业务会话缓存清理失败");
        }
    }
}

#[cfg(test)]
#[path = "business_cache_p2_tests.rs"]
mod p2_tests;
