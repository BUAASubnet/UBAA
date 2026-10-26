//! iHome 令牌仅存于当前路线内存；失效代数阻止迟到登录回写。
use std::sync::Mutex;
#[derive(Default)]
pub(crate) struct IhomeState {
    value: Mutex<(u64, Option<String>)>,
    login: tokio::sync::Mutex<()>,
    pub(crate) mutation: tokio::sync::Mutex<()>,
}
impl std::fmt::Debug for IhomeState {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("IhomeState([已隐藏])")
    }
}
impl IhomeState {
    pub(crate) fn snapshot(&self) -> (u64, Option<String>) {
        self.value
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }
    pub(crate) fn store(&self, generation: u64, token: String) -> bool {
        let mut v = self
            .value
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if v.0 != generation {
            return false;
        }
        v.1 = Some(token);
        true
    }
    pub(crate) fn clear(&self) {
        let mut v = self
            .value
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        v.0 = v.0.wrapping_add(1);
        v.1 = None;
    }
    pub(crate) async fn login_guard(&self) -> tokio::sync::MutexGuard<'_, ()> {
        self.login.lock().await
    }
}
