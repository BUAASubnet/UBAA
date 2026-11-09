use super::*;

#[test]
fn unknown_directory_creation_is_reconciled_without_publishing_the_file() {
    runtime().block_on(async {
        let (store, remote, server) = setup();
        store.create(event()).unwrap();
        {
            let mut s = server.lock().unwrap();
            s.directory_missing = true;
            s.unknown_directory = true;
        }
        let mut first = SyncCoordinator::new(store.clone(), remote);
        assert_eq!(
            first
                .run(AgendaSyncAction::CreateConfirmed, now())
                .await
                .unwrap()
                .status,
            AgendaSyncStatus::OutcomeUnknown
        );
        assert!(store.restore_sync_attempt().unwrap().is_some());
        let mut reopened = SyncCoordinator::new(store.clone(), remote_for(server.clone()));
        assert_eq!(
            reopened
                .run(AgendaSyncAction::Pull, now())
                .await
                .unwrap()
                .status,
            AgendaSyncStatus::NeedsCreation
        );
        assert!(store.restore_sync_attempt().unwrap().is_none());
        assert_eq!(server.lock().unwrap().directory_creates, 1);
        assert!(server.lock().unwrap().published.is_empty());
        assert_eq!(
            reopened
                .run(AgendaSyncAction::CreateConfirmed, now())
                .await
                .unwrap()
                .status,
            AgendaSyncStatus::UpToDate
        );
        assert_eq!(server.lock().unwrap().published.len(), 1);
    });
}
#[test]
fn confirmed_creation_preserves_existing_peer_files_and_merges_them() {
    runtime().block_on(async {
        let (store, remote, server) = setup();
        store.create(event()).unwrap();
        let mut gui = SyncCoordinator::new(store.clone(), remote);
        let other = AgendaStore::open(&root(), ACCOUNT).unwrap();
        let item = event();
        let id = item.id;
        other.create(item).unwrap();
        let identity = insert_snapshot(&server, &other, 1);
        let original = server.lock().unwrap().files[&identity].clone();
        let report = gui
            .run(AgendaSyncAction::CreateConfirmed, now())
            .await
            .unwrap();
        assert_eq!(report.status, AgendaSyncStatus::UpToDate);
        assert!(store.get(id).unwrap().is_some());
        let s = server.lock().unwrap();
        assert_eq!(s.files[&identity], original);
        assert_eq!(s.published.len(), 1);
        assert_ne!(s.published[0].publisher, identity.publisher);
    });
}
#[test]
fn successful_receipt_survives_readback_failure_and_another_process_confirms_without_upload() {
    runtime().block_on(async {
        let directory = root();
        let store = AgendaStore::open(&directory, ACCOUNT).unwrap();
        store.create(event()).unwrap();
        let (_, remote, server) = setup();
        server.lock().unwrap().fail_readback = true;
        let mut gui = SyncCoordinator::new(store.clone(), remote);
        assert_eq!(
            gui.run(AgendaSyncAction::Push, now()).await.unwrap().status,
            AgendaSyncStatus::OutcomeUnknown
        );
        drop(gui);
        server.lock().unwrap().fail_readback = false;
        let peer_store = AgendaStore::open(&directory, ACCOUNT).unwrap();
        let mut peer = SyncCoordinator::new(peer_store.clone(), remote_for(server.clone()));
        assert_eq!(
            peer.run(AgendaSyncAction::Pull, now())
                .await
                .unwrap()
                .status,
            AgendaSyncStatus::UpToDate
        );
        assert!(store.restore_sync_attempt().unwrap().is_none());
        assert_eq!(store.unsynced_count().unwrap(), 0);
        assert_eq!(server.lock().unwrap().published.len(), 1);
        peer_store.create(event()).unwrap();
        peer.run(AgendaSyncAction::Push, now()).await.unwrap();
        let mut gui = SyncCoordinator::new(store, remote_for(server.clone()));
        assert_eq!(
            gui.run(AgendaSyncAction::Pull, now()).await.unwrap().status,
            AgendaSyncStatus::UpToDate
        );
        assert_eq!(server.lock().unwrap().published.len(), 2);
    });
}
#[test]
fn registered_but_changed_current_version_cannot_confirm_dirty_records() {
    runtime().block_on(async {
        let (store, remote, server) = setup();
        store.create(event()).unwrap();
        server.lock().unwrap().fail_readback = true;
        let mut gui = SyncCoordinator::new(store.clone(), remote);
        gui.run(AgendaSyncAction::Push, now()).await.unwrap();
        drop(gui);
        {
            let mut s = server.lock().unwrap();
            s.fail_readback = false;
            s.files.values_mut().next().unwrap().0.revision += 1;
        }
        let mut peer = SyncCoordinator::new(store.clone(), remote_for(server.clone()));
        assert_eq!(
            peer.run(AgendaSyncAction::Pull, now())
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
fn local_clear_scrubs_body_and_blocks_new_publication_but_allows_other_device_merge() {
    runtime().block_on(async {
        let (store, remote, server) = setup();
        let mut item = event();
        item.content.title = "应随清除消失的合成标题".into();
        let id = item.id;
        store.create(item).unwrap();
        server.lock().unwrap().unknown = true;
        let mut gui = SyncCoordinator::new(store.clone(), remote);
        gui.run(AgendaSyncAction::Push, now()).await.unwrap();
        assert_eq!(store.clear_local_data().unwrap(), 1);
        assert!(
            !store
                .restore_sync_attempt()
                .unwrap()
                .unwrap()
                .retains_body()
        );
        assert!(store.get(id).unwrap().is_none());
        let other = AgendaStore::open(&root(), ACCOUNT).unwrap();
        let item = event();
        let other_id = item.id;
        other.create(item).unwrap();
        insert_snapshot(&server, &other, 1);
        let item = event();
        let fresh_id = item.id;
        store.create(item).unwrap();
        let mut reopened = SyncCoordinator::new(store.clone(), remote_for(server.clone()));
        assert_eq!(
            reopened
                .run(AgendaSyncAction::Push, now())
                .await
                .unwrap()
                .status,
            AgendaSyncStatus::OutcomeUnknown
        );
        assert!(store.get(id).unwrap().is_none());
        assert!(store.get(other_id).unwrap().is_some());
        assert!(store.get(fresh_id).unwrap().is_some());
        assert_eq!(server.lock().unwrap().published.len(), 1);
    });
}
#[test]
fn local_clear_revokes_a_sent_attempt_before_its_late_result() {
    runtime().block_on(async {
        for expected in [false, true] {
            let directory = root();
            let store = AgendaStore::open(&directory, ACCOUNT).unwrap();
            let item = event();
            let id = item.id;
            store.create(item).unwrap();
            let (_, mut remote, server) = setup();
            let gate = gate();
            remote.after_send_gate = Some(gate.clone());
            let moved = store.clone();
            let task = tokio::spawn(async move {
                SyncCoordinator::new(moved, remote)
                    .run(AgendaSyncAction::Push, now())
                    .await
            });
            gate.entered.notified().await;
            let old = store.restore_sync_attempt().unwrap().unwrap().snapshot;
            let peer = AgendaStore::open(&directory, ACCOUNT).unwrap();
            assert_eq!(
                if expected {
                    peer.clear_local_data_if_unsynced(1)
                } else {
                    peer.clear_local_data()
                }
                .unwrap(),
                1
            );
            assert!(!peer.restore_sync_attempt().unwrap().unwrap().retains_body());
            assert!(peer.get(id).unwrap().is_none());
            assert!(matches!(
                peer.confirm_sync(&old, old.document()),
                Err(crate::cache::CacheError::Superseded)
            ));
            gate.released.notify_one();
            assert!(matches!(
                task.await.unwrap(),
                Err(super::super::AgendaSyncError::Local(
                    crate::cache::CacheError::Superseded
                ))
            ));
            let report = SyncCoordinator::new(peer.clone(), remote_for(server.clone()))
                .run(AgendaSyncAction::Push, now())
                .await
                .unwrap();
            assert_eq!(report.status, AgendaSyncStatus::OutcomeUnknown);
            assert!(peer.get(id).unwrap().is_none());
            assert_eq!(server.lock().unwrap().published.len(), 1);
        }
    });
}
#[test]
fn complete_read_chooses_highest_publication_even_when_older_file_arrives_late() {
    runtime().block_on(async {
        let (store, remote, server) = setup();
        let other = AgendaStore::open(&root(), ACCOUNT).unwrap();
        let item = event();
        let id = item.id;
        let time = item.updated_at;
        let mut content = item.content.clone();
        other.create(item).unwrap();
        let old = other.sync_snapshot().unwrap().document().clone();
        content.title = "同设备的新版本".into();
        other
            .edit(id, AgendaEditScope::All, None, content, None, time)
            .unwrap();
        insert_snapshot(&server, &other, 5);
        let older = Publication {
            publisher: other.sync_snapshot().unwrap().device_id,
            sequence: 4,
        };
        server.lock().unwrap().files.insert(
            older,
            (
                Version {
                    identity: older,
                    revision: 1,
                },
                older.encode(&old).unwrap(),
            ),
        );
        let mut driver = SyncCoordinator::new(store.clone(), remote);
        driver.run(AgendaSyncAction::Pull, now()).await.unwrap();
        assert_eq!(
            store.get(id).unwrap().unwrap().content.title,
            "同设备的新版本"
        );
        assert_eq!(server.lock().unwrap().reads.len(), 1);
    });
}
#[test]
fn one_corrupt_selected_snapshot_keeps_all_local_rows_unchanged() {
    runtime().block_on(async {
        let (store, remote, server) = setup();
        let local = event();
        let local_id = local.id;
        store.create(local).unwrap();
        let before = store.sync_snapshot().unwrap().document().clone();
        for corrupt in [false, true] {
            let other = AgendaStore::open(&root(), ACCOUNT).unwrap();
            other.create(event()).unwrap();
            let identity = insert_snapshot(&server, &other, 1);
            if corrupt {
                server.lock().unwrap().files.get_mut(&identity).unwrap().1 = b"{}".to_vec();
            }
        }
        let result = SyncCoordinator::new(store.clone(), remote)
            .run(AgendaSyncAction::Pull, now())
            .await;
        assert!(result.is_err());
        assert_eq!(store.sync_snapshot().unwrap().document(), &before);
        assert!(store.get(local_id).unwrap().is_some());
    });
}
#[test]
fn compact_deletion_summary_prevents_old_device_resurrection_after_purge() {
    runtime().block_on(async {
        let (store, remote, server) = setup();
        let item = event();
        let id = item.id;
        store.create(item).unwrap();
        let old = store.sync_snapshot().unwrap().document().clone();
        store.delete(id, AgendaEditScope::All, None, now()).unwrap();
        let mut driver = SyncCoordinator::new(store.clone(), remote);
        driver.run(AgendaSyncAction::Push, now()).await.unwrap();
        let later = t("2026-09-05T00:00:00+08:00");
        driver.run(AgendaSyncAction::Pull, later).await.unwrap();
        assert!(store.get(id).unwrap().is_none());
        let stale = Publication {
            publisher: Uuid::new_v4(),
            sequence: 999,
        };
        server.lock().unwrap().files.insert(
            stale,
            (
                Version {
                    identity: stale,
                    revision: 1,
                },
                stale.encode(&old).unwrap(),
            ),
        );
        driver.run(AgendaSyncAction::Pull, later).await.unwrap();
        assert!(store.get(id).unwrap().is_none());
        let document = store.sync_snapshot().unwrap().document().clone();
        assert!(document.items.is_empty());
        assert_eq!(document.item_deletions[0].id, id);
        assert_eq!(server.lock().unwrap().published.len(), 1);
    });
}

#[test]
fn another_devices_copy_cannot_acknowledge_an_unknown_pending_publication() {
    runtime().block_on(async {
        for deleted in [false, true] {
            let (store, remote, server) = setup();
            let item = event();
            let id = item.id;
            store.create(item).unwrap();
            if deleted {
                store.delete(id, AgendaEditScope::All, None, now()).unwrap();
            }
            let key = crate::domain::agenda::SchoolAgendaKey {
                source: "spoc".into(),
                upstream_id: "合成作业".into(),
            };
            store
                .set_overlay(
                    crate::domain::agenda::SchoolAgendaOverlay {
                        key: key.clone(),
                        completed_at: None,
                        completion_override: false,
                        hidden: true,
                        note: Some("未决覆盖".into()),
                        updated_at: now(),
                        deleted_at: None,
                        locally_modified: false,
                    },
                    now(),
                )
                .unwrap();
            if deleted {
                store.clear_overlay(&key, now()).unwrap();
            }
            let sent = store.sync_snapshot().unwrap().document().clone();
            server.lock().unwrap().unknown = true;
            let mut driver = SyncCoordinator::new(store.clone(), remote);
            driver.run(AgendaSyncAction::Push, now()).await.unwrap();
            let peer = AgendaStore::open(&root(), ACCOUNT).unwrap();
            let scope = peer.sync_snapshot().unwrap();
            peer.merge_sync(&scope, &sent).unwrap();
            insert_snapshot(&server, &peer, 1);
            assert_eq!(
                driver
                    .run(AgendaSyncAction::Pull, now())
                    .await
                    .unwrap()
                    .status,
                AgendaSyncStatus::OutcomeUnknown
            );
            assert_eq!(store.unsynced_count().unwrap(), 2);
            assert!(store.restore_sync_attempt().unwrap().is_some());
            assert_eq!(server.lock().unwrap().published.len(), 1);
        }
    });
}

#[test]
fn same_registered_identity_with_different_body_is_rejected_before_any_local_merge() {
    runtime().block_on(async {
        let (store, remote, server) = setup();
        let item = event();
        let id = item.id;
        store.create(item).unwrap();
        server.lock().unwrap().fail_readback = true;
        let mut driver = SyncCoordinator::new(store.clone(), remote);
        driver.run(AgendaSyncAction::Push, now()).await.unwrap();
        let before = store.sync_snapshot().unwrap().document().clone();
        {
            let mut state = server.lock().unwrap();
            state.fail_readback = false;
            let (version, bytes) = state.files.values_mut().next().unwrap();
            *bytes = version
                .identity
                .encode(&super::super::AgendaSyncDocument::default())
                .unwrap();
        }
        assert!(driver.run(AgendaSyncAction::Pull, now()).await.is_err());
        assert_eq!(store.sync_snapshot().unwrap().document(), &before);
        assert!(store.get(id).unwrap().unwrap().locally_modified);
    });
}

#[test]
fn local_clear_releases_directory_attempt_and_late_creation_cannot_block_next_publication() {
    runtime().block_on(async {
        for expected in [false, true] {
            let directory = root();
            let store = AgendaStore::open(&directory, ACCOUNT).unwrap();
            let item = event();
            let id = item.id;
            store.create(item).unwrap();
            let (_, mut remote, server) = setup();
            {
                let mut state = server.lock().unwrap();
                state.directory_missing = true;
                state.unknown_directory = true;
            }
            let gate = gate();
            remote.after_send_gate = Some(gate.clone());
            let moved = store.clone();
            let task = tokio::spawn(async move {
                SyncCoordinator::new(moved, remote)
                    .run(AgendaSyncAction::CreateConfirmed, now())
                    .await
            });
            gate.entered.notified().await;
            let pending = store.restore_sync_attempt().unwrap().unwrap();
            assert!(pending.snapshot.publication.is_none());
            let peer = AgendaStore::open(&directory, ACCOUNT).unwrap();
            assert_eq!(
                if expected {
                    peer.clear_local_data_if_unsynced(1)
                } else {
                    peer.clear_local_data()
                }
                .unwrap(),
                1
            );
            assert!(
                peer.restore_sync_attempt().unwrap().is_none(),
                "清除本机数据后，目录创建在途不能占用文件发布位置"
            );
            assert!(peer.get(id).unwrap().is_none());
            gate.released.notify_one();
            assert!(matches!(
                task.await.unwrap(),
                Err(super::super::AgendaSyncError::Local(
                    crate::cache::CacheError::Superseded
                ))
            ));
            let item = event();
            let next_id = item.id;
            peer.create(item).unwrap();
            let report = SyncCoordinator::new(peer.clone(), remote_for(server.clone()))
                .run(AgendaSyncAction::Push, now())
                .await
                .unwrap();
            assert_eq!(report.status, AgendaSyncStatus::UpToDate);
            assert!(peer.get(next_id).unwrap().is_some());
            assert!(peer.restore_sync_attempt().unwrap().is_none());
            let state = server.lock().unwrap();
            assert_eq!(state.directory_creates, 1);
            assert_eq!(state.published.len(), 1);
            assert_eq!(state.published[0].sequence, 1);
        }
    });
}
