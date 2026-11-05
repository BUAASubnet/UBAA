mod reconciliation;

use super::{coordinator::*, tests::root};
use crate::{
    agenda::{
        AgendaStore,
        tests::{ACCOUNT, event, t},
    },
    domain::agenda::AgendaEditScope,
};
use async_trait::async_trait;
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicU64, Ordering},
};
#[derive(Clone, Debug, Eq, PartialEq)]
struct Version {
    object: u64,
    revision: u64,
}
#[derive(Default)]
struct Server {
    directory_missing: bool,
    directory_creates: usize,
    document: Option<Vec<u8>>,
    revision: u64,
    reads: Vec<Version>,
    bases: Vec<Option<Version>>,
    lookups: usize,
    unknown: bool,
    unregistered_revision_readable: bool,
    history: std::collections::BTreeMap<u64, Vec<u8>>,
}
struct Gate {
    entered: tokio::sync::Notify,
    released: tokio::sync::Notify,
}
struct Remote {
    server: Arc<Mutex<Server>>,
    generation: Arc<AtomicU64>,
    expected: u64,
    unverified: bool,
    readback_gate: Option<Arc<Gate>>,
    publish_gate: Option<Arc<Gate>>,
    unknown_location: bool,
    fail_read: bool,
}
#[async_trait]
impl SyncRemote for Remote {
    type Version = Version;
    fn check_current(&self) -> Result<(), RemoteError> {
        if self.generation.load(Ordering::SeqCst) != self.expected {
            Err(RemoteError::Superseded)
        } else if self.unverified {
            Err(RemoteError::Unverified)
        } else {
            Ok(())
        }
    }
    fn same_object(&self, a: &Version, b: &Version) -> bool {
        a.object == b.object
    }
    fn object_key(&self, version: &Version) -> String {
        version.object.to_string()
    }
    async fn locate(&mut self) -> Result<RemoteLocation<Version>, RemoteError> {
        let mut server = self.server.lock().unwrap();
        server.lookups += 1;
        Ok(if self.unknown_location {
            RemoteLocation::Unknown
        } else if server.document.is_some() {
            RemoteLocation::Found(Version {
                object: 1,
                revision: server.revision,
            })
        } else {
            RemoteLocation::Missing
        })
    }
    fn needs_directory(&self) -> bool {
        self.server.lock().unwrap().directory_missing
    }
    async fn create_directory_once(
        &mut self,
        before_commit: BeforeCommit<'_>,
    ) -> Result<bool, RemoteError> {
        before_commit()?;
        let mut server = self.server.lock().unwrap();
        server.directory_missing = false;
        server.directory_creates += 1;
        Ok(false)
    }
    async fn directory_exists(&mut self) -> Result<bool, RemoteError> {
        Ok(!self.server.lock().unwrap().directory_missing)
    }
    async fn read_version(&mut self, version: &Version) -> Result<Vec<u8>, RemoteError> {
        if version.revision > 0
            && let Some(gate) = self.readback_gate.take()
        {
            gate.entered.notify_one();
            gate.released.notified().await;
        }
        let mut server = self.server.lock().unwrap();
        server.reads.push(version.clone());
        if self.fail_read || version.object != 1 {
            return Err(RemoteError::Failed);
        }
        if version.revision == server.revision {
            server.document.clone()
        } else {
            server.history.get(&version.revision).cloned()
        }
        .ok_or(RemoteError::Failed)
    }
    async fn publish_once(
        &mut self,
        base: Option<&Version>,
        body: &[u8],
        before_commit: BeforeCommit<'_>,
    ) -> Result<RemoteCommit<Version>, RemoteError> {
        if let Some(gate) = self.publish_gate.take() {
            gate.entered.notify_one();
            gate.released.notified().await;
        }
        before_commit()?;
        let mut server = self.server.lock().unwrap();
        server.bases.push(base.cloned());
        let matches = match base {
            Some(v) => server.document.is_some() && v.object == 1 && v.revision == server.revision,
            None => server.document.is_none(),
        };
        if !matches {
            return Ok(RemoteCommit::Conflict);
        }
        if server.unregistered_revision_readable {
            let revision = server.revision + 1;
            server.history.insert(revision, body.to_vec());
            return Ok(RemoteCommit::OutcomeUnknown(Some(Version {
                object: 1,
                revision,
            })));
        }
        if let Some(previous) = server.document.clone() {
            let revision = server.revision;
            server.history.insert(revision, previous);
        }
        server.revision += 1;
        server.document = Some(body.to_vec());
        let version = Version {
            object: 1,
            revision: server.revision,
        };
        Ok(if server.unknown {
            RemoteCommit::OutcomeUnknown(Some(version))
        } else {
            RemoteCommit::Committed(version)
        })
    }
}
fn runtime() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}
fn setup() -> (AgendaStore, Remote, Arc<Mutex<Server>>) {
    let store = AgendaStore::open(&root(), ACCOUNT).unwrap();
    let server = Arc::new(Mutex::new(Server::default()));
    let remote = Remote {
        server: server.clone(),
        generation: Arc::new(AtomicU64::new(0)),
        expected: 0,
        unverified: false,
        readback_gate: None,
        publish_gate: None,
        unknown_location: false,
        fail_read: false,
    };
    (store, remote, server)
}
fn now() -> crate::domain::agenda::AgendaTime {
    t("2026-03-01T00:00:00+08:00")
}
#[test]
fn unverified_automatic_sync_performs_no_remote_operation() {
    runtime().block_on(async {
        let (store, mut remote, server) = setup();
        store.create(event()).unwrap();
        remote.unverified = true;
        let result = SyncCoordinator::new(store.clone(), remote)
            .run(AgendaSyncAction::Pull, now())
            .await
            .unwrap();
        assert_eq!(result.status, AgendaSyncStatus::Unverified);
        assert_eq!(result.pending_count, 1);
        let server = server.lock().unwrap();
        assert_eq!(server.lookups, 0);
        assert!(server.bases.is_empty());
    });
}
#[test]
fn opening_only_pulls_and_confirmed_creation_reads_back_the_new_version() {
    runtime().block_on(async {
        let (store, remote, server) = setup();
        store.create(event()).unwrap();
        let mut driver = SyncCoordinator::new(store.clone(), remote);
        assert_eq!(
            driver
                .run(AgendaSyncAction::Pull, now())
                .await
                .unwrap()
                .status,
            AgendaSyncStatus::NeedsCreation
        );
        assert!(server.lock().unwrap().bases.is_empty());
        assert_eq!(
            driver
                .run(AgendaSyncAction::CreateConfirmed, now())
                .await
                .unwrap()
                .status,
            AgendaSyncStatus::UpToDate
        );
        assert_eq!(store.unsynced_count().unwrap(), 0);
        let server = server.lock().unwrap();
        assert_eq!(server.bases, vec![None]);
        assert_eq!(
            server.reads,
            vec![Version {
                object: 1,
                revision: 1
            }]
        );
    });
}
#[test]
fn local_edit_during_readback_is_not_acknowledged_by_the_old_upload() {
    runtime().block_on(async {
        let (store, mut remote, server) = setup();
        let item = event();
        let id = item.id;
        let time = item.updated_at;
        store.create(item.clone()).unwrap();
        let gate = Arc::new(Gate {
            entered: tokio::sync::Notify::new(),
            released: tokio::sync::Notify::new(),
        });
        remote.readback_gate = Some(gate.clone());
        let writer = store.clone();
        let edit = tokio::spawn(async move {
            gate.entered.notified().await;
            let mut value = item.content;
            value.title = "上传等待时的同秒修改".into();
            writer
                .edit(id, AgendaEditScope::All, None, value, None, time)
                .unwrap();
            gate.released.notify_one();
        });
        let result = SyncCoordinator::new(store.clone(), remote)
            .run(AgendaSyncAction::CreateConfirmed, now())
            .await
            .unwrap();
        edit.await.unwrap();
        assert_eq!(result.status, AgendaSyncStatus::Pending);
        assert_eq!(store.unsynced_count().unwrap(), 1);
        assert_eq!(
            store.get(id).unwrap().unwrap().content.title,
            "上传等待时的同秒修改"
        );
        assert_eq!(server.lock().unwrap().bases.len(), 1);
    });
}
#[test]
fn unknown_upload_is_only_reconciled_on_the_next_trigger_without_reupload() {
    runtime().block_on(async {
        let (store, remote, server) = setup();
        store.create(event()).unwrap();
        server.lock().unwrap().unknown = true;
        let mut driver = SyncCoordinator::new(store.clone(), remote);
        assert_eq!(
            driver
                .run(AgendaSyncAction::CreateConfirmed, now())
                .await
                .unwrap()
                .status,
            AgendaSyncStatus::OutcomeUnknown
        );
        assert_eq!(store.unsynced_count().unwrap(), 1);
        assert_eq!(
            driver
                .run(AgendaSyncAction::Push, now())
                .await
                .unwrap()
                .status,
            AgendaSyncStatus::UpToDate
        );
        assert_eq!(store.unsynced_count().unwrap(), 0);
        assert_eq!(server.lock().unwrap().bases.len(), 1);
    });
}

