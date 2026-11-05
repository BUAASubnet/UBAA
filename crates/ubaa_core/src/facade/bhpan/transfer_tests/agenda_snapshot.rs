use super::*;
use crate::{
    agenda::AgendaStore,
    agenda::sync::publication::Publication,
    facade::{AgendaSyncAction, AgendaSyncService, AgendaSyncStatus, SharedAccountGuard},
};
fn t(value: &str) -> crate::domain::agenda::AgendaTime {
    crate::domain::agenda::AgendaTime::new(value.parse().unwrap())
}
fn event() -> crate::domain::agenda::AgendaItem {
    use crate::domain::agenda::*;
    AgendaItem::new(
        AgendaContent {
            kind: AgendaKind::Event,
            title: "合成日程".into(),
            location: None,
            notes: None,
            color: None,
            start: Some(t("2026-11-05T09:00:00+08:00")),
            end: Some(t("2026-11-05T10:00:00+08:00")),
            all_day: false,
            due: None,
        },
        t("2026-11-05T00:00:00+08:00"),
    )
}
fn store(f: &mut Fixture) -> AgendaStore {
    for (name, value) in [
        ("materials.lock", ""),
        ("transaction.v1", "UBAA1:C"),
        ("account-generation.v1", "UBAA1:1"),
    ] {
        std::fs::write(f.root.join(name), value).unwrap();
    }
    let guard = SharedAccountGuard::new(&f.root, 1).unwrap();
    let store =
        AgendaStore::open_shared(&f.root, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", guard.clone())
            .unwrap();
    f.client.bind_shared_account(Some(guard));
    store
}
fn entry(id: &str, name: &str, size: i64) -> serde_json::Value {
    json!({"id":id,"name":name,"size":size,"rev":"r","created_at":"2026-11-05T01:00:00Z","modified_at":"2026-11-05T01:00:00Z"})
}
fn locate(f: &Fixture, files: &[serde_json::Value], dirs: &[serde_json::Value]) {
    f.transport.script.add(
        HttpMethod::Get,
        "/api/efast/v1/owned-doc-lib",
        None,
        r#"[{"id":"gns://fixture/root","name":"个人"}]"#.as_bytes(),
    );
    for (path, items) in [
        (
            "/api/efast/v1/folders/gns%3A%2F%2Ffixture%2Froot/sub_objects?limit=1000",
            vec![entry("gns://fixture/ubaa", "UBAA", -1)],
        ),
        (
            "/api/efast/v1/folders/gns%3A%2F%2Ffixture%2Fubaa/sub_objects?limit=1000",
            vec![entry("gns://fixture/target", "agenda_snapshots", -1)],
        ),
    ] {
        f.transport.script.add(
            HttpMethod::Get,
            path,
            None,
            &serde_json::to_vec(&json!({"dirs":items,"files":[],"next_marker":""})).unwrap(),
        );
    }
    f.transport.script.add(
        HttpMethod::Get,
        "/api/efast/v1/folders/gns%3A%2F%2Ffixture%2Ftarget/sub_objects?limit=1000",
        None,
        &serde_json::to_vec(&json!({"dirs":dirs,"files":files,"next_marker":""})).unwrap(),
    );
}
#[tokio::test]
async fn 快照发布只新建独立文件并在最终登记后读取当前版本正文确认() {
    let mut f = Fixture::new();
    let store = store(&mut f);
    store.create(event()).unwrap();
    let sent = store.sync_snapshot().unwrap();
    let identity = Publication {
        publisher: sent.document().items[0].device_id,
        sequence: 1,
    };
    let name = identity.file_name();
    let body = identity.encode(sent.document()).unwrap();
    let length = body.len() as u64;
    locate(&f, &[], &[]);
    f.transport.script.add(HttpMethod::Post,"/api/efast/v1/file/osbeginupload",Some(json!({"docid":"gns://fixture/target","length":length,"name":name,"ondup":1})),&serde_json::to_vec(&json!({"docid":"gns://fixture/created","rev":"upload-revision","authrequest":["PUT",OBJECT,"Authorization: object-only"]})).unwrap());
    f.transport
        .objects
        .lock()
        .unwrap()
        .push_back(ObjectStep::ok(length));
    f.end(b"{}");
    locate(
        &f,
        &[entry(
            "gns://fixture/created",
            &name,
            i64::try_from(length).unwrap(),
        )],
        &[],
    );
    f.transport.script.add(HttpMethod::Post,"/api/efast/v1/file/metadata",Some(json!({"docid":"gns://fixture/created"})),&serde_json::to_vec(&json!({"docid":"gns://fixture/created","rev":"upload-revision","name":name,"size":length})).unwrap());
    f.transport.script.add(HttpMethod::Post,"/api/efast/v1/file/osdownload",Some(json!({"docid":"gns://fixture/created","rev":"upload-revision","authtype":"QUERY_STRING"})),&serde_json::to_vec(&json!({"docid":"gns://fixture/created","rev":"upload-revision","name":name,"size":length,"authrequest":["GET",OBJECT,"Authorization: object-only"]})).unwrap());
    f.transport.objects.lock().unwrap().push_back(ObjectStep {
        status: 200,
        etag: None,
        length: None,
        bytes: body,
    });
    let mut service = AgendaSyncService::new(store.clone(), f.root.join("scratch"));
    let report = service
        .run(
            &mut f.client,
            AgendaSyncAction::Push,
            t("2026-11-05T03:00:00+08:00"),
        )
        .await
        .unwrap();
    assert_eq!(report.status, AgendaSyncStatus::UpToDate);
    assert_eq!(report.pending_count, 0);
    assert!(!store.sync_enabled().unwrap());
    drop(service);
    drop(store);
    f.finish();
}
#[tokio::test]
async fn 同步目录中的子目录或非法快照名使整轮失败并保留本机数据() {
    for folder in [true, false] {
        let mut f = Fixture::new();
        let store = store(&mut f);
        let item = event();
        store.create(item.clone()).unwrap();
        let invalid = entry(
            "gns://fixture/unexpected",
            "unexpected",
            if folder { -1 } else { 5 },
        );
        locate(
            &f,
            &if folder {
                vec![]
            } else {
                vec![invalid.clone()]
            },
            &if folder { vec![invalid] } else { vec![] },
        );
        let mut service = AgendaSyncService::new(store.clone(), f.root.join("scratch"));
        let report = service
            .run(
                &mut f.client,
                AgendaSyncAction::Pull,
                t("2026-11-05T03:00:00+08:00"),
            )
            .await;
        assert!(report.is_err() || report.unwrap().status == AgendaSyncStatus::Failed);
        assert_eq!(store.get(item.id).unwrap(), Some(item));
        assert_eq!(store.unsynced_count().unwrap(), 1);
        drop(service);
        drop(store);
        f.finish();
    }
}
