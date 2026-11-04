use super::*;
use crate::domain::bhpan::{BhpanCapability, BhpanFileVersion, BhpanVersionUploadOutcome};
async fn baseline(f: &mut Fixture) -> BhpanFileVersion {
    let file = f.file(5);
    f.transport.script.add(
        HttpMethod::Post,
        "/api/efast/v1/file/metadata",
        Some(json!({"docid":"gns://fixture/file"})),
        br#"{"docid":"gns://fixture/file","rev":"base-r","name":"agenda.json","size":5}"#,
    );
    f.client
        .bhpan_file_version(&file.handle, None)
        .await
        .unwrap()
}
#[tokio::test]
async fn 元数据必须给出同对象非空基版且篡改或关闭后的快照不能发送() {
    for response in [
        br#"{"docid":"gns://fixture/other","rev":"r","name":"agenda.json","size":5}"#.as_slice(),
        br#"{"docid":"gns://fixture/file","rev":"","name":"agenda.json","size":5}"#,
        br#"{"docid":"gns://fixture/file","name":"agenda.json","size":5}"#,
    ] {
        let mut f = Fixture::new();
        let file = f.file(5);
        f.transport.script.add(
            HttpMethod::Post,
            "/api/efast/v1/file/metadata",
            Some(json!({"docid":"gns://fixture/file"})),
            response,
        );
        assert!(
            f.client
                .bhpan_file_version(&file.handle, None)
                .await
                .is_err()
        );
        f.finish();
    }
    let mut f = Fixture::new();
    let version = baseline(&mut f).await;
    let mut changed = version.clone();
    changed.rev = "other".into();
    let path = f.source(5);
    assert!(
        f.client
            .bhpan_prepare_version_upload(&changed, path.clone(), BhpanTransfer::new())
            .await
            .is_err()
    );
    f.client.close_control().close();
    assert!(
        f.client
            .bhpan_prepare_version_upload(&version, path, BhpanTransfer::new())
            .await
            .is_err()
    );
    assert_eq!(f.transport.business_calls.load(Ordering::SeqCst), 1);
    f.finish();
}
#[tokio::test]
async fn 条件更新开始和最终登记始终比较_r而使用新_u登记并固定读回() {
    for unknown in [false, true] {
        let mut f = Fixture::new();
        let version = baseline(&mut f).await;
        let path = f.source(5);
        f.transport.script.add(HttpMethod::Post,"/api/efast/v1/file/osbeginupload",Some(json!({"docid":"gns://fixture/file","length":5,"name":"","ondup":1,"editedrev":"base-r"})),serde_json::to_vec(&json!({"docid":"gns://fixture/file","rev":"new-u","authrequest":["PUT",OBJECT,"Authorization: object-only"]})).unwrap().as_slice());
        f.transport
            .objects
            .lock()
            .unwrap()
            .push_back(ObjectStep::ok(5));
        f.transport.script.add(
            HttpMethod::Post,
            "/api/efast/v1/file/osendupload",
            Some(json!({"docid":"gns://fixture/file","rev":"new-u","editedrev":"base-r"})),
            if unknown {
                br#"{"error":"synthetic"}"#
            } else {
                b"{}"
            },
        );
        let p = f
            .client
            .bhpan_prepare_version_upload(&version, path, BhpanTransfer::new())
            .await
            .unwrap();
        let outcome = f
            .client
            .bhpan_commit_upload_version(&p.handle)
            .await
            .unwrap();
        let uploaded = match outcome {
            BhpanVersionUploadOutcome::Committed { version } => {
                assert!(!unknown);
                version
            }
            BhpanVersionUploadOutcome::OutcomeUnknown { version } => {
                assert!(unknown);
                version.unwrap()
            }
        };
        assert_eq!(uploaded.docid, version.docid);
        assert_eq!(uploaded.rev, "new-u");
        assert_eq!(
            f.client.bhpan_capabilities().conditional_replace,
            BhpanCapability::Unverified
        );
        assert!(
            f.client
                .bhpan_commit_upload_version(&p.handle)
                .await
                .is_err()
        );
        f.transport.script.add(HttpMethod::Post,"/api/efast/v1/file/osdownload",Some(json!({"docid":"gns://fixture/file","rev":"new-u","authtype":"QUERY_STRING"})),serde_json::to_vec(&json!({"authrequest":["GET",OBJECT,"Authorization: object-only"],"rev":"new-u","name":"agenda.json","size":5})).unwrap().as_slice());
        f.transport.objects.lock().unwrap().push_back(ObjectStep {
            status: 200,
            etag: None,
            length: None,
            bytes: vec![0; 5],
        });
        let target = f.root.join("readback.json");
        let receipt = f
            .client
            .bhpan_download_file_version(&uploaded, target.clone(), false, BhpanTransfer::new())
            .await
            .unwrap();
        assert_eq!(receipt.version.rev, "new-u");
        assert_eq!(std::fs::read(target).unwrap(), vec![0; 5]);
        f.finish();
    }
}
#[tokio::test]
async fn 下载缺少或返回不同版本时不请求对象且未知列表不声明缺失() {
    let mut f = Fixture::new();
    let version = baseline(&mut f).await;
    f.transport.script.add(
        HttpMethod::Post,
        "/api/efast/v1/file/osdownload",
        Some(json!({"docid":"gns://fixture/file","rev":"base-r","authtype":"QUERY_STRING"})),
        serde_json::to_vec(
            &json!({"authrequest":["GET",OBJECT],"rev":"other","name":"agenda.json","size":5}),
        )
        .unwrap()
        .as_slice(),
    );
    let target = f.root.join("readback.json");
    assert!(
        f.client
            .bhpan_download_file_version(&version, target.clone(), false, BhpanTransfer::new())
            .await
            .is_err()
    );
    assert!(!target.exists());
    assert_eq!(f.transport.object_calls.load(Ordering::SeqCst), 0);
    f.transport.script.add(
        HttpMethod::Get,
        "/api/efast/v1/owned-doc-lib",
        None,
        br#"[{"id":"gns://fixture/target","name":"root"}]"#,
    );
    f.transport.script.add(
        HttpMethod::Post,
        "/api/efast/v1/dir/list",
        Some(json!({"docid":"gns://fixture/target","by":"name","sort":"asc"})),
        br#"{"dirs":[],"files":[]}"#,
    );
    assert!(matches!(
        f.client
            .bhpan_lookup_personal_path(&["UBAA".into(), "agenda.json".into()])
            .await
            .unwrap(),
        crate::domain::bhpan::BhpanPathLookup::Unknown { .. }
    ));
    f.finish();
}
#[tokio::test]
async fn 首次创建保持不覆盖参数并返回开始授权的新版本() {
    let mut f = Fixture::new();
    let path = f.source(5);
    f.begin(5);
    f.end(b"{}");
    f.transport
        .objects
        .lock()
        .unwrap()
        .push_back(ObjectStep::ok(5));
    let p = f
        .client
        .bhpan_prepare_upload(&f.parent.handle, path, "notes.txt", BhpanTransfer::new())
        .await
        .unwrap();
    let BhpanVersionUploadOutcome::Committed { version } = f
        .client
        .bhpan_commit_upload_version(&p.handle)
        .await
        .unwrap()
    else {
        panic!("完整登记应返回确定收据")
    };
    assert_eq!(version.docid, "gns://fixture/created");
    assert_eq!(version.rev, "upload-revision");
    f.finish();
}
