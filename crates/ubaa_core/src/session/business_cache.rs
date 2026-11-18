//! 只读 worker 在同一账号与路线内共享的业务 Cookie。
mod cookies;
mod file;
mod writer;
pub(crate) use cookies::reusable_cookie_scope;

use super::{FileSessionStore, StoredCookie};
use crate::domain::ConnectionMode;
use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex, MutexGuard};

#[derive(Clone, Copy, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "lowercase")]
pub(crate) enum BusinessScope {
    Byxt,
    Portal,
}

impl BusinessScope {
    pub(crate) const ALL: [Self; 2] = [Self::Byxt, Self::Portal];

    pub(crate) fn owns(self, route: ConnectionMode, cookie: &StoredCookie) -> bool {
        let host = match self {
            Self::Byxt => "byxt.buaa.edu.cn",
            Self::Portal => "it.buaa.edu.cn",
        };
        reusable_cookie_scope(route, cookie) == Some(host)
    }
}

pub(crate) fn same_material(left: &[StoredCookie], right: &[StoredCookie]) -> bool {
    left.len() == right.len()
        && left
            .iter()
            .all(|cookie| right.iter().any(|other| cookie.same_for_persistence(other)))
}

#[derive(Clone, Default)]
pub(crate) struct BusinessSeed {
    pub(crate) version: u64,
    pub(crate) cookies: Vec<StoredCookie>,
}

type Seeds = [BusinessSeed; 2];

#[derive(Default)]
struct State {
    account: Option<String>,
    direct: Seeds,
    webvpn: Seeds,
    generation: u64,
    writer: writer::Writer,
}

impl State {
    fn route(&mut self, route: ConnectionMode) -> &mut Seeds {
        match route {
            ConnectionMode::Direct => &mut self.direct,
            ConnectionMode::WebVpn => &mut self.webvpn,
        }
    }

    fn invalidate(&mut self, route: ConnectionMode) {
        for entry in self.route(route) {
            entry.version = entry.version.saturating_add(1);
            entry.cookies.clear();
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

    pub(crate) fn seeds(&self, account: &str, route: ConnectionMode) -> (u64, Seeds) {
        let mut state = self.lock();
        if state.account.as_deref() != Some(account) {
            state.invalidate_all();
            state.account = Some(account.to_owned());
            match self.file.read() {
                Ok(Some(mut stored)) if stored.account == account => {
                    for route in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
                        for (scope, entry) in std::mem::take(stored.route(route)) {
                            let file::Material::Cookies(mut cookies) = entry.material;
                            cookies.retain(|cookie| scope.owns(route, cookie));
                            state.route(route)[scope as usize].cookies = cookies;
                        }
                    }
                }
                Ok(_) => {}
                Err(_) => tracing::warn!("业务会话缓存读取失败"),
            }
        }
        (state.generation, state.route(route).clone())
    }

    pub(crate) fn write(
        &self,
        account: &str,
        generation: u64,
        route: ConnectionMode,
        changes: Vec<(BusinessScope, Vec<StoredCookie>)>,
        saved_at: i64,
        current: impl FnOnce() -> bool + Send + 'static,
    ) -> Option<Seeds> {
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
        for (scope, cookies) in changes {
            let slot = &mut entries[scope as usize];
            slot.version = slot.version.saturating_add(1);
            slot.cookies = cookies;
        }
        Some(entries.clone())
    }

    pub(crate) fn reject(
        &self,
        account: &str,
        generation: u64,
        route: ConnectionMode,
        scope: BusinessScope,
        rejected: &[StoredCookie],
    ) {
        let mut state = self.lock();
        if state.generation != generation || state.account.as_deref() != Some(account) {
            return;
        }
        let entry = &mut state.route(route)[scope as usize];
        if same_material(&entry.cookies, rejected) {
            entry.version = entry.version.saturating_add(1);
            entry.cookies.clear();
        }
        let account = account.to_owned();
        let rejected = rejected.to_vec();
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
