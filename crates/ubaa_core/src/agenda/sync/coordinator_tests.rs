mod reconciliation;

use super::{coordinator::*, publication::Publication, tests::root};
use crate::{
    agenda::{
        AgendaStore,
        tests::{ACCOUNT, event, t},
    },
    domain::agenda::AgendaEditScope,
};
use async_trait::async_trait;
use std::{
    collections::BTreeMap,
    sync::{
        Arc, Mutex,
        atomic::{AtomicU64, Ordering},
    },
};
use uuid::Uuid;

#[derive(Clone, Debug, Eq, PartialEq)]
struct Version {
    identity: Publication,
    revision: u64,
}
#[derive(Default)]
#[allow(clippy::struct_excessive_bools)]
struct Server {
    directory_missing: bool,
    directory_creates: usize,
    files: BTreeMap<Publication, (Version, Vec<u8>)>,
    reads: Vec<Version>,
    published: Vec<Publication>,
    lookups: usize,
    unknown: bool,
    unknown_directory: bool,
    fail_readback: bool,
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
    after_send_gate: Option<Arc<Gate>>,
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
    fn publication(&self, v: &Version) -> Publication {
        v.identity
    }
    fn same_version(&self, a: &Version, b: &Version) -> bool {
        a == b
    }
    fn object_key(&self, v: &Version) -> String {
        format!("{}:{}", v.identity.file_name(), v.revision)
    }
    async fn locate(&mut self) -> Result<RemoteLocation<Vec<Version>>, RemoteError> {
        let mut s = self.server.lock().unwrap();
        s.lookups += 1;
        Ok(if self.unknown_location {
            RemoteLocation::Unknown
        } else if s.directory_missing {
            RemoteLocation::Missing
        } else {
            RemoteLocation::Found(s.files.values().rev().map(|(v, _)| v.clone()).collect())
        })
    }
    fn directory_target(&self) -> Option<String> {
        Some("合成同步目录".into())
    }
    async fn create_directory_once(
        &mut self,
        before: BeforeCommit<'_>,
    ) -> Result<bool, RemoteError> {
        before()?;
        let confirmed = {
            let mut s = self.server.lock().unwrap();
            s.directory_missing = false;
            s.directory_creates += 1;
            !s.unknown_directory
        };
        if let Some(gate) = self.after_send_gate.take() {
            gate.entered.notify_one();
            gate.released.notified().await;
        }
        Ok(confirmed)
    }
    async fn directory_exists(&mut self, target: &str) -> Result<bool, RemoteError> {
        assert_eq!(target, "合成同步目录");
        Ok(!self.server.lock().unwrap().directory_missing)
    }
    async fn read_version(&mut self, v: &Version) -> Result<Vec<u8>, RemoteError> {
        if let Some(gate) = self.readback_gate.take() {
            gate.entered.notify_one();
            gate.released.notified().await;
        }
        let mut s = self.server.lock().unwrap();
        s.reads.push(v.clone());
        if self.fail_read || s.fail_readback && !s.published.is_empty() {
            return Err(RemoteError::Failed);
        }
        s.files
            .get(&v.identity)
            .filter(|(stored, _)| stored == v)
            .map(|(_, body)| body.clone())
            .ok_or(RemoteError::Failed)
    }
    async fn publish_once(
        &mut self,
        identity: Publication,
        body: &[u8],
        before: BeforeCommit<'_>,
    ) -> Result<RemoteCommit<Version>, RemoteError> {
        if let Some(gate) = self.publish_gate.take() {
            gate.entered.notify_one();
            gate.released.notified().await;
        }
        before()?;
        let result = {
            let mut s = self.server.lock().unwrap();
            assert!(!s.files.contains_key(&identity), "不可重放同一发布身份");
            let v = Version {
                identity,
                revision: 1,
            };
            s.files.insert(identity, (v.clone(), body.to_vec()));
            s.published.push(identity);
            if s.unknown {
                RemoteCommit::OutcomeUnknown(Some(v))
            } else {
                RemoteCommit::Committed(v)
            }
        };
        if let Some(gate) = self.after_send_gate.take() {
            gate.entered.notify_one();
            gate.released.notified().await;
        }
        Ok(result)
    }
}
fn runtime() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}
fn remote_for(server: Arc<Mutex<Server>>) -> Remote {
    Remote {
        server,
        generation: Arc::new(AtomicU64::new(0)),
        expected: 0,
        unverified: false,
        readback_gate: None,
        publish_gate: None,
        after_send_gate: None,
        unknown_location: false,
        fail_read: false,
    }
}
fn setup() -> (AgendaStore, Remote, Arc<Mutex<Server>>) {
    let store = AgendaStore::open(&root(), ACCOUNT).unwrap();
    let server = Arc::new(Mutex::new(Server::default()));
    (store, remote_for(server.clone()), server)
}
fn now() -> crate::domain::agenda::AgendaTime {
    t("2026-03-01T00:00:00+08:00")
}
fn gate() -> Arc<Gate> {
    Arc::new(Gate {
        entered: tokio::sync::Notify::new(),
        released: tokio::sync::Notify::new(),
    })
}
fn insert_snapshot(server: &Arc<Mutex<Server>>, store: &AgendaStore, sequence: u64) -> Publication {
    let sent = store.sync_snapshot().unwrap();
    let identity = Publication {
        publisher: sent.device_id,
        sequence,
    };
    let v = Version {
        identity,
        revision: 1,
    };
    server
        .lock()
        .unwrap()
        .files
        .insert(identity, (v, identity.encode(sent.document()).unwrap()));
    identity
}

