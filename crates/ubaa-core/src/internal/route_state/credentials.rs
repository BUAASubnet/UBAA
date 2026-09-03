//! 路线内业务凭据及其单飞/失效状态。

use std::sync::Mutex as SyncMutex;
use std::sync::atomic::{AtomicU64, Ordering};

#[cfg(test)]
use std::sync::{Arc, Condvar, Mutex as TestMutex};

use tokio::sync::Mutex;

/// 博雅业务令牌，只在当前路线的内存状态中保存。
#[derive(Clone)]
pub(crate) struct BykcCredential {
    pub(crate) token: String,
}

impl std::fmt::Debug for BykcCredential {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("BykcCredential")
            .field("token", &"[已隐藏]")
            .finish()
    }
}

/// 图书馆业务令牌，只在当前路线的内存状态中保存。
#[derive(Clone)]
pub(crate) struct LibBookCredential {
    pub(crate) token: String,
}

impl std::fmt::Debug for LibBookCredential {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("LibBookCredential")
            .field("token", &"[已隐藏]")
            .finish()
    }
}

/// 阳光打卡业务凭据，只在当前路线的内存状态中保存。
#[derive(Clone)]
pub(crate) struct YgdkCredential {
    pub(crate) uid: i32,
    pub(crate) token: String,
}

impl std::fmt::Debug for YgdkCredential {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("YgdkCredential")
            .field("uid", &self.uid)
            .field("token", &"[已隐藏]")
            .finish()
    }
}

/// iClass 业务凭据，只在当前路线的内存状态中保存。
#[allow(dead_code)]
#[derive(Clone)]
pub(crate) struct SigninCredential {
    pub(crate) user_id: String,
    pub(crate) session_id: String,
}

impl std::fmt::Debug for SigninCredential {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("SigninCredential")
            .field("user_id", &"[已隐藏]")
            .field("session_id", &"[已隐藏]")
            .finish()
    }
}

/// SPOC 业务凭据，只在当前路线的内存状态中保存。
#[derive(Clone, Eq, PartialEq)]
pub(crate) struct SpocCredential {
    pub(crate) token: String,
    pub(crate) role: String,
}

impl SpocCredential {
    pub(crate) fn new(token: String, role: String) -> Self {
        Self { token, role }
    }

    pub(crate) fn token_header(&self) -> String {
        format!("Inco-{}", self.token)
    }
}

impl std::fmt::Debug for SpocCredential {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("SpocCredential")
            .field("token", &"[已隐藏]")
            .field("role", &self.role)
            .finish()
    }
}

/// 路线内的场馆预约业务状态。
#[derive(Default)]
pub(crate) struct CgyyState {
    token: SyncMutex<Option<String>>,
    login: Mutex<()>,
}

impl CgyyState {
    pub(crate) fn token(&self) -> Option<String> {
        self.token
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    pub(crate) fn set(&self, token: String) {
        *self
            .token
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(token);
    }

    pub(crate) async fn login_guard(&self) -> tokio::sync::MutexGuard<'_, ()> {
        self.login.lock().await
    }

    pub(crate) fn clear(&self) {
        *self
            .token
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = None;
    }
}

impl std::fmt::Debug for CgyyState {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("CgyyState")
            .field("token", &"[已隐藏]")
            .field("login", &"[已隐藏]")
            .finish()
    }
}

/// 路线内的博雅业务状态。
#[allow(dead_code)]
#[derive(Debug, Default)]
pub(crate) struct BykcState {
    credential: SyncMutex<Option<BykcCredential>>,
    login: Mutex<()>,
}

#[allow(dead_code)]
impl BykcState {
    pub(crate) fn credential(&self) -> Option<BykcCredential> {
        self.credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    pub(crate) fn set(&self, value: BykcCredential) {
        *self
            .credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(value);
    }

    pub(crate) async fn login_guard(&self) -> tokio::sync::MutexGuard<'_, ()> {
        self.login.lock().await
    }

    pub(crate) fn clear(&self) {
        *self
            .credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = None;
    }
}

/// 路线内的图书馆业务状态。
#[derive(Debug, Default)]
pub(crate) struct LibBookState {
    credential: SyncMutex<Option<LibBookCredential>>,
    login: Mutex<()>,
}

impl LibBookState {
    pub(crate) fn credential(&self) -> Option<LibBookCredential> {
        self.credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    pub(crate) fn set(&self, value: LibBookCredential) {
        *self
            .credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(value);
    }

    pub(crate) fn clear_credential(&self) {
        *self
            .credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = None;
    }

    pub(crate) async fn login_guard(&self) -> tokio::sync::MutexGuard<'_, ()> {
        self.login.lock().await
    }

    pub(crate) fn clear(&self) {
        self.clear_credential();
    }
}

/// 路线内的阳光打卡业务状态。
#[allow(dead_code)]
#[derive(Default)]
pub(crate) struct YgdkState {
    credential: SyncMutex<Option<YgdkCredential>>,
    login: Mutex<()>,
}

impl std::fmt::Debug for YgdkState {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("YgdkState")
            .field("credential", &"[已隐藏]")
            .field("login", &"[已隐藏]")
            .finish()
    }
}

