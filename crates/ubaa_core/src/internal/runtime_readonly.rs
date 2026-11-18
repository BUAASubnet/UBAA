//! 并行读取只更新自身业务会话材料，不竞争主客户端的持久会话修订。
use super::ClientRuntime;
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::internal::route_state::RouteFeatureState;
use crate::session::business_cache::{
    BusinessMaterial, BusinessScope, BusinessSeeds, reusable_cookie_scope, same_material,
};
use crate::session::{CookieJar, StoredCookie};
use std::sync::{Arc, Weak};

#[derive(Clone)]
pub(super) struct ReadonlyOwner {
    state: Weak<RouteFeatureState>,
    generation: u64,
    business_cache_account: Option<String>,
    business_cache_generation: u64,
    business_seeds: Box<BusinessSeeds>,
    #[cfg(test)]
    invalidate_hook: Option<Arc<dyn Fn() + Send + Sync>>,
}
impl ReadonlyOwner {
    pub(super) fn invalidate(&self) {
        if let Some(state) = self.state.upgrade()
            && state.lifecycle_generation() == self.generation
        {
            #[cfg(test)]
            if let Some(hook) = &self.invalidate_hook {
                hook();
            }
            // 前面的快照仅用于跳过已过期归属；最终比较与完整清理必须共用锁。
            state.clear_if_generation(self.generation);
        }
    }
    fn current(&self) -> bool {
        self.state
            .upgrade()
            .is_some_and(|state| state.lifecycle_generation() == self.generation)
    }
}

impl ClientRuntime {
    pub(crate) fn fork_parallel_readonly(&mut self) -> Self {
        let mode = self.mode();
        let use_business_cache = self.business_sessions.is_some();
        let mut child = self.fork_for_readonly_with_cookie_filter(|cookie| {
            !use_business_cache || reusable_cookie_scope(mode, cookie).is_none()
        });
        child.readonly_generation = Some(ReadonlyOwner {
            state: Arc::downgrade(&self.feature_state),
            generation: self.feature_state.lifecycle_generation(),
            business_cache_account: None,
            business_cache_generation: 0,
            business_seeds: Box::default(),
            #[cfg(test)]
            invalidate_hook: None,
        });
        // Token 可能依赖业务 Cookie；两者一起留在同组，主写客户端独立激活。
        child.feature_state = Arc::new(RouteFeatureState::default());
        child.synchronize_business_sessions(self.account_name());
        child
    }

    #[cfg(test)]
    pub(crate) fn set_readonly_invalidate_hook(&mut self, hook: Arc<dyn Fn() + Send + Sync>) {
        self.readonly_generation.as_mut().unwrap().invalidate_hook = Some(hook);
    }

    pub(crate) fn synchronize_readonly(&mut self, parent: &Self) -> bool {
        if !self.belongs_to(parent) {
            return false;
        }
        // 调用方持有认证与写入的排他边界。
        self.session_revision = parent.session_revision;
        self.synchronize_business_sessions(parent.account_name());
        true
    }

    fn belongs_to(&self, parent: &Self) -> bool {
        parent.readonly_generation.is_none()
            && self.mode == parent.mode
            && self.authentication_generation == parent.authentication_generation
            && self.readonly_generation.as_ref().is_some_and(|owner| {
                Weak::ptr_eq(&owner.state, &Arc::downgrade(&parent.feature_state))
                    && owner.current()
            })
    }

