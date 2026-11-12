use super::{
    AgendaSyncDocument, AgendaSyncError, AgendaSyncSnapshot,
    pending::{PendingOperation, PublicationReceipt, SyncAttempt},
    publication::Publication,
    transaction::RestoredAttempt,
};
use crate::{
    agenda::AgendaStore,
    cache::{CacheError, CacheResult},
    domain::agenda::AgendaTime,
};
use async_trait::async_trait;
use std::collections::BTreeMap;

/// 一次明确触发的同步作业，失败后不会在作业内重新上传。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AgendaSyncAction {
    Pull,
    Push,
    CreateConfirmed,
}
/// 同步文件或本机记录的当前结果，不包含授权材料。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AgendaSyncStatus {
    UpToDate,
    Pending,
    NeedsCreation,
    LocationUnknown,
    Unverified,
    Failed,
    Conflict,
    OutcomeUnknown,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AgendaSyncReport {
    pub status: AgendaSyncStatus,
    pub pending_count: usize,
    pub changed_count: usize,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) enum RemoteError {
    Unverified,
    Failed,
    Superseded,
    Local(CacheError),
    Core(crate::error::UbaaError),
}
pub(crate) enum RemoteLocation<V> {
    Found(V),
    Missing,
    Unknown,
}
pub(crate) enum RemoteCommit<V> {
    Committed(V),
    OutcomeUnknown(Option<V>),
}
pub(crate) type BeforeCommit<'a> = &'a (dyn Fn() -> Result<(), RemoteError> + Sync);