impl YgdkState {
    #[allow(dead_code)]
    pub(crate) fn credential(&self) -> Option<YgdkCredential> {
        self.credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    #[allow(dead_code)]
    pub(crate) fn set(&self, value: YgdkCredential) {
        *self
            .credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(value);
    }

    pub(crate) fn clear(&self) {
        *self
            .credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = None;
    }

    #[allow(dead_code)]
    pub(crate) async fn login_guard(&self) -> tokio::sync::MutexGuard<'_, ()> {
        self.login.lock().await
    }
}

#[cfg(test)]
#[derive(Default)]
pub(crate) struct StoreCredentialHook {
    flags: TestMutex<(bool, bool)>,
    signal: Condvar,
}

#[cfg(test)]
impl StoreCredentialHook {
    fn pause(&self) {
        let mut flags = self
            .flags
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        flags.0 = true;
        self.signal.notify_all();
        while !flags.1 {
            flags = self
                .signal
                .wait(flags)
                .unwrap_or_else(std::sync::PoisonError::into_inner);
        }
    }

    pub(crate) fn wait_until_paused(&self) {
        let mut flags = self
            .flags
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        while !flags.0 {
            flags = self
                .signal
                .wait(flags)
                .unwrap_or_else(std::sync::PoisonError::into_inner);
        }
    }

    pub(crate) fn release(&self) {
        let mut flags = self
            .flags
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        flags.1 = true;
        self.signal.notify_all();
    }
}

/// 路线内的 iClass 业务状态。
#[allow(dead_code)]
#[derive(Default)]
pub(crate) struct SigninState {
    invalidations: AtomicU64,
    login: Mutex<()>,
    credential: SyncMutex<Option<SigninCredential>>,
    #[cfg(test)]
    store_hook: TestMutex<Option<Arc<StoreCredentialHook>>>,
}

impl SigninState {
    pub(crate) fn generation(&self) -> u64 {
        self.invalidations.load(Ordering::Acquire)
    }

    pub(crate) fn credential(&self) -> Option<SigninCredential> {
        self.credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    pub(crate) async fn login_guard(&self) -> tokio::sync::MutexGuard<'_, ()> {
        self.login.lock().await
    }

    pub(crate) fn store_credential(&self, generation: u64, credential: SigninCredential) -> bool {
        if self.generation() != generation {
            return false;
        }
        #[cfg(test)]
        self.pause_after_generation_check();
        *self
            .credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(credential);
        true
    }

    #[cfg(test)]
    pub(crate) fn set_store_hook(&self, hook: Arc<StoreCredentialHook>) {
        *self
            .store_hook
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(hook);
    }

    #[cfg(test)]
    fn pause_after_generation_check(&self) {
        let hook = self
            .store_hook
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        if let Some(hook) = hook {
            hook.pause();
        }
    }

    pub(crate) fn clear_credential(&self) {
        *self
            .credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = None;
    }

    pub(crate) fn clear(&self) {
        self.invalidations.fetch_add(1, Ordering::AcqRel);
        self.clear_credential();
    }
}

impl std::fmt::Debug for SigninState {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("SigninState")
            .field("generation", &self.generation())
            .field("credential", &"[已隐藏]")
            .finish()
    }
}

/// 路线内的 SPOC 业务状态。
#[derive(Default)]
pub(crate) struct SpocState {
    invalidations: AtomicU64,
    login: Mutex<()>,
    credential: SyncMutex<Option<SpocCredential>>,
}

impl SpocState {
    pub(crate) fn credential(&self) -> Option<SpocCredential> {
        self.credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    pub(crate) fn store_credential(&self, generation: u64, credential: SpocCredential) -> bool {
        let mut cached = self
            .credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if self.generation() != generation {
            return false;
        }
        *cached = Some(credential);
        true
    }

    pub(crate) fn clear_credential(&self) {
        *self
            .credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = None;
    }

    pub(crate) async fn login_guard(&self) -> tokio::sync::MutexGuard<'_, ()> {
        self.login.lock().await
    }

    pub(crate) fn generation(&self) -> u64 {
        self.invalidations.load(Ordering::Acquire)
    }

    pub(crate) fn clear(&self) {
        self.invalidations.fetch_add(1, Ordering::AcqRel);
        // 并发持有者可能仍在使用旧凭据；代数检查可防止失效后重新填充此缓存。
        let mut credential = self
            .credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        *credential = None;
    }
}

impl std::fmt::Debug for SpocState {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("SpocState")
            .field("generation", &self.generation())
            .field("credential", &"[已隐藏]")
            .finish()
    }
}

#[cfg(test)]
mod tests {
    use super::{YgdkCredential, YgdkState};

    #[test]
    fn 阳光打卡状态调试输出不泄露令牌() {
        let state = YgdkState::default();
        state.set(YgdkCredential {
            uid: 42,
            token: "ygdk-state-secret-token".into(),
        });
        let rendered = format!("{state:?}");
        assert!(!rendered.contains("ygdk-state-secret-token"));
    }
}