#[test]
fn unverified_sync_performs_no_remote_operation() {
    runtime().block_on(async {
        let (store, mut remote, server) = setup();
        store.create(event()).unwrap();
        remote.unverified = true;
        let report = SyncCoordinator::new(store, remote)
            .run(AgendaSyncAction::Pull, now())
            .await
            .unwrap();
        assert_eq!(report.status, AgendaSyncStatus::Unverified);
        assert_eq!(report.pending_count, 1);
        let s = server.lock().unwrap();
        assert_eq!(s.lookups, 0);
        assert_eq!(s.published.len(), 0);
    });
}
#[test]
fn opening_only_pulls_and_confirmed_creation_reads_back_the_publication() {
    runtime().block_on(async {
        let (store, remote, server) = setup();
        store.create(event()).unwrap();
        server.lock().unwrap().directory_missing = true;
        let mut d = SyncCoordinator::new(store.clone(), remote);
        assert_eq!(
            d.run(AgendaSyncAction::Pull, now()).await.unwrap().status,
            AgendaSyncStatus::NeedsCreation
        );
        assert_eq!(server.lock().unwrap().published.len(), 0);
        assert_eq!(
            d.run(AgendaSyncAction::CreateConfirmed, now())
                .await
                .unwrap()
                .status,
            AgendaSyncStatus::UpToDate
        );
        assert_eq!(store.unsynced_count().unwrap(), 0);
        let s = server.lock().unwrap();
        assert_eq!(s.directory_creates, 1);
        assert_eq!(s.published.len(), 1);
        assert_eq!(s.reads.len(), 1);
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
        let gate = gate();
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
            .run(AgendaSyncAction::Push, now())
            .await
            .unwrap();
        edit.await.unwrap();
        assert_eq!(result.status, AgendaSyncStatus::Pending);
        assert_eq!(store.unsynced_count().unwrap(), 1);
        assert_eq!(
            store.get(id).unwrap().unwrap().content.title,
            "上传等待时的同秒修改"
        );
        assert_eq!(server.lock().unwrap().published.len(), 1);
    });
}
#[test]
fn visible_unknown_publication_stays_dirty_without_reupload_even_after_reopen() {
    runtime().block_on(async {
        let (store, remote, server) = setup();
        store.create(event()).unwrap();
        server.lock().unwrap().unknown = true;
        let mut d = SyncCoordinator::new(store.clone(), remote);
        assert_eq!(
            d.run(AgendaSyncAction::Push, now()).await.unwrap().status,
            AgendaSyncStatus::OutcomeUnknown
        );
        for _ in 0..2 {
            let mut next = SyncCoordinator::new(store.clone(), remote_for(server.clone()));
            assert_eq!(
                next.run(AgendaSyncAction::Push, now())
                    .await
                    .unwrap()
                    .status,
                AgendaSyncStatus::OutcomeUnknown
            );
        }
        assert_eq!(store.unsynced_count().unwrap(), 1);
        assert_eq!(server.lock().unwrap().published.len(), 1);
    });
}
#[test]
fn confirmed_snapshot_is_not_uploaded_again_without_any_change() {
    runtime().block_on(async {
        let (store, remote, server) = setup();
        store.create(event()).unwrap();
        let mut d = SyncCoordinator::new(store, remote);
        d.run(AgendaSyncAction::Push, now()).await.unwrap();
        assert_eq!(
            d.run(AgendaSyncAction::Push, now()).await.unwrap().status,
            AgendaSyncStatus::UpToDate
        );
        assert_eq!(server.lock().unwrap().published.len(), 1);
    });
}
#[test]
fn unknown_location_does_not_create_or_publish_even_when_confirmed() {
    runtime().block_on(async {
        let (store, mut remote, server) = setup();
        store.create(event()).unwrap();
        remote.unknown_location = true;
        let mut d = SyncCoordinator::new(store, remote);
        for action in [
            AgendaSyncAction::Pull,
            AgendaSyncAction::Push,
            AgendaSyncAction::CreateConfirmed,
        ] {
            assert_eq!(
                d.run(action, now()).await.unwrap().status,
                AgendaSyncStatus::LocationUnknown
            );
        }
        let s = server.lock().unwrap();
        assert_eq!(s.published.len(), 0);
        assert_eq!(s.directory_creates, 0);
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
            insert_snapshot(&server, &other, 1);
            let gate = gate();
            remote.readback_gate = Some(gate.clone());
            remote.fail_read = route;
            let generation = remote.generation.clone();
            let moved = store.clone();
            let task = tokio::spawn(async move {
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
            task.await.unwrap();
            assert!(matches!(
                result,
                Err(super::AgendaSyncError::Local(
                    crate::cache::CacheError::Superseded
                ))
            ));
            assert!(store.get(id).unwrap().is_some());
            assert!(store.get(remote_id).unwrap().is_none());
            assert_eq!(server.lock().unwrap().published.len(), 0);
        }
    });
}
#[test]
fn two_devices_publish_independently_and_merge_both_changes() {
    runtime().block_on(async {
        let (first, mut remote, server) = setup();
        let item = event();
        let first_id = item.id;
        first.create(item).unwrap();
        let second = AgendaStore::open(&root(), ACCOUNT).unwrap();
        let item = event();
        let second_id = item.id;
        second.create(item).unwrap();
        let gate = gate();
        remote.publish_gate = Some(gate.clone());
        let other = remote_for(server.clone());
        let second_clone = second.clone();
        let peer = tokio::spawn(async move {
            gate.entered.notified().await;
            let report = SyncCoordinator::new(second_clone, other)
                .run(AgendaSyncAction::Push, now())
                .await
                .unwrap();
            gate.released.notify_one();
            report
        });
        let mut d = SyncCoordinator::new(first.clone(), remote);
        assert_eq!(
            d.run(AgendaSyncAction::Push, now()).await.unwrap().status,
            AgendaSyncStatus::UpToDate
        );
        assert_eq!(peer.await.unwrap().status, AgendaSyncStatus::UpToDate);
        assert!(first.get(first_id).unwrap().is_some());
        assert!(first.get(second_id).unwrap().is_some());
        let mut peer = SyncCoordinator::new(second.clone(), remote_for(server.clone()));
        peer.run(AgendaSyncAction::Pull, now()).await.unwrap();
        assert!(second.get(first_id).unwrap().is_some());
        assert!(second.get(second_id).unwrap().is_some());
        let s = server.lock().unwrap();
        assert_eq!(s.published.len(), 2);
        assert_ne!(s.published[0].publisher, s.published[1].publisher);
    });
}
#[test]
fn stopping_after_possible_send_preserves_read_only_reconciliation() {
    runtime().block_on(async {
        let (store, mut remote, server) = setup();
        store.create(event()).unwrap();
        let gate = gate();
        remote.after_send_gate = Some(gate.clone());
        let moved = store.clone();
        let task = tokio::spawn(async move {
            SyncCoordinator::new(moved, remote)
                .run(AgendaSyncAction::Push, now())
                .await
        });
        gate.entered.notified().await;
        assert!(store.restore_sync_attempt().unwrap().is_some());
        task.abort();
        assert!(task.await.unwrap_err().is_cancelled());
        let mut next = SyncCoordinator::new(store.clone(), remote_for(server.clone()));
        assert_eq!(
            next.run(AgendaSyncAction::Push, now())
                .await
                .unwrap()
                .status,
            AgendaSyncStatus::OutcomeUnknown
        );
        assert_eq!(store.unsynced_count().unwrap(), 1);
        assert_eq!(server.lock().unwrap().published.len(), 1);
    });
}
#[test]
fn failure_to_persist_attempt_stops_before_the_first_remote_write() {
    runtime().block_on(async {
        let directory=root(); let store=AgendaStore::open(&directory,ACCOUNT).unwrap(); store.create(event()).unwrap(); let (_,remote,server)=setup();
        let db=rusqlite::Connection::open(directory.join("agenda").join(format!("{ACCOUNT}.sqlite"))).unwrap();
        db.execute_batch("CREATE TRIGGER reject_attempt BEFORE INSERT ON agenda_sync_pending BEGIN SELECT RAISE(FAIL,'合成写入失败'); END;").unwrap();
        let mut d=SyncCoordinator::new(store.clone(),remote);
        assert!(matches!(d.run(AgendaSyncAction::Push,now()).await,Err(super::AgendaSyncError::Local(_))));
        assert_eq!(server.lock().unwrap().published.len(), 0); assert!(store.restore_sync_attempt().unwrap().is_none()); assert_eq!(store.unsynced_count().unwrap(),1);
        db.execute_batch("DROP TRIGGER reject_attempt").unwrap();
        assert_eq!(d.run(AgendaSyncAction::Push,now()).await.unwrap().status,AgendaSyncStatus::UpToDate);
        assert_eq!(server.lock().unwrap().published.len(),1);
    });
}
