//! 接续 FRB 的原钩子。遥测在独立线程写队列，panic 线程不等待数据库。

use super::Inner;
use std::{
    cell::Cell,
    future::{Future, poll_fn},
    panic::PanicHookInfo,
    sync::{Arc, Mutex, Once, Weak, mpsc},
};
use ubaa_core::facade::{ErrorKind, app_service as core};

static ACTIVE: Mutex<Option<Weak<Inner>>> = Mutex::new(None);

thread_local! {
    static SUPPRESSED: Cell<bool> = const { Cell::new(false) };
}

pub(in crate::api) fn suppress<T>(operation: impl FnOnce() -> T) -> T {
    struct Restore(bool);
    impl Drop for Restore {
        fn drop(&mut self) {
            SUPPRESSED.with(|value| value.set(self.0));
        }
    }
    let _restore = Restore(SUPPRESSED.with(|value| value.replace(true)));
    operation()
}

pub(super) async fn suppress_async<T>(operation: impl Future<Output = T>) -> T {
    let mut operation = Box::pin(operation);
    // 异步任务可切换线程，抑制范围只覆盖当前线程的这次轮询。
    poll_fn(|context| suppress(|| operation.as_mut().poll(context))).await
}

pub(super) fn register(inner: &Arc<Inner>) {
    if let Ok(mut active) = ACTIVE.lock() {
        *active = Some(Arc::downgrade(inner));
    }
}

struct PanicEvent {
    app_service: Weak<Inner>,
    account: Option<Arc<core::ConfirmedAccount>>,
    source: Option<String>,
}

pub(in crate::api) fn install() {
    static INSTALL: Once = Once::new();
    INSTALL.call_once(|| {
        let (send, receive) = mpsc::sync_channel::<PanicEvent>(16);
        let worker = std::thread::Builder::new()
            .name("ubaa-panic-telemetry".into())
            .spawn(move || {
                while let Ok(event) = receive.recv() {
                    if let Some(inner) = event.app_service.upgrade() {
                        suppress(|| {
                            let _ = inner
                                .core
                                .enqueue(&telemetry_event(event.source), event.account.as_deref());
                        });
                    }
                }
            });
        if worker.is_err() {
            return;
        }
        chain(move |source| {
            let Ok(active) = ACTIVE.try_lock() else {
                return;
            };
            if let Some(inner) = active.as_ref().and_then(Weak::upgrade) {
                let account = inner
                    .account
                    .try_lock()
                    .ok()
                    .and_then(|account| account.clone());
                let _ = send.try_send(PanicEvent {
                    app_service: Arc::downgrade(&inner),
                    account,
                    source,
                });
            }
        });
    });
}

fn chain(record: impl Fn(Option<String>) + Send + Sync + 'static) {
    let previous = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        if matches!(SUPPRESSED.try_with(Cell::get), Ok(false)) {
            record(source_from_panic(info));
        }
        previous(info);
    }));
}

fn source_from_panic(info: &PanicHookInfo<'_>) -> Option<String> {
    let location = info.location()?;
    rust_source(location.file(), location.line())
}

fn rust_source(path: &str, line: u32) -> Option<String> {
    let path = path.replace('\\', "/");
    let manifest = env!("CARGO_MANIFEST_DIR").replace('\\', "/");
    let (repository, _) = manifest.rsplit_once("/crates/")?;
    let path = path
        .strip_prefix(repository)
        .and_then(|value| value.strip_prefix('/'))
        .unwrap_or(&path);
    let (package, file) = path.strip_prefix("crates/ubaa_")?.split_once("/src/")?;
    let stem = file.strip_suffix(".rs")?;
    if package.is_empty()
        || !package.bytes().all(|b| b.is_ascii_lowercase() || b == b'_')
        || stem.is_empty()
        || !stem
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'_' | b'/'))
        || stem.starts_with("app_service/")
        || stem.starts_with("api/app_service/")
    {
        return None;
    }
    let source = format!("{path}:{line}");
    (source.len() <= 128).then_some(source)
}

fn telemetry_event(source: Option<String>) -> core::TelemetryEvent {
    core::TelemetryEvent::Error(core::ErrorDimensions {
        event: core::ErrorEvent::Crash,
        feature: core::Feature::App,
        route: core::Route::None,
        error_code: "panic".into(),
        error_kind: ErrorKind::Internal,
        retryable: false,
        source,
    })
}

#[cfg(test)]
mod tests {
    use super::rust_source;

    #[test]
    fn 只保留受支持的仓库源码位置且排除遥测自身() {
        assert_eq!(
            rust_source(r"crates\ubaa_core\src\facade\auth.rs", 8).as_deref(),
            Some("crates/ubaa_core/src/facade/auth.rs:8")
        );
        let absolute = format!("{}/src/api/simple.rs", env!("CARGO_MANIFEST_DIR"));
        assert_eq!(
            rust_source(&absolute, 3).as_deref(),
            Some("crates/ubaa_flutter_bridge/src/api/simple.rs:3")
        );
        for path in [
            "/foreign/crates/ubaa_core/src/lib.rs",
            "crates/ubaa_core/src/../lib.rs",
            "crates/ubaa_core/src/app_service/service.rs",
            "crates/ubaa_flutter_bridge/src/api/app_service/mod.rs",
        ] {
            assert!(rust_source(path, 1).is_none());
        }
    }
}
