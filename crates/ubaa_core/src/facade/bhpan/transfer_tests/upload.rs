use super::*;
#[tokio::test]
async fn 普通上传在确认后流式发送并检查最终登记且确认只消费一次() {
    let mut f = Fixture::new();
    let path = f.source(200_003);
    f.begin(200_003);
    f.end(b"{}");
    f.transport
        .objects
        .lock()
        .unwrap()
        .push_back(ObjectStep::ok(200_003));
    let transfer = BhpanTransfer::new();
    let prepared = f
        .client
        .bhpan_prepare_upload(&f.parent.handle, path, "notes.txt", transfer.clone())
        .await
        .unwrap();
    assert_eq!(f.transport.business_calls.load(Ordering::SeqCst), 0);
    f.client.bhpan_commit_write(&prepared.handle).await.unwrap();
    assert_eq!(transfer.progress().phase, BhpanTransferPhase::Completed);
    assert_eq!(transfer.progress().bytes, 200_003);
    assert!(f.client.bhpan_commit_write(&prepared.handle).await.is_err());
    assert_eq!(f.transport.object_calls.load(Ordering::SeqCst), 1);
    f.finish();
}
#[tokio::test]
async fn 非成功对象状态带_etag或最终登记error均停止且不重试() {
    for end_error in [false, true] {
        let mut f = Fixture::new();
        let path = f.source(5);
        f.begin(5);
        let mut step = ObjectStep::ok(5);
        if end_error {
            f.end(br#"{"error":"synthetic"}"#);
        } else {
            step.status = 500;
        }
        f.transport.objects.lock().unwrap().push_back(step);
        let p = f
            .client
            .bhpan_prepare_upload(&f.parent.handle, path, "notes.txt", BhpanTransfer::new())
            .await
            .unwrap();
        let error = f.client.bhpan_commit_write(&p.handle).await.unwrap_err();
        assert_eq!(error.code, crate::error::ErrorCode::OutcomeUnknown);
        assert!(!error.retryable);
        assert_eq!(f.transport.object_calls.load(Ordering::SeqCst), 1);
        f.finish();
    }
}
#[tokio::test]
async fn 文件确认后改变保持零发送而对象发送中取消或文件改变不登记() {
    for change in 0..3 {
        let mut f = Fixture::new();
        let path = f.source(5);
        let transfer = BhpanTransfer::new();
        let p = f
            .client
            .bhpan_prepare_upload(
                &f.parent.handle,
                path.clone(),
                "notes.txt",
                transfer.clone(),
            )
            .await
            .unwrap();
        if change == 0 {
            std::fs::write(&path, b"changed").unwrap();
        } else {
            f.begin(5);
            f.transport
                .objects
                .lock()
                .unwrap()
                .push_back(ObjectStep::ok(5));
            if change == 1 {
                *f.transport.stop.lock().unwrap() = Some(transfer.clone());
            } else {
                *f.transport.change_file.lock().unwrap() = Some(path);
            }
        }
        let error = f.client.bhpan_commit_write(&p.handle).await.unwrap_err();
        assert_eq!(
            error.code,
            if change == 0 {
                crate::error::ErrorCode::InvalidInput
            } else {
                crate::error::ErrorCode::OutcomeUnknown
            }
        );
        assert_eq!(
            f.transport.business_calls.load(Ordering::SeqCst),
            usize::from(change != 0)
        );
        f.finish();
    }
}
#[tokio::test]
async fn 分片按20_mi_b编号顺序上传并验证每片_etag合并和最终登记() {
    let mut f = Fixture::new();
    let length = 100 * 1024 * 1024 + 3;
    let path = f.source(length);
    f.transport.script.add(
        HttpMethod::Post,
        "/api/efast/v1/file/osinitmultiupload",
        Some(json!({"docid":"gns://fixture/target","length":length,"name":"notes.txt","ondup":1})),
        br#"{"docid":"gns://fixture/created","rev":"upload-revision","uploadid":"upload-id"}"#,
    );
    let mut auth = serde_json::Map::new();
    let mut partinfo = serde_json::Map::new();
    for number in 1..=6 {
        let size = if number == 6 { 3 } else { 20 * 1024 * 1024 };
        auth.insert(
            number.to_string(),
            json!(["PUT", OBJECT, "Authorization: object-only"]),
        );
        partinfo.insert(number.to_string(), json!(["part-etag", size]));
        f.transport
            .objects
            .lock()
            .unwrap()
            .push_back(ObjectStep::ok(size));
    }
    f.transport.script.add(HttpMethod::Post,"/api/efast/v1/file/osuploadpart",Some(json!({"docid":"gns://fixture/created","rev":"upload-revision","uploadid":"upload-id","parts":"1-6"})),serde_json::to_vec(&json!({"authrequests":auth})).unwrap().as_slice());
    let response = format!(
        "--fixture\r\nContent-Type: application/xml\r\n\r\n<Complete>part-with-hyphen</Complete>\r\n--fixture\r\nContent-Type: application/json\r\n\r\n{{\"authrequest\":[\"POST\",\"{OBJECT}\",\"Authorization: object-only\"]}}\r\n--fixture--\r\n"
    );
    f.transport.script.add(HttpMethod::Post,"/api/efast/v1/file/oscompleteupload",Some(json!({"docid":"gns://fixture/created","rev":"upload-revision","uploadid":"upload-id","partinfo":partinfo})),response.as_bytes());
    f.transport
        .objects
        .lock()
        .unwrap()
        .push_back(ObjectStep::ok(0));
    f.end(b"{}");
    let transfer = BhpanTransfer::new();
    let p = f
        .client
        .bhpan_prepare_upload(&f.parent.handle, path, "notes.txt", transfer.clone())
        .await
        .unwrap();
    f.client.bhpan_commit_write(&p.handle).await.unwrap();
    assert_eq!(transfer.progress().bytes, length);
    assert_eq!(f.transport.object_calls.load(Ordering::SeqCst), 7);
    f.finish();
}

#[tokio::test]
async fn 传输授权等待期间取消立即结束且不继续对象或最终登记() {
    for upload in [false, true] {
        let mut f = Fixture::new();
        let transfer = BhpanTransfer::new();
        f.transport.business_gate = Some(Arc::new(tokio::sync::Notify::new()));
        // 客户端持有同一合成传输实例。
        let mut config = RouteConfig::default();
        config.replace_default_policy(RoutePolicy::Direct);
        f.client = UbaaClient::with_routing(
            f.transport.clone(),
            f.transport.clone(),
            FileSessionStore::new(&f.root).unwrap(),
            config,
            NeverProbe,
        )
        .unwrap();
        f.client.bhpan.binding = Some(f.client.bhpan_binding());
        f.client.bhpan.token = Some(SecretValue::new("personal-fixture"));
        f.parent = super::super::tests::item(&mut f.client, BhpanScope::Personal);
        let calls = f.transport.business_calls.clone();
        let mut pending: std::pin::Pin<Box<dyn std::future::Future<Output = Result<()>> + '_>> =
            if upload {
                let path = f.source(5);
                f.begin(5);
                let p = f
                    .client
                    .bhpan_prepare_upload(&f.parent.handle, path, "notes.txt", transfer.clone())
                    .await
                    .unwrap();
                {
                    let client = &mut f.client;
                    Box::pin(async move { client.bhpan_commit_write(&p.handle).await.map(|_| ()) })
                }
            } else {
                let item = f.file(5);
                f.download_auth(b"hello".to_vec());
                f.transport.objects.lock().unwrap().clear();
                let target = f.root.join("cancelled.txt");
                let control = transfer.clone();
                let client = &mut f.client;
                Box::pin(async move {
                    client
                        .bhpan_download(&[item.handle], "notes", target, false, control)
                        .await
                        .map(|_| ())
                })
            };
        {
            let mut context = std::task::Context::from_waker(std::task::Waker::noop());
            assert!(pending.as_mut().poll(&mut context).is_pending());
        }
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        transfer.cancel();
        {
            let mut context = std::task::Context::from_waker(std::task::Waker::noop());
            assert!(
                pending.as_mut().poll(&mut context).is_ready(),
                "取消必须唤醒等待中的传输授权"
            );
        }
        drop(pending);
        assert_eq!(f.transport.object_calls.load(Ordering::SeqCst), 0);
        f.finish();
    }
}

#[tokio::test]
async fn 对象提前成功但正文未完整消费不能登记文件() {
    let mut f = Fixture::new();
    f.transport.skip_upload_body = true;
    let mut config = RouteConfig::default();
    config.replace_default_policy(RoutePolicy::Direct);
    f.client = UbaaClient::with_routing(
        f.transport.clone(),
        f.transport.clone(),
        FileSessionStore::new(&f.root).unwrap(),
        config,
        NeverProbe,
    )
    .unwrap();
    f.client.bhpan.binding = Some(f.client.bhpan_binding());
    f.client.bhpan.token = Some(SecretValue::new("personal-fixture"));
    f.parent = super::super::tests::item(&mut f.client, BhpanScope::Personal);
    let path = f.source(5);
    f.begin(5);
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
    assert_eq!(
        f.client
            .bhpan_commit_write(&p.handle)
            .await
            .unwrap_err()
            .code,
        crate::error::ErrorCode::OutcomeUnknown
    );
    assert_eq!(f.transport.business_calls.load(Ordering::SeqCst), 1);
    f.finish();
}

#[tokio::test]
async fn 开始上传明确拒绝保留原错误且对象零发送() {
    let mut f = Fixture::new();
    let source = f.source(5);
    f.begin(5);
    f.transport.script.status(403);
    let transfer = BhpanTransfer::new();
    let p = f
        .client
        .bhpan_prepare_upload(&f.parent.handle, source, "notes.txt", transfer.clone())
        .await
        .unwrap();
    let error = f.client.bhpan_commit_write(&p.handle).await.unwrap_err();
    assert_eq!(error.code, crate::error::ErrorCode::PermissionDenied);
    assert_eq!(transfer.progress().phase, BhpanTransferPhase::Failed);
    assert_eq!(f.transport.object_calls.load(Ordering::SeqCst), 0);
    f.finish();
}
#[tokio::test]
async fn 开始上传已有新版本时授权错误仍保留版本并停止发送() {
    let mut f = Fixture::new();
    let source = f.source(5);
    f.transport.script.add(HttpMethod::Post,"/api/efast/v1/file/osbeginupload",None,br#"{"docid":"gns://fixture/created","rev":"new-u","authrequest":["POST","https://object.synthetic.invalid/upload"]}"#);
    let p = f
        .client
        .bhpan_prepare_upload(&f.parent.handle, source, "notes.txt", BhpanTransfer::new())
        .await
        .unwrap();
    let crate::domain::bhpan::BhpanVersionUploadOutcome::OutcomeUnknown { version } = f
        .client
        .bhpan_commit_upload_version(&p.handle)
        .await
        .unwrap()
    else {
        panic!("授权无效应保留未知结果")
    };
    assert_eq!(version.map(|version| version.rev), Some("new-u".into()));
    assert_eq!(f.transport.object_calls.load(Ordering::SeqCst), 0);
    f.finish();
}
