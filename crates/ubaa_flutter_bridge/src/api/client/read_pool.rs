//! 不同业务共享读取许可，认证和写入使用同一把写锁。
use super::client::{BridgeError, disposed_error};
use std::ops::{Deref, DerefMut};
use tokio::sync::{
    Mutex, MutexGuard, RwLock, RwLockReadGuard, RwLockWriteGuard, Semaphore, SemaphorePermit,
    TryLockError,
};
use ubaa_core::facade::UbaaClient;

#[derive(Clone, Copy)]
pub(crate) enum ReadGroup {
    Academic,
    Signin,
    Spoc,
    Judge,
    Ygdk,
    Bykc,
    Cgyy,
    Profile,
}

pub(crate) struct ClientPool {
    primary: Mutex<Option<UbaaClient>>,
    groups: [ReadSlot; 8],
    barrier: RwLock<()>,
    permits: Semaphore,
}

struct ReadSlot {
    permit: Semaphore,
    client: Mutex<Option<UbaaClient>>,
}

pub(crate) struct ClientGuard<'a> {
    client: MutexGuard<'a, Option<UbaaClient>>,
    _read: Option<RwLockReadGuard<'a, ()>>,
    _write: Option<RwLockWriteGuard<'a, ()>>,
    _permit: Option<SemaphorePermit<'a>>,
    _group: Option<SemaphorePermit<'a>>,
}

impl Deref for ClientGuard<'_> {
    type Target = Option<UbaaClient>;
    fn deref(&self) -> &Self::Target {
        &self.client
    }
}
impl DerefMut for ClientGuard<'_> {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.client
    }
}

impl ClientPool {
    pub(crate) fn new(client: UbaaClient) -> Self {
        Self {
            primary: Mutex::new(Some(client)),
            groups: std::array::from_fn(|_| ReadSlot {
                permit: Semaphore::new(1),
                client: Mutex::new(None),
            }),
            barrier: RwLock::new(()),
            permits: Semaphore::new(4),
        }
    }

    pub(crate) async fn lock(&self) -> ClientGuard<'_> {
        let barrier = self.barrier.write().await;
        ClientGuard {
            client: self.primary.lock().await,
            _read: None,
            _write: Some(barrier),
            _permit: None,
            _group: None,
        }
    }

    pub(crate) fn try_lock(&self) -> Result<ClientGuard<'_>, TryLockError> {
        let barrier = self.barrier.try_write()?;
        Ok(ClientGuard {
            client: self.primary.try_lock()?,
            _read: None,
            _write: Some(barrier),
            _permit: None,
            _group: None,
        })
    }

    pub(crate) async fn read(
        &self,
        group: Option<ReadGroup>,
    ) -> Result<ClientGuard<'_>, BridgeError> {
        let Some(group) = group else {
            return Ok(self.lock().await);
        };
        // 同组排队时不持共享许可，避免一串尚未开始的读取挡住写方。
        let slot = &self.groups[group as usize];
        let group_permit = slot.permit.acquire().await.map_err(|_| disposed_error())?;
        let permit = self.permits.acquire().await.map_err(|_| disposed_error())?;
        let barrier = self.barrier.read().await;
        let mut client = slot.client.lock().await;
        let mut primary = self.primary.lock().await;
        let parent = primary.as_mut().ok_or_else(disposed_error)?;
        let current = match client.as_mut() {
            Some(worker) => worker
                .synchronize_parallel_readonly(parent)
                .map_err(|error| BridgeError::from_core(error, None))?,
            None => false,
        };
        if !current {
            *client = Some(
                parent
                    .fork_parallel_readonly()
                    .map_err(|error| BridgeError::from_core(error, None))?,
            );
        }
        drop(primary);
        Ok(ClientGuard {
            client,
            _read: Some(barrier),
            _write: None,
            _permit: Some(permit),
            _group: Some(group_permit),
        })
    }

    /// 调用方已经持有独占 guard；等待许可的读取尚未占用 worker 锁。
    pub(crate) async fn clear_readers(&self) {
        for slot in &self.groups {
            *slot.client.lock().await = None;
        }
    }
}

#[cfg(test)]
#[path = "read_pool_tests.rs"]
mod tests;