#[test]
fn confirmed_snapshot_is_not_uploaded_again_without_any_change() {
    runtime().block_on(async {
        let (store, remote, server) = setup();
        store.create(event()).unwrap();
        let mut driver = SyncCoordinator::new(store, remote);
        driver
            .run(AgendaSyncAction::CreateConfirmed, now())
            .await
            .unwrap();
        assert_eq!(
            driver
                .run(AgendaSyncAction::Push, now())
                .await
                .unwrap()
                .status,
            AgendaSyncStatus::UpToDate
        );
        assert_eq!(server.lock().unwrap().bases.len(), 1);
    });
}
#[test]
fn unknown_location_requires_confirmation_and_confirmed_creation_never_overwrites() {
    runtime().block_on(async {
        let (store, mut remote, server) = setup();
        store.create(event()).unwrap();
        remote.unknown_location = true;
        let other = AgendaStore::open(&root(), ACCOUNT).unwrap();
        other.create(event()).unwrap();
        let existing = other.sync_snapshot().unwrap().document().encode().unwrap();
        server.lock().unwrap().document = Some(existing.clone());
        let mut driver = SyncCoordinator::new(store.clone(), remote);
        assert_eq!(
            driver
                .run(AgendaSyncAction::Pull, now())
                .await
                .unwrap()
                .status,
            AgendaSyncStatus::LocationUnknown
        );
        assert_eq!(
            driver
                .run(AgendaSyncAction::Push, now())
                .await
                .unwrap()
                .status,
            AgendaSyncStatus::LocationUnknown
        );
        assert!(server.lock().unwrap().bases.is_empty());
        assert_eq!(
            driver
                .run(AgendaSyncAction::CreateConfirmed, now())
                .await
                .unwrap()
                .status,
            AgendaSyncStatus::Conflict
        );
        let server = server.lock().unwrap();
        assert_eq!(server.bases, vec![None]);
        assert_eq!(server.document.as_ref(), Some(&existing));
        assert_eq!(store.unsynced_count().unwrap(), 1);
    });
}
#[test]
fn route_change_or_same_account_relogin_during_read_does_not_merge_or_publish() {
    runtime().block_on(async {
        for route in [true, false] {
            let (store, mut remote, server) = setup();
            let local = event();
            let id = local.id;
            store.create(local).unwrap();
            let other = AgendaStore::open(&root(), ACCOUNT).unwrap();
            let incoming = event();
            let remote_id = incoming.id;
            other.create(incoming).unwrap();
            {
                let mut server = server.lock().unwrap();
                server.revision = 1;
                server.document = Some(other.sync_snapshot().unwrap().document().encode().unwrap());
            }
            let gate = Arc::new(Gate {
                entered: tokio::sync::Notify::new(),
                released: tokio::sync::Notify::new(),
            });
            remote.readback_gate = Some(gate.clone());
            remote.fail_read = route;
            let generation = remote.generation.clone();
            let moved = store.clone();
            let change = tokio::spawn(async move {
                gate.entered.notified().await;
                if route {
                    generation.store(1, Ordering::SeqCst);
                } else {
                    moved.deactivate().unwrap();
                    moved.activate().unwrap();
                }
                gate.released.notify_one();
            });
            let result = SyncCoordinator::new(store.clone(), remote)
                .run(AgendaSyncAction::Push, now())
                .await;
            change.await.unwrap();
            assert!(matches!(
                result,
                Err(super::AgendaSyncError::Local(
                    crate::cache::CacheError::Superseded
                ))
            ));
            assert!(store.get(id).unwrap().is_some());
            assert!(store.get(remote_id).unwrap().is_none());
            assert!(server.lock().unwrap().bases.is_empty());
            assert_eq!(store.unsynced_count().unwrap(), 1);
        }
    });
}
#[test]
fn two_devices_with_the_same_base_conflict_without_retry_then_merge_on_new_trigger() {
    runtime().block_on(async {
        let (first, mut remote, server) = setup();
        let first_item = event();
        let first_id = first_item.id;
        first.create(first_item).unwrap();
        server.lock().unwrap().document =
            Some(super::AgendaSyncDocument::default().encode().unwrap());
        let gate = Arc::new(Gate {
            entered: tokio::sync::Notify::new(),
            released: tokio::sync::Notify::new(),
        });
        remote.publish_gate = Some(gate.clone());
        let second = AgendaStore::open(&root(), ACCOUNT).unwrap();
        let second_item = event();
        let second_id = second_item.id;
        second.create(second_item).unwrap();
        let other_remote = Remote {
            server: server.clone(),
            generation: Arc::new(AtomicU64::new(0)),
            expected: 0,
            unverified: false,
            readback_gate: None,
            publish_gate: None,
            unknown_location: false,
            fail_read: false,
        };
        let peer = tokio::spawn(async move {
            gate.entered.notified().await;
            let result = SyncCoordinator::new(second, other_remote)
                .run(AgendaSyncAction::Push, now())
                .await
                .unwrap();
            gate.released.notify_one();
            result
        });
        let mut driver = SyncCoordinator::new(first.clone(), remote);
        assert_eq!(
            driver
                .run(AgendaSyncAction::Push, now())
                .await
                .unwrap()
                .status,
            AgendaSyncStatus::Conflict
        );
        assert_eq!(peer.await.unwrap().status, AgendaSyncStatus::UpToDate);
        assert_eq!(first.unsynced_count().unwrap(), 1);
        {
            let server = server.lock().unwrap();
            assert_eq!(server.bases.len(), 2);
            assert!(
                server
                    .bases
                    .iter()
                    .all(|v| v.as_ref().unwrap().revision == 0)
            );
        }
        assert_eq!(
            driver
                .run(AgendaSyncAction::Push, now())
                .await
                .unwrap()
                .status,
            AgendaSyncStatus::UpToDate
        );
        let server = server.lock().unwrap();
        assert_eq!(server.bases.len(), 3);
        assert_eq!(server.bases[2].as_ref().unwrap().revision, 1);
        let merged = super::AgendaSyncDocument::decode(server.document.as_ref().unwrap()).unwrap();
        assert_eq!(merged.items.len(), 2);
        assert!(merged.items.iter().any(|v| v.item.id == first_id));
        assert!(merged.items.iter().any(|v| v.item.id == second_id));
    });
}

