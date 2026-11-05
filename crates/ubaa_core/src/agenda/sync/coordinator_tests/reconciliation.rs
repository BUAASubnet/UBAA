use super::*;

#[test]
fn unknown_directory_creation_is_reconciled_without_publishing_the_file() {
    runtime().block_on(async {
        let (store, remote, server) = setup();
        store.create(event()).unwrap();
        server.lock().unwrap().directory_missing = true;
        let mut first = SyncCoordinator::new(store.clone(), remote);
        let report = first
            .run(AgendaSyncAction::CreateConfirmed, now())
            .await
            .unwrap();
        assert_eq!(report.status, AgendaSyncStatus::OutcomeUnknown);
        assert_eq!(report.pending_count, 1);
        assert!(store.restore_sync_attempt().unwrap().is_some());

        let (_, mut remote, _) = setup();
        remote.server = server.clone();
        let mut reopened = SyncCoordinator::new(store.clone(), remote);
        let report = reopened.run(AgendaSyncAction::Pull, now()).await.unwrap();
        assert_eq!(report.status, AgendaSyncStatus::NeedsCreation);
        assert_eq!(report.pending_count, 1);
        assert!(store.restore_sync_attempt().unwrap().is_none());
        {
            let state = server.lock().unwrap();
            assert_eq!(state.directory_creates, 1);
            assert!(state.bases.is_empty());
        }
        let report = reopened
            .run(AgendaSyncAction::CreateConfirmed, now())
            .await
            .unwrap();
        assert_eq!(report.status, AgendaSyncStatus::UpToDate);
        assert_eq!(server.lock().unwrap().bases, vec![None]);
    });
}

#[test]
fn create_confirmed_never_updates_a_file_found_on_recheck() {
    runtime().block_on(async {
        let (store, remote, server) = setup();
        store.create(event()).unwrap();
        let mut gui = SyncCoordinator::new(store, remote);
        assert_eq!(
            gui.run(AgendaSyncAction::Pull, now()).await.unwrap().status,
            AgendaSyncStatus::NeedsCreation
        );
        let other = AgendaStore::open(&root(), ACCOUNT).unwrap();
        other.create(event()).unwrap();
        let original = other.sync_snapshot().unwrap().document().encode().unwrap();
        server.lock().unwrap().document = Some(original.clone());
        let result = gui
            .run(AgendaSyncAction::CreateConfirmed, now())
            .await
            .unwrap();
        assert_eq!(result.status, AgendaSyncStatus::Pending);
        let state = server.lock().unwrap();
        assert!(
            state.bases.is_empty(),
            "只确认了首次创建，重新定位发现现有文件时不得更新"
        );
        assert_eq!(state.document.as_ref(), Some(&original));
    });
}

#[test]
fn gui_reloads_durable_attempt_after_peer_reconciles_and_pushes() {
    runtime().block_on(async {
        let directory = root();
        let store = AgendaStore::open(&directory, ACCOUNT).unwrap();
        store.create(event()).unwrap();
        let (_, remote, server) = setup();
        server.lock().unwrap().document = Some(
            super::super::AgendaSyncDocument::default()
                .encode()
                .unwrap(),
        );
        server.lock().unwrap().unknown = true;
        let mut gui = SyncCoordinator::new(store.clone(), remote);
        assert_eq!(
            gui.run(AgendaSyncAction::Push, now()).await.unwrap().status,
            AgendaSyncStatus::OutcomeUnknown
        );
        let (_, mut remote, _) = setup();
        remote.server = server.clone();
        let peer_store = AgendaStore::open(&directory, ACCOUNT).unwrap();
        let mut peer = SyncCoordinator::new(peer_store.clone(), remote);
        assert_eq!(
            peer.run(AgendaSyncAction::Pull, now())
                .await
                .unwrap()
                .status,
            AgendaSyncStatus::UpToDate
        );
        assert!(store.restore_sync_attempt().unwrap().is_none());
        peer_store.create(event()).unwrap();
        server.lock().unwrap().unknown = false;
        assert_eq!(
            peer.run(AgendaSyncAction::Push, now())
                .await
                .unwrap()
                .status,
            AgendaSyncStatus::UpToDate
        );
        let result = gui.run(AgendaSyncAction::Pull, now()).await.unwrap();
        assert_eq!(result.status, AgendaSyncStatus::UpToDate);
    });
}