    fn synchronize_business_sessions(&mut self, account: Option<&str>) {
        let mode = self.mode();
        let now = super::now_seconds_at(self.now());
        let (Some(cache), Some(owner)) = (&self.business_sessions, &mut self.readonly_generation)
        else {
            return;
        };
        if owner
            .business_cache_account
            .as_deref()
            .is_some_and(|prior| Some(prior) != account)
        {
            for scope in BusinessScope::ALL {
                apply_business_seed(&mut self.jar, &self.feature_state, mode, scope, None);
            }
            *owner.business_seeds = Default::default();
        }
        owner.business_cache_account = account.map(str::to_owned);
        let Some(account) = account else {
            return;
        };
        let Ok(now) = now else {
            tracing::warn!("业务会话缓存读取失败");
            return;
        };
        let (generation, seeds) = cache.seeds(account, mode, now);
        owner.business_cache_generation = generation;
        for (scope, mut latest) in BusinessScope::ALL.into_iter().zip(seeds) {
            let seed = &mut owner.business_seeds[scope as usize];
            if latest.version > seed.version
                && same_material(
                    business_material(&self.jar, &self.feature_state, mode, scope).as_ref(),
                    seed.material.as_ref(),
                )
                && apply_business_seed(
                    &mut self.jar,
                    &self.feature_state,
                    mode,
                    scope,
                    latest.material.as_ref(),
                )
            {
                latest.material = business_material(&self.jar, &self.feature_state, mode, scope);
                *seed = latest;
            }
        }
    }

    pub(crate) fn persist_business_session(&mut self) {
        let mode = self.mode();
        let (Some(cache), Some(owner)) = (&self.business_sessions, &self.readonly_generation)
        else {
            return;
        };
        let Some(account) = owner.business_cache_account.as_deref() else {
            return;
        };
        let changes: Vec<_> = BusinessScope::ALL
            .into_iter()
            .filter_map(|scope| {
                let material = business_material(&self.jar, &self.feature_state, mode, scope);
                (!same_material(
                    material.as_ref(),
                    owner.business_seeds[scope as usize].material.as_ref(),
                ))
                .then_some((scope, material))
            })
            .collect();
        if changes.is_empty()
            || self.ensure_session_revision().is_err()
            || self.check_authentication_scope().is_err()
        {
            return;
        }
        let Ok(saved_at) = super::now_seconds_at(self.now()) else {
            tracing::warn!("业务会话缓存写回失败");
            return;
        };
        let updated_scopes =
            BusinessScope::ALL.map(|scope| changes.iter().any(|(key, _)| scope == *key));
        let store = Arc::clone(&self.store);
        let revision = self.session_revision;
        // 排队过程中另一个进程可以替换主会话，持旁车锁时再次核对所有权。
        let current = move || {
            store
                .is_revision_current(revision)
                .is_ok_and(|current| current)
        };
        if let Some(seeds) = cache.write(
            account,
            owner.business_cache_generation,
            mode,
            changes,
            saved_at,
            current,
        ) {
            let owner = self.readonly_generation.as_mut().expect("已验证读组归属");
            for (index, seed) in seeds.into_iter().enumerate() {
                if updated_scopes[index] {
                    owner.business_seeds[index] = seed;
                }
            }
        }
    }

    pub(crate) fn business_cookies_for_rejection(
        &self,
        scope: BusinessScope,
    ) -> Option<Vec<StoredCookie>> {
        self.readonly_generation
            .as_ref()?
            .business_cache_account
            .as_ref()?;
        Some(scope_cookies(&self.jar, self.mode(), scope))
    }

    pub(crate) fn reject_business_session(
        &mut self,
        scope: BusinessScope,
        rejected: &[StoredCookie],
    ) {
        self.reject_business_material(scope, BusinessMaterial::Cookies(rejected.to_vec()));
    }

    /// 从只读业务缓存删除仍匹配的材料；凭据槽位由原业务失效分支清理。
    pub(crate) fn reject_business_material(
        &mut self,
        scope: BusinessScope,
        rejected: BusinessMaterial,
    ) {
        let mode = self.mode();
        let (Some(cache), Some(owner)) = (&self.business_sessions, &mut self.readonly_generation)
        else {
            return;
        };
        let Some(account) = owner.business_cache_account.as_deref() else {
            return;
        };
        if !matches!(&rejected, BusinessMaterial::Cookies(cookies) if cookies.is_empty()) {
            cache.reject(
                account,
                owner.business_cache_generation,
                mode,
                scope,
                rejected,
            );
        }
        if matches!(scope, BusinessScope::Byxt | BusinessScope::Portal) {
            self.jar.retain(|cookie| !scope.owns(mode, cookie));
        }
        owner.business_seeds[scope as usize].material = None;
    }