#[test]
fn readable_upload_version_without_current_metadata_publication_stays_unknown_and_dirty() {
    runtime().block_on(async {
        let (store, remote, server) = setup();
        store.create(event()).unwrap();
        {
            let mut state = server.lock().unwrap();
            state.document = Some(super::AgendaSyncDocument::default().encode().unwrap());
            state.unregistered_revision_readable = true;
        }
        let mut driver = SyncCoordinator::new(store.clone(), remote);
        assert_eq!(
            driver
                .run(AgendaSyncAction::Push, now())
                .await
                .unwrap()
                .status,
            AgendaSyncStatus::OutcomeUnknown
        );
        let checked = driver.run(AgendaSyncAction::Push, now()).await.unwrap();
        assert_eq!(
            store.unsynced_count().unwrap(),
            1,
            "只有U正文证据时不得确认本机快照"
        );
        assert_eq!(checked.status, AgendaSyncStatus::OutcomeUnknown);
        assert_eq!(
            driver
                .run(AgendaSyncAction::Push, now())
                .await
                .unwrap()
                .status,
            AgendaSyncStatus::OutcomeUnknown
        );
        {
            let mut state = server.lock().unwrap();
            assert_eq!(state.revision, 0);
            assert_eq!(state.bases.len(), 1);
            assert!(state.reads.iter().all(|v| v.revision == 0));
            state.document = state.history.get(&1).cloned();
            state.revision = 1;
        }
        assert_eq!(
            driver
                .run(AgendaSyncAction::Push, now())
                .await
                .unwrap()
                .status,
            AgendaSyncStatus::UpToDate
        );
        assert_eq!(store.unsynced_count().unwrap(), 0);
        assert_eq!(server.lock().unwrap().bases.len(), 1);
    });
}