#[test]
fn successful_local_clear_does_not_keep_the_agenda_body_in_pending() {
    runtime().block_on(async {
        let (store, remote, server) = setup();
        let mut item = event();
        item.content.title = "应随本机数据清除的合成标题".into();
        let id = item.id;
        store.create(item).unwrap();
        server.lock().unwrap().document = Some(
            super::super::AgendaSyncDocument::default()
                .encode()
                .unwrap(),
        );
        server.lock().unwrap().unregistered_revision_readable = true;
        let mut gui = SyncCoordinator::new(store.clone(), remote);
        assert_eq!(
            gui.run(AgendaSyncAction::Push, now()).await.unwrap().status,
            AgendaSyncStatus::OutcomeUnknown
        );
        assert_eq!(store.clear_local_data().unwrap(), 1);
        let pending = store.restore_sync_attempt().unwrap();
        assert!(
            pending.is_none(),
            "成功清除本机日程后不能仍保留完整明文发送快照"
        );
        assert!(store.get(id).unwrap().is_none());
    });
}

#[test]
fn local_clear_revokes_a_sent_attempt_before_its_late_result() {
    runtime().block_on(async {
        for clear_with_expected_count in [false, true] {
            let directory = root();
            let store = AgendaStore::open(&directory, ACCOUNT).unwrap();
            let item = event();
            let id = item.id;
            store.create(item).unwrap();
            let (_, remote, server) = setup();
            {
                let mut state = server.lock().unwrap();
                state.document = Some(
                    super::super::AgendaSyncDocument::default()
                        .encode()
                        .unwrap(),
                );
                state.unregistered_revision_readable = true;
            }
            let gate = Arc::new(Gate {
                entered: tokio::sync::Notify::new(),
                released: tokio::sync::Notify::new(),
            });
            let mut sender = SyncCoordinator::new(
                store.clone(),
                StopAfterSend {
                    inner: remote,
                    gate: gate.clone(),
                },
            );
            let task = tokio::spawn(async move { sender.run(AgendaSyncAction::Push, now()).await });
            gate.entered.notified().await;
            let (old, _, _) = store.restore_sync_attempt().unwrap().unwrap();
            let peer = AgendaStore::open(&directory, ACCOUNT).unwrap();
            let cleared = if clear_with_expected_count {
                peer.clear_local_data_if_unsynced(1)
            } else {
                peer.clear_local_data()
            };
            assert_eq!(cleared.unwrap(), 1);
            assert!(peer.restore_sync_attempt().unwrap().is_none());
            assert!(peer.get(id).unwrap().is_none());
            assert!(matches!(
                peer.confirm_sync(&old, old.document()),
                Err(crate::cache::CacheError::Superseded)
            ));
            gate.released.notify_one();
            assert!(matches!(
                task.await.unwrap(),
                Err(crate::facade::AgendaSyncError::Local(
                    crate::cache::CacheError::Superseded
                ))
            ));

            let (_, mut remote, _) = setup();
            remote.server = server.clone();
            let mut reopened = SyncCoordinator::new(peer.clone(), remote);
            let report = reopened.run(AgendaSyncAction::Push, now()).await.unwrap();
            assert_eq!(report.status, AgendaSyncStatus::UpToDate);
            assert!(peer.get(id).unwrap().is_none());
            assert!(peer.restore_sync_attempt().unwrap().is_none());
            assert_eq!(server.lock().unwrap().bases.len(), 1);
        }
    });
}

#[test]
fn a_peer_that_already_synced_a_retired_tombstone_does_not_publish_it_again() {
    runtime().block_on(async {
        let (store, remote, server) = setup();
        let item = event();
        let id = item.id;
        store.create(item).unwrap();
        store.delete(id, AgendaEditScope::All, None, now()).unwrap();
        server.lock().unwrap().document =
            Some(store.sync_snapshot().unwrap().document().encode().unwrap());
        let mut driver = SyncCoordinator::new(store.clone(), remote);
        assert_eq!(
            driver
                .run(AgendaSyncAction::Pull, now())
                .await
                .unwrap()
                .status,
            AgendaSyncStatus::UpToDate
        );
        assert_eq!(store.unsynced_count().unwrap(), 0);
        {
            let mut state = server.lock().unwrap();
            state.document = Some(
                super::super::AgendaSyncDocument::default()
                    .encode()
                    .unwrap(),
            );
            state.revision += 1;
        }
        let later = t("2026-09-05T00:00:00+08:00");
        assert_eq!(
            driver
                .run(AgendaSyncAction::Push, later)
                .await
                .unwrap()
                .status,
            AgendaSyncStatus::UpToDate
        );
        let state = server.lock().unwrap();
        assert!(
            state.bases.is_empty(),
            "同库的旧删除标记已同步且超过180天，远端清理不应将其变回未同步并重新发布"
        );
        assert!(store.get(id).unwrap().is_none());
    });
}
