//! Route-owned, process-local state for read-only feature workflows.

use std::future::Future;
use std::sync::atomic::{AtomicU64, Ordering};

use tokio::sync::Mutex;

/// State shared only by runtimes and read workers for one route/client.
#[derive(Debug, Default)]
pub(crate) struct RouteFeatureState {
    pub(crate) classroom: ClassroomState,
    pub(crate) spoc: SpocState,
    pub(crate) judge: JudgeState,
}

impl RouteFeatureState {
    pub(crate) fn clear(&self) {
        self.classroom.clear();
        self.spoc.clear();
        self.judge.clear();
    }
}

/// Once-per-route Classroom bootstrap state.
#[derive(Debug, Default)]
pub(crate) struct ClassroomState {
    sync: Mutex<()>,
    // The low bit is the synchronized flag. Higher bits form an invalidation generation.
    generation_and_synced: AtomicU64,
}

impl ClassroomState {
    pub(crate) async fn ensure_synced<F, Fut>(&self, synchronize: F)
    where
        F: FnOnce() -> Fut,
        Fut: Future<Output = bool>,
    {
        if self.is_synced() {
            return;
        }
        let _guard = self.sync.lock().await;
        if self.is_synced() {
            return;
        }
        let generation = self.generation_and_synced.load(Ordering::Acquire);
        if synchronize().await {
            let _ = self.generation_and_synced.compare_exchange(
                generation,
                generation | 1,
                Ordering::AcqRel,
                Ordering::Acquire,
            );
        }
    }

    fn is_synced(&self) -> bool {
        self.generation_and_synced.load(Ordering::Acquire) & 1 == 1
    }

    pub(crate) fn clear(&self) {
        let _ =
            self.generation_and_synced
                .fetch_update(Ordering::AcqRel, Ordering::Acquire, |state| {
                    Some((state & !1).wrapping_add(2))
                });
    }
}

/// Route-owned SPOC state, populated by the SPOC migration phase.
#[derive(Debug, Default)]
pub(crate) struct SpocState {
    invalidations: AtomicU64,
}

impl SpocState {
    fn clear(&self) {
        self.invalidations.fetch_add(1, Ordering::AcqRel);
    }
}

/// Placeholder for route-owned Judge caches added by the Judge migration phase.
#[derive(Debug, Default)]
pub(crate) struct JudgeState {
    invalidations: AtomicU64,
}

impl JudgeState {
    fn clear(&self) {
        self.invalidations.fetch_add(1, Ordering::AcqRel);
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::time::Duration;

    use super::ClassroomState;

    #[test]
    fn concurrent_classroom_bootstraps_use_one_double_checked_sync() {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_time()
            .build()
            .unwrap();
        runtime.block_on(async {
            let state = Arc::new(ClassroomState::default());
            let calls = Arc::new(AtomicUsize::new(0));
            let first_state = Arc::clone(&state);
            let first_calls = Arc::clone(&calls);
            let second_state = Arc::clone(&state);
            let second_calls = Arc::clone(&calls);

            let first = tokio::spawn(async move {
                first_state
                    .ensure_synced(|| async move {
                        first_calls.fetch_add(1, Ordering::SeqCst);
                        tokio::time::sleep(Duration::from_millis(10)).await;
                        true
                    })
                    .await;
            });
            let second = tokio::spawn(async move {
                second_state
                    .ensure_synced(|| async move {
                        second_calls.fetch_add(1, Ordering::SeqCst);
                        true
                    })
                    .await;
            });
            first.await.unwrap();
            second.await.unwrap();

            assert_eq!(calls.load(Ordering::SeqCst), 1);
        });
    }

    #[test]
    fn failed_or_cleared_classroom_sync_remains_retryable() {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .build()
            .unwrap();
        runtime.block_on(async {
            let state = ClassroomState::default();
            let calls = AtomicUsize::new(0);

            state
                .ensure_synced(|| async {
                    calls.fetch_add(1, Ordering::SeqCst);
                    false
                })
                .await;
            state
                .ensure_synced(|| async {
                    calls.fetch_add(1, Ordering::SeqCst);
                    true
                })
                .await;
            state.clear();
            state
                .ensure_synced(|| async {
                    calls.fetch_add(1, Ordering::SeqCst);
                    true
                })
                .await;

            assert_eq!(calls.load(Ordering::SeqCst), 3);
        });
    }
}