#[test]
fn reopening_the_same_account_after_unknown_only_reconciles_without_reupload() {
    runtime().block_on(async {
        let (_, remote, server) = setup();
        let directory = root();
        let store = AgendaStore::open(&directory, ACCOUNT).unwrap();
        store.create(event()).unwrap();
        {
            let mut state = server.lock().unwrap();
            state.document = Some(super::AgendaSyncDocument::default().encode().unwrap());
            state.unregistered_revision_readable = true;
        }
        let mut first = SyncCoordinator::new(store.clone(), remote);
        assert_eq!(
            first
                .run(AgendaSyncAction::Push, now())
                .await
                .unwrap()
                .status,
            AgendaSyncStatus::OutcomeUnknown
        );
        drop(first);
        let second = AgendaStore::open(&directory, ACCOUNT).unwrap();
        let remote = Remote {
            server: server.clone(),
            generation: Arc::new(AtomicU64::new(0)),
            expected: 0,
            unverified: false,
            readback_gate: None,
            publish_gate: None,
            unknown_location: false,
            fail_read: false,
        };
        let mut second = SyncCoordinator::new(second, remote);
        assert_eq!(
            second
                .run(AgendaSyncAction::Push, now())
                .await
                .unwrap()
                .status,
            AgendaSyncStatus::OutcomeUnknown
        );
        assert_eq!(store.unsynced_count().unwrap(), 1);
        assert_eq!(
            server.lock().unwrap().bases.len(),
            1,
            "新消费者必须保留结果未知的只读核对状态"
        );
    });
}