/// 远端先完成目录发现，协调器再逐设备选择最高发布序号。
#[async_trait]
pub(crate) trait SyncRemote: Send {
    type Version: Clone + Send + Sync;
    fn check_current(&self) -> Result<(), RemoteError>;
    fn publication(&self, version: &Self::Version) -> Publication;
    fn same_version(&self, left: &Self::Version, right: &Self::Version) -> bool;
    fn object_key(&self, version: &Self::Version) -> String;
    async fn locate(&mut self) -> Result<RemoteLocation<Vec<Self::Version>>, RemoteError>;
    fn directory_target(&self) -> Option<String> {
        None
    }
    async fn create_directory_once(&mut self, _: BeforeCommit<'_>) -> Result<bool, RemoteError> {
        Err(RemoteError::Failed)
    }
    async fn directory_exists(&mut self, _: &str) -> Result<bool, RemoteError> {
        Err(RemoteError::Failed)
    }
    async fn read_version(&mut self, version: &Self::Version) -> Result<Vec<u8>, RemoteError>;
    async fn publish_once(
        &mut self,
        identity: Publication,
        body: &[u8],
        before_commit: BeforeCommit<'_>,
    ) -> Result<RemoteCommit<Self::Version>, RemoteError>;
}
pub(crate) struct Committed<V> {
    attempt: uuid::Uuid,
    epoch: u64,
    uploaded: V,
}
pub(crate) struct SyncCoordinator<R: SyncRemote> {
    pub(crate) store: AgendaStore,
    pub(crate) remote: R,
    pub(crate) committed: Option<Committed<R::Version>>,
}
impl<R: SyncRemote> SyncCoordinator<R> {
    pub fn new(store: AgendaStore, remote: R) -> Self {
        Self {
            store,
            remote,
            committed: None,
        }
    }
    pub async fn run(
        &mut self,
        action: AgendaSyncAction,
        now: AgendaTime,
    ) -> Result<AgendaSyncReport, AgendaSyncError> {
        let pending = self.store.restore_sync_attempt()?;
        let scope = pending
            .as_ref()
            .map(|v| v.snapshot.clone())
            .map_or_else(|| self.store.sync_snapshot(), Ok)?;
        if pending.as_ref().is_none_or(|pending| {
            !pending.retains_body()
                || self.committed.as_ref().is_none_or(|cached| {
                    pending.snapshot.attempt != Some(cached.attempt)
                        || pending.snapshot.epoch != cached.epoch
                        || pending.operation.object()
                            != Some(self.remote.object_key(&cached.uploaded).as_str())
                })
        }) {
            self.committed = None;
        }
        let mut changed = 0;
        match self
            .run_inner(action, now, &scope, pending, &mut changed)
            .await
        {
            Ok(result) => Ok(result),
            Err(RunError::Local(error) | RunError::Remote(RemoteError::Local(error))) => {
                Err(error.into())
            }
            Err(RunError::Remote(RemoteError::Superseded)) => Err(CacheError::Superseded.into()),
            Err(RunError::Remote(RemoteError::Core(error))) => Err(AgendaSyncError::Remote(error)),
            Err(RunError::Remote(RemoteError::Unverified)) => {
                Ok(self.report(&scope, AgendaSyncStatus::Unverified, changed)?)
            }
            Err(RunError::Remote(RemoteError::Failed)) => {
                let status = if self.store.has_sync_attempt(&scope)? {
                    AgendaSyncStatus::OutcomeUnknown
                } else {
                    AgendaSyncStatus::Failed
                };
                Ok(self.report(&scope, status, changed)?)
            }
        }
    }
    async fn run_inner(
        &mut self,
        action: AgendaSyncAction,
        now: AgendaTime,
        scope: &AgendaSyncSnapshot,
        pending: Option<RestoredAttempt>,
        changed: &mut usize,
    ) -> RunResult<AgendaSyncReport> {
        self.check(scope)?;
        if let Some(pending) = pending {
            if matches!(&pending.operation, PendingOperation::Directory { .. }) {
                return self.reconcile_directory(scope, pending).await;
            }
            return self.reconcile_file(scope, pending, now, changed).await;
        }
        let mut location = self.remote.locate().await;
        self.check(scope)?;
        for _ in 0..2 {
            if !matches!(location, Ok(RemoteLocation::Missing))
                || action != AgendaSyncAction::CreateConfirmed
            {
                break;
            }
            let Some(target) = self.remote.directory_target() else {
                break;
            };
            if !self.create_directory(scope, target).await? {
                return Ok(self.report(scope, AgendaSyncStatus::OutcomeUnknown, 0)?);
            }
            location = self.remote.locate().await;
            self.check(scope)?;
        }
        let versions = match location? {
            RemoteLocation::Found(versions) => versions,
            RemoteLocation::Missing => {
                return Ok(self.report(scope, AgendaSyncStatus::NeedsCreation, 0)?);
            }
            RemoteLocation::Unknown => {
                return Ok(self.report(scope, AgendaSyncStatus::LocationUnknown, 0)?);
            }
        };
        let (document, _) = self.read_all(scope, versions, None, None).await?;
        *changed = self.store.merge_sync_at(scope, &document, now)?;
        if action == AgendaSyncAction::Pull {
            return Ok(self.report(scope, self.pending_status(scope)?, *changed)?);
        }
        let mut sent = self.store.sync_snapshot()?;
        self.check(scope)?;
        if sent.document() == &document {
            return Ok(self.report(scope, self.pending_status(scope)?, *changed)?);
        }
        let attempt = self
            .store
            .begin_sync_attempt(&mut sent, SyncAttempt::Publication)?;
        let identity = Publication::from_snapshot(&sent)?;
        let body = match identity.encode(sent.document()) {
            Ok(body) => body,
            Err(error) => {
                self.store.clear_sync_attempt(&sent)?;
                return Err(error.into());
            }
        };
        let result = self
            .remote
            .publish_once(identity, &body, &|| {
                self.store
                    .check_sync_attempt(&sent)
                    .map_err(RemoteError::Local)
            })
            .await;
        self.check(scope)?;
        match result {
            Err(error) => {
                self.store.clear_sync_attempt(&sent)?;
                Err(error.into())
            }
            Ok(RemoteCommit::OutcomeUnknown(uploaded)) => {
                self.store.record_sync_receipt(
                    &sent,
                    PublicationReceipt::Unknown(
                        uploaded.as_ref().map(|v| self.remote.object_key(v)),
                    ),
                )?;
                Ok(self.report(scope, AgendaSyncStatus::OutcomeUnknown, *changed)?)
            }
            Ok(RemoteCommit::Committed(uploaded)) => {
                self.store.record_sync_receipt(
                    &sent,
                    PublicationReceipt::Registered(self.remote.object_key(&uploaded)),
                )?;
                self.committed = Some(Committed {
                    attempt,
                    epoch: sent.epoch,
                    uploaded,
                });
                let pending = self
                    .store
                    .restore_sync_attempt()?
                    .ok_or(CacheError::Superseded)?;
                self.reconcile_file(scope, pending, now, changed).await
            }
        }
    }
    async fn read_all(
        &mut self,
        scope: &AgendaSyncSnapshot,
        versions: Vec<R::Version>,
        ignored: Option<uuid::Uuid>,
        expected: Option<&AgendaSyncSnapshot>,
    ) -> RunResult<(AgendaSyncDocument, Option<R::Version>)> {
        let mut latest = BTreeMap::<uuid::Uuid, R::Version>::new();
        for version in versions {
            let identity = self.remote.publication(&version);
            if let Some(previous) = latest.get(&identity.publisher) {
                let old = self.remote.publication(previous);
                if identity == old && !self.remote.same_version(previous, &version) {
                    return Err(RemoteError::Failed.into());
                }
                if identity.sequence <= old.sequence {
                    continue;
                }
            }
            latest.insert(identity.publisher, version);
        }
        let mut combined = AgendaSyncDocument::default();
        let mut matching = None;
        for version in latest.into_values() {
            let identity = self.remote.publication(&version);
            if ignored == Some(identity.publisher) {
                continue;
            }
            let bytes = self.remote.read_version(&version).await;
            self.check(scope)?;
            let document = identity.decode(&bytes?)?;
            if let Some(sent) = expected
                && Publication::from_snapshot(sent)? == identity
            {
                if sent.document() != &document {
                    return Err(CacheError::Corrupt.into());
                }
                matching = Some(version.clone());
            }
            combined = combined.merge(&document)?;
        }
        Ok((combined, matching))
    }
    async fn reconcile_file(
        &mut self,
        scope: &AgendaSyncSnapshot,
        pending: RestoredAttempt,
        now: AgendaTime,
        changed: &mut usize,
    ) -> RunResult<AgendaSyncReport> {
        let location = self.remote.locate().await;
        self.check(scope)?;
        let RemoteLocation::Found(versions) = location? else {
            return Ok(self.report(scope, AgendaSyncStatus::OutcomeUnknown, *changed)?);
        };
        let current_matches = pending.confirmable_object().is_some_and(|object| {
            versions.iter().any(|version| {
                Publication::from_snapshot(&pending.snapshot).ok()
                    == Some(self.remote.publication(version))
                    && object == self.remote.object_key(version)
            })
        });
        let ignored = (!current_matches).then_some(scope.device_id);
        let expected = current_matches.then_some(&pending.snapshot);
        let (document, matching) = self.read_all(scope, versions, ignored, expected).await?;
        *changed += self.store.merge_sync_at(scope, &document, now)?;
        if let Some(current) = matching
            && pending.confirmable_object() == Some(self.remote.object_key(&current).as_str())
        {
            self.store
                .confirm_sync(&pending.snapshot, pending.snapshot.document())?;
            self.committed = None;
            return Ok(self.report(scope, self.pending_status(scope)?, *changed)?);
        }
        Ok(self.report(scope, AgendaSyncStatus::OutcomeUnknown, *changed)?)
    }
    async fn create_directory(
        &mut self,
        scope: &AgendaSyncSnapshot,
        target: String,
    ) -> RunResult<bool> {
        let mut sent = scope.clone();
        sent.document = AgendaSyncDocument::default();
        self.store
            .begin_sync_attempt(&mut sent, SyncAttempt::Directory(target))?;
        let result = self
            .remote
            .create_directory_once(&|| {
                self.store
                    .check_sync_attempt(&sent)
                    .map_err(RemoteError::Local)
            })
            .await;
        self.check(scope)?;
        if matches!(result, Ok(false)) {
            return Ok(false);
        }
        self.store.clear_sync_attempt(&sent)?;
        Ok(result?)
    }
    async fn reconcile_directory(
        &mut self,
        scope: &AgendaSyncSnapshot,
        pending: RestoredAttempt,
    ) -> RunResult<AgendaSyncReport> {
        let PendingOperation::Directory {
            target: Some(target),
        } = &pending.operation
        else {
            return Err(CacheError::Corrupt.into());
        };
        let exists = self.remote.directory_exists(target).await;
        self.check(scope)?;
        if exists? && pending.retains_body() {
            self.store.clear_sync_attempt(&pending.snapshot)?;
            return Ok(self.report(scope, AgendaSyncStatus::NeedsCreation, 0)?);
        }
        Ok(self.report(scope, AgendaSyncStatus::OutcomeUnknown, 0)?)
    }
    fn check(&self, scope: &AgendaSyncSnapshot) -> RunResult<()> {
        self.store.sync_pending_count(scope)?;
        self.remote.check_current()?;
        Ok(())
    }
    fn pending_status(&self, scope: &AgendaSyncSnapshot) -> CacheResult<AgendaSyncStatus> {
        Ok(if self.store.sync_pending_count(scope)? == 0 {
            AgendaSyncStatus::UpToDate
        } else {
            AgendaSyncStatus::Pending
        })
    }
    fn report(
        &self,
        scope: &AgendaSyncSnapshot,
        status: AgendaSyncStatus,
        changed_count: usize,
    ) -> CacheResult<AgendaSyncReport> {
        Ok(AgendaSyncReport {
            status,
            pending_count: self.store.sync_pending_count(scope)?,
            changed_count,
        })
    }
}
enum RunError {
    Local(CacheError),
    Remote(RemoteError),
}
type RunResult<T> = Result<T, RunError>;
impl From<CacheError> for RunError {
    fn from(value: CacheError) -> Self {
        Self::Local(value)
    }
}
impl From<RemoteError> for RunError {
    fn from(value: RemoteError) -> Self {
        Self::Remote(value)
    }
}
