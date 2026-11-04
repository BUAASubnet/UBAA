use super::*;
#[tokio::test]
async fn 单文件下载完整后交付且授权不进入结果() {
    let mut f = Fixture::new();
    let item = f.file(5);
    f.download_auth(b"hello".to_vec());
    let path = f.root.join("delivered.txt");
    let transfer = BhpanTransfer::new();
    let receipt = f
        .client
        .bhpan_download(
            &[item.handle],
            "notes",
            path.clone(),
            false,
            transfer.clone(),
        )
        .await
        .unwrap();
    assert_eq!(std::fs::read(&path).unwrap(), b"hello");
    assert_eq!(receipt.bytes, 5);
    assert!(!receipt.batch);
    assert_eq!(transfer.progress().phase, BhpanTransferPhase::Completed);
    assert!(
        !serde_json::to_string(&receipt)
            .unwrap()
            .contains("signature")
    );
    f.finish();
}
#[tokio::test]
async fn 取消或截断下载清理临时文件且不覆盖原文件() {
    for cancel in [false, true] {
        let mut f = Fixture::new();
        let item = f.file(5);
        let path = f.root.join("delivered.txt");
        std::fs::write(&path, b"original").unwrap();
        f.download_auth(if cancel {
            b"hello".to_vec()
        } else {
            b"hell".to_vec()
        });
        let transfer = BhpanTransfer::new();
        if cancel {
            *f.transport.stop.lock().unwrap() = Some(transfer.clone());
        }
        assert!(
            f.client
                .bhpan_download(
                    &[item.handle],
                    "notes",
                    path.clone(),
                    true,
                    transfer.clone()
                )
                .await
                .is_err()
        );
        assert_eq!(std::fs::read(&path).unwrap(), b"original");
        assert!(!std::fs::read_dir(&f.root).unwrap().any(|entry| {
            entry
                .unwrap()
                .file_name()
                .to_string_lossy()
                .ends_with(".part")
        }));
        if cancel {
            assert_eq!(transfer.progress().phase, BhpanTransferPhase::Cancelled);
        }
        f.finish();
    }
}
#[tokio::test]
async fn 目录打包使用本次_api返回地址并以_get完整交付() {
    let mut f = Fixture::new();
    let path = f.root.join("bundle.zip");
    f.transport.script.add(HttpMethod::Post,"/api/efast/v1/file/batchdownload",Some(json!({"name":"bundle.zip","reqhost":"bhpan.buaa.edu.cn","dirs":["gns://fixture/target"],"files":[]})),serde_json::to_vec(&json!({"url":OBJECT})).unwrap().as_slice());
    f.transport.objects.lock().unwrap().push_back(ObjectStep {
        status: 200,
        etag: None,
        length: Some(0),
        bytes: b"synthetic zip body".to_vec(),
    });
    let receipt = f
        .client
        .bhpan_download(
            &[f.parent.handle.clone()],
            "bundle",
            path.clone(),
            false,
            BhpanTransfer::new(),
        )
        .await
        .unwrap();
    assert!(receipt.batch);
    assert_eq!(std::fs::read(path).unwrap(), b"synthetic zip body");
    f.finish();
}