struct StopAfterSend {
    inner: Remote,
    gate: Arc<Gate>,
}
#[async_trait]
impl SyncRemote for StopAfterSend {
    type Version = Version;
    fn check_current(&self) -> Result<(), RemoteError> {
        self.inner.check_current()
    }
    fn same_object(&self, a: &Version, b: &Version) -> bool {
        self.inner.same_object(a, b)
    }
    fn object_key(&self, version: &Version) -> String {
        self.inner.object_key(version)
    }
    async fn locate(&mut self) -> Result<RemoteLocation<Version>, RemoteError> {
        self.inner.locate().await
    }
    async fn read_version(&mut self, version: &Version) -> Result<Vec<u8>, RemoteError> {
        self.inner.read_version(version).await
    }
    async fn publish_once(
        &mut self,
        base: Option<&Version>,
        body: &[u8],
        before_commit: BeforeCommit<'_>,
    ) -> Result<RemoteCommit<Version>, RemoteError> {
        let result = self.inner.publish_once(base, body, before_commit).await;
        self.gate.entered.notify_one();
        self.gate.released.notified().await;
        result
    }
}
#[test]
fn stopping_after_a_possible_send_before_returning_outcome_preserves_read_only_reconciliation() {
    runtime().block_on(async {
        for unregistered in [true, false] {
            let (_, remote, server) = setup();
            let directory = root();
            let store = AgendaStore::open(&directory, ACCOUNT).unwrap();
            store.create(event()).unwrap();
            {
                let mut state = server.lock().unwrap();
                state.document = Some(super::AgendaSyncDocument::default().encode().unwrap());
                state.unregistered_revision_readable = unregistered;
            }
            let gate = Arc::new(Gate {
                entered: tokio::sync::Notify::new(),
                released: tokio::sync::Notify::new(),
            });
            let mut driver = SyncCoordinator::new(
                store.clone(),
                StopAfterSend {
                    inner: remote,
                    gate: gate.clone(),
                },
            );
            let task = tokio::spawn(async move { driver.run(AgendaSyncAction::Push, now()).await });
            gate.entered.notified().await;
            assert!(store.restore_sync_attempt().unwrap().is_some());
            task.abort();
            assert!(task.await.unwrap_err().is_cancelled());
            let reopened = AgendaStore::open(&directory, ACCOUNT).unwrap();
            let (_, mut remote, _) = setup();
            remote.server = server.clone();
            let report = SyncCoordinator::new(reopened, remote)
                .run(AgendaSyncAction::Push, now())
                .await
                .unwrap();
            assert_eq!(
                report.status,
                if unregistered {
                    AgendaSyncStatus::OutcomeUnknown
                } else {
                    AgendaSyncStatus::UpToDate
                }
            );
            assert_eq!(server.lock().unwrap().bases.len(), 1);
            assert_eq!(store.unsynced_count().unwrap(), usize::from(unregistered));
        }
    });
}
#[test]
fn failure_to_persist_attempt_stops_before_the_first_remote_write() {
    runtime().block_on(async {
        let (_,remote,server)=setup();
        let directory=root();
        let store=AgendaStore::open(&directory,ACCOUNT).unwrap();
        store.create(event()).unwrap();
        server.lock().unwrap().document=Some(super::AgendaSyncDocument::default().encode().unwrap());
        let db=rusqlite::Connection::open(directory.join("agenda").join(format!("{ACCOUNT}.sqlite"))).unwrap();
        db.execute_batch("CREATE TRIGGER reject_attempt BEFORE INSERT ON agenda_sync_pending BEGIN SELECT RAISE(FAIL,'合成写入失败'); END;").unwrap();
        let mut driver=SyncCoordinator::new(store.clone(),remote);
        assert!(matches!(driver.run(AgendaSyncAction::Push,now()).await,Err(super::AgendaSyncError::Local(_))));
        assert!(server.lock().unwrap().bases.is_empty());
        assert!(store.restore_sync_attempt().unwrap().is_none());
        assert_eq!(store.unsynced_count().unwrap(),1);
        db.execute_batch("DROP TRIGGER reject_attempt").unwrap();
        assert_eq!(driver.run(AgendaSyncAction::Push,now()).await.unwrap().status,AgendaSyncStatus::UpToDate);
        assert_eq!(server.lock().unwrap().bases.len(),1);
    });
}
