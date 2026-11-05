use super::{AgendaSyncDocument, AgendaSyncError, AgendaSyncSnapshot, state::SyncStep};
use crate::{
    agenda::AgendaStore,
    cache::{CacheError, CacheResult},
    domain::agenda::AgendaTime,
};
use async_trait::async_trait;

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
    #[cfg(test)]
    Conflict,
    OutcomeUnknown(Option<V>),
}
pub(crate) type BeforeCommit<'a> = &'a (dyn Fn() -> Result<(), RemoteError> + Sync);

/// 版本对象由云盘 facade 创建。协调器不构造 URL、Token 或 HTTP 请求。
#[async_trait]
pub(crate) trait SyncRemote: Send {
    type Version: Clone + Send + Sync;
    fn check_current(&self) -> Result<(), RemoteError>;
    fn same_object(&self, left: &Self::Version, right: &Self::Version) -> bool;
    fn object_key(&self, version: &Self::Version) -> String;
    async fn locate(&mut self) -> Result<RemoteLocation<Self::Version>, RemoteError>;
    fn needs_directory(&self) -> bool {
        false
    }
    async fn create_directory_once(&mut self, _: BeforeCommit<'_>) -> Result<bool, RemoteError> {
        Err(RemoteError::Failed)
    }
    async fn directory_exists(&mut self) -> Result<bool, RemoteError> {
        Err(RemoteError::Failed)
    }
    async fn read_version(&mut self, version: &Self::Version) -> Result<Vec<u8>, RemoteError>;
    async fn publish_once(
        &mut self,
        base: Option<&Self::Version>,
        body: &[u8],
        before_commit: BeforeCommit<'_>,
    ) -> Result<RemoteCommit<Self::Version>, RemoteError>;
}
enum Pending<V> {
    Directory(AgendaSyncSnapshot),
    Committed {
        sent: AgendaSyncSnapshot,
        uploaded: V,
    },
    Unknown {
        sent: AgendaSyncSnapshot,
        object: Option<String>,
    },
}
impl<V> Pending<V> {
    fn sent(&self) -> &AgendaSyncSnapshot {
        match self {
            Self::Directory(sent) | Self::Committed { sent, .. } | Self::Unknown { sent, .. } => {
                sent
            }
        }
    }
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
        let pending = self.restore_pending()?;
        let scope = pending
            .as_ref()
            .map(|v| v.sent().clone())
            .map_or_else(|| self.store.sync_snapshot(), Ok)?;
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
            Err(RunError::Remote(RemoteError::Unverified)) => self
                .report(&scope, AgendaSyncStatus::Unverified, changed)
                .map_err(Into::into),
            Err(RunError::Remote(RemoteError::Failed)) => {
                let status = if self.store.has_sync_attempt(&scope)? {
                    AgendaSyncStatus::OutcomeUnknown
                } else {
                    AgendaSyncStatus::Failed
                };
                self.report(&scope, status, changed).map_err(Into::into)
            }
        }
    }
    fn restore_pending(&mut self) -> CacheResult<Option<Pending<R::Version>>> {
        let Some((sent, step, object)) = self.store.restore_sync_attempt()? else {
            self.committed = None;
            return Ok(None);
        };
        if step == SyncStep::Directory {
            self.committed = None;
            return Ok(Some(Pending::Directory(sent)));
        }
        if let Some(cached) = &self.committed
            && sent.attempt == Some(cached.attempt)
            && sent.epoch == cached.epoch
            && object
                .as_ref()
                .is_some_and(|key| *key == self.remote.object_key(&cached.uploaded))
        {
            return Ok(Some(Pending::Committed {
                sent,
                uploaded: cached.uploaded.clone(),
            }));
        }
        self.committed = None;
        Ok(Some(Pending::Unknown { sent, object }))
    }
    async fn run_inner(
        &mut self,
        action: AgendaSyncAction,
        now: AgendaTime,
        scope: &AgendaSyncSnapshot,
        pending: Option<Pending<R::Version>>,
        changed: &mut usize,
    ) -> RunResult<AgendaSyncReport> {
        self.check(scope)?;
        if let Some(pending) = pending {
            return self.reconcile(scope, pending).await;
        }
        let located = self.remote.locate().await;
        self.check(scope)?;
        let mut known_document = None;
        let base = match located? {
            RemoteLocation::Found(version) => {
                let bytes = self.remote.read_version(&version).await;
                self.check(scope)?;
                let document = AgendaSyncDocument::decode(&bytes?)?;
                *changed = self.store.merge_sync_at(scope, &document, now)?;
                known_document = Some(document);
                Some(version)
            }
            RemoteLocation::Missing => {
                *changed = self
                    .store
                    .merge_sync_at(scope, &AgendaSyncDocument::default(), now)?;
                None
            }
            RemoteLocation::Unknown if action == AgendaSyncAction::CreateConfirmed => {
                *changed = self.store.purge_sync_tombstones(scope, now)?;
                None
            }
            RemoteLocation::Unknown => {
                return Ok(self.report(scope, AgendaSyncStatus::LocationUnknown, 0)?);
            }
        };
        if action == AgendaSyncAction::Pull
            || action == AgendaSyncAction::CreateConfirmed && base.is_some()
        {
            return Ok(self.report(
                scope,
                if base.is_none() {
                    AgendaSyncStatus::NeedsCreation
                } else {
                    self.pending_status(scope)?
                },
                *changed,
            )?);
        }
        if base.is_none() && action != AgendaSyncAction::CreateConfirmed {
            return Ok(self.report(scope, AgendaSyncStatus::NeedsCreation, *changed)?);
        }
        if base.is_none() && self.remote.needs_directory() && !self.create_directory(scope).await? {
            return Ok(self.report(scope, AgendaSyncStatus::OutcomeUnknown, *changed)?);
        }
        self.publish_file(scope, base, known_document, *changed)
            .await
    }
    async fn create_directory(&mut self, scope: &AgendaSyncSnapshot) -> RunResult<bool> {
        let mut attempt = scope.clone();
        attempt.document = AgendaSyncDocument::default();
        self.store
            .begin_sync_attempt(&mut attempt, SyncStep::Directory, None)?;
        let result = self
            .remote
            .create_directory_once(&|| {
                self.store
                    .check_sync_attempt(&attempt)
                    .map_err(RemoteError::Local)
            })
            .await;
        self.check(scope)?;
        if matches!(result, Ok(false)) {
            return Ok(false);
        }
        self.store.clear_sync_attempt(&attempt)?;
        Ok(result?)
    }
    async fn publish_file(
        &mut self,
        scope: &AgendaSyncSnapshot,
        base: Option<R::Version>,
        known_document: Option<AgendaSyncDocument>,
        changed: usize,
    ) -> RunResult<AgendaSyncReport> {
        let mut sent = self.store.sync_snapshot()?;
        self.check(scope)?;
        if base.is_some() && known_document.as_ref() == Some(sent.document()) {
            return Ok(self.report(scope, self.pending_status(scope)?, changed)?);
        }
        let body = sent.document().encode()?;
        let object = base.as_ref().map(|v| self.remote.object_key(v));
        let attempt = self
            .store
            .begin_sync_attempt(&mut sent, SyncStep::File, object.clone())?;
        let outcome = self
            .remote
            .publish_once(base.as_ref(), &body, &|| {
                self.store
                    .check_sync_attempt(&sent)
                    .map_err(RemoteError::Local)
            })
            .await;
        self.check(scope)?;
        let outcome = match outcome {
            Ok(outcome) => outcome,
            Err(error) => {
                self.store.clear_sync_attempt(&sent)?;
                return Err(error.into());
            }
        };
        match outcome {
            #[cfg(test)]
            RemoteCommit::Conflict => {
                self.store.clear_sync_attempt(&sent)?;
                Ok(self.report(scope, AgendaSyncStatus::Conflict, changed)?)
            }
            RemoteCommit::OutcomeUnknown(uploaded) => {
                let object = uploaded
                    .as_ref()
                    .map(|v| self.remote.object_key(v))
                    .or(object);
                self.store.update_sync_attempt(&sent, object)?;
                Ok(self.report(scope, AgendaSyncStatus::OutcomeUnknown, changed)?)
            }
            RemoteCommit::Committed(uploaded) => {
                self.store
                    .update_sync_attempt(&sent, Some(self.remote.object_key(&uploaded)))?;
                self.committed = Some(Committed {
                    attempt,
                    epoch: sent.epoch,
                    uploaded: uploaded.clone(),
                });
                let mut report = self
                    .reconcile(scope, Pending::Committed { sent, uploaded })
                    .await?;
                report.changed_count = changed;
                Ok(report)
            }
        }
    }
    async fn reconcile(
        &mut self,
        scope: &AgendaSyncSnapshot,
        pending: Pending<R::Version>,
    ) -> RunResult<AgendaSyncReport> {
        if let Pending::Directory(sent) = &pending {
            let exists = self.remote.directory_exists().await;
            self.check(scope)?;
            if exists? {
                self.store.clear_sync_attempt(sent)?;
                self.committed = None;
                return Ok(self.report(scope, AgendaSyncStatus::NeedsCreation, 0)?);
            }
            return Ok(self.report(scope, AgendaSyncStatus::OutcomeUnknown, 0)?);
        }
        if let Pending::Committed { sent, uploaded } = &pending {
            let bytes = self.remote.read_version(uploaded).await;
            self.check(scope)?;
            match bytes {
                Ok(bytes) => return self.verify(scope, sent, &bytes),
                Err(RemoteError::Failed) => {}
                Err(error) => return Err(error.into()),
            }
        }
        let located = self.remote.locate().await;
        self.check(scope)?;
        let RemoteLocation::Found(current) = located? else {
            return Ok(self.report(scope, AgendaSyncStatus::OutcomeUnknown, 0)?);
        };
        let same_object = match &pending {
            Pending::Directory(_) => unreachable!("目录步骤只核对目录"),
            Pending::Committed { uploaded, .. } => self.remote.same_object(uploaded, &current),
            Pending::Unknown { object, .. } => object
                .as_ref()
                .is_none_or(|object| *object == self.remote.object_key(&current)),
        };
        if !same_object {
            return Ok(self.report(scope, AgendaSyncStatus::OutcomeUnknown, 0)?);
        }
        let bytes = self.remote.read_version(&current).await;
        self.check(scope)?;
        let bytes = bytes?;
        let read_back = AgendaSyncDocument::decode(&bytes)?;
        if &read_back == pending.sent().document() {
            return self.verify(scope, pending.sent(), &bytes);
        }
        Ok(self.report(scope, AgendaSyncStatus::OutcomeUnknown, 0)?)
    }
    fn verify(
        &mut self,
        scope: &AgendaSyncSnapshot,
        sent: &AgendaSyncSnapshot,
        bytes: &[u8],
    ) -> RunResult<AgendaSyncReport> {
        let document = AgendaSyncDocument::decode(bytes)?;
        match self.store.confirm_sync(sent, &document) {
            Ok(_) => {
                self.committed = None;
                Ok(self.report(scope, self.pending_status(scope)?, 0)?)
            }
            Err(CacheError::Superseded) => {
                self.check(scope)?;
                let status = if self.store.has_sync_attempt(scope)? {
                    AgendaSyncStatus::OutcomeUnknown
                } else {
                    self.committed = None;
                    self.pending_status(scope)?
                };
                Ok(self.report(scope, status, 0)?)
            }
            Err(error) => Err(error.into()),
        }
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