    pub(super) fn ensure_readonly_generation(&self) -> Result<()> {
        if self
            .readonly_generation
            .as_ref()
            .is_some_and(|owner| !owner.current())
        {
            return Err(UbaaError::new(
                ErrorCode::AuthenticationRequired,
                ErrorKind::Authentication,
                false,
                "读取所属会话已失效",
            ));
        }
        Ok(())
    }

    pub(crate) fn ensure_primary_client(&self) -> Result<()> {
        if self.readonly_generation.is_some() {
            return Err(UbaaError::new(
                ErrorCode::InvalidInput,
                ErrorKind::Input,
                false,
                "只读实例不能执行登录、注销或学校写入",
            ));
        }
        Ok(())
    }
}

fn business_material(
    jar: &CookieJar,
    state: &RouteFeatureState,
    mode: crate::domain::ConnectionMode,
    scope: BusinessScope,
) -> Option<BusinessMaterial> {
    match scope {
        BusinessScope::Byxt | BusinessScope::Portal => {
            let cookies = scope_cookies(jar, mode, scope);
            (!cookies.is_empty()).then_some(BusinessMaterial::Cookies(cookies))
        }
        BusinessScope::Identity => state
            .cached_academic_identity()
            .map(BusinessMaterial::Identity),
        BusinessScope::Spoc => state.spoc.credential().map(BusinessMaterial::Spoc),
        BusinessScope::Ygdk => state.ygdk.credential().map(BusinessMaterial::Ygdk),
    }
}

fn apply_business_seed(
    jar: &mut CookieJar,
    state: &RouteFeatureState,
    mode: crate::domain::ConnectionMode,
    scope: BusinessScope,
    material: Option<&BusinessMaterial>,
) -> bool {
    match (scope, material) {
        (BusinessScope::Byxt | BusinessScope::Portal, Some(BusinessMaterial::Cookies(cookies))) => {
            apply_cookie_seed(jar, cookies);
        }
        (BusinessScope::Byxt | BusinessScope::Portal, None) => {
            jar.retain(|cookie| !scope.owns(mode, cookie));
        }
        (BusinessScope::Identity, Some(BusinessMaterial::Identity(kind))) => {
            state.seed_academic_identity(Some(*kind));
        }
        (BusinessScope::Identity, None) => state.seed_academic_identity(None),
        (BusinessScope::Spoc, Some(BusinessMaterial::Spoc(credential))) => {
            return state
                .spoc
                .store_credential(state.spoc.generation(), credential.clone());
        }
        (BusinessScope::Ygdk, Some(BusinessMaterial::Ygdk(credential))) => {
            return state
                .ygdk
                .store_credential(state.ygdk.generation(), credential.clone());
        }
        (BusinessScope::Spoc, None) => state.spoc.clear(),
        (BusinessScope::Ygdk, None) => state.ygdk.clear(),
        _ => return false,
    }
    true
}

fn scope_cookies(
    jar: &CookieJar,
    mode: crate::domain::ConnectionMode,
    scope: BusinessScope,
) -> Vec<StoredCookie> {
    jar.cookies()
        .iter()
        .filter(|cookie| scope.owns(mode, cookie))
        .cloned()
        .collect()
}

fn apply_cookie_seed(jar: &mut CookieJar, seed: &[StoredCookie]) {
    let mut cookies = jar.cookies().to_vec();
    for incoming in seed {
        if let Some(existing) = cookies.iter_mut().find(|cookie| cookie.same_key(incoming)) {
            *existing = incoming.clone();
        } else {
            cookies.push(incoming.clone());
        }
    }
    jar.replace(cookies);
}

#[cfg(test)]
#[path = "runtime_readonly_tests.rs"]
mod tests;
