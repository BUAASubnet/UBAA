use super::*;

#[tokio::test]
async fn ygdk_prepare_rejects_invalid_local_input_before_storing_intent() {
    let path = std::env::temp_dir().join(format!(
        "ubaa-bridge-ygdk-input-{}-{:?}",
        std::process::id(),
        std::thread::current().id()
    ));
    let _ = std::fs::remove_dir_all(&path);
    let client = BridgeClient::open(path.to_string_lossy().into_owned()).expect("open client");
    let missing_photo = client
        .prepare_ygdk_submit(BridgeYgdkSubmitRequest {
            target: BridgeYgdkSubmitTarget {
                classify_id: 3,
                item_id: 1,
            },
            start_time: "2026-09-02 08:00".to_owned(),
            end_time: "2026-09-02 09:00".to_owned(),
            place: None,
            share_to_square: false,
            photo: BridgePhotoUpload {
                bytes: Vec::new(),
                file_name: "photo.jpg".to_owned(),
                mime_type: "image/jpeg".to_owned(),
            },
        })
        .await
        .expect_err("invalid Ygdk input must be rejected during prepare");
    assert_eq!(missing_photo.code, BridgeErrorCode::InvalidInput);

    let missing_time = client
        .prepare_ygdk_submit(BridgeYgdkSubmitRequest {
            target: BridgeYgdkSubmitTarget {
                classify_id: 3,
                item_id: 1,
            },
            start_time: String::new(),
            end_time: "2026-09-02 09:00".to_owned(),
            place: None,
            share_to_square: false,
            photo: BridgePhotoUpload {
                bytes: vec![1, 2, 3],
                file_name: "photo.jpg".to_owned(),
                mime_type: "image/jpeg".to_owned(),
            },
        })
        .await
        .expect_err("both Ygdk times must be non-empty during prepare");
    assert_eq!(missing_time.code, BridgeErrorCode::InvalidInput);

    for (start_time, end_time) in [
        ("2026-09-02T08:00", "2026-09-02 09:00"),
        ("2026-09-02 08:00:00", "2026-09-02 09:00"),
        ("2026-09-02 09:00", "2026-09-02 09:00"),
        ("2026-09-02 10:00", "2026-09-02 09:00"),
        ("2026-09-02 23:00", "2026-09-03 00:00"),
    ] {
        let error = client
            .prepare_ygdk_submit(BridgeYgdkSubmitRequest {
                target: BridgeYgdkSubmitTarget {
                    classify_id: 3,
                    item_id: 1,
                },
                start_time: start_time.to_owned(),
                end_time: end_time.to_owned(),
                place: None,
                share_to_square: false,
                photo: BridgePhotoUpload {
                    bytes: vec![1, 2, 3],
                    file_name: "photo.jpg".to_owned(),
                    mime_type: "image/jpeg".to_owned(),
                },
            })
            .await
            .expect_err("非 canonical 时间必须在路线解析和网络前拒绝");
        assert_eq!(error.code, BridgeErrorCode::InvalidInput);
        assert!(error.resolved_route.is_none());
    }

    for (file_name, mime_type) in [
        ("../photo.jpg", "image/jpeg"),
        ("photo\r\n.jpg", "image/jpeg"),
        (" photo.jpg", "image/jpeg"),
        ("photo.jpg ", "image/jpeg"),
        ("photo.jpg", "image/jpeg; charset=utf-8"),
        ("photo.jpg", "application/octet-stream"),
    ] {
        let error = client
            .prepare_ygdk_submit(BridgeYgdkSubmitRequest {
                target: BridgeYgdkSubmitTarget {
                    classify_id: 3,
                    item_id: 1,
                },
                start_time: "2026-09-02 08:00".to_owned(),
                end_time: "2026-09-02 09:00".to_owned(),
                place: None,
                share_to_square: false,
                photo: BridgePhotoUpload {
                    bytes: vec![1, 2, 3],
                    file_name: file_name.to_owned(),
                    mime_type: mime_type.to_owned(),
                },
            })
            .await
            .expect_err("危险 multipart metadata 必须在网络前拒绝");
        assert_eq!(error.code, BridgeErrorCode::InvalidInput);
        assert!(error.resolved_route.is_none());
    }
    assert!(client.write_intents.lock().await.is_empty());
    client.dispose().await.expect("dispose client");
    let _ = std::fs::remove_dir_all(path);
}

#[tokio::test]
async fn cgyy_prepare_rejects_incomplete_request_before_route_resolution() {
    let path = std::env::temp_dir().join(format!(
        "ubaa-bridge-cgyy-input-{}-{:?}",
        std::process::id(),
        std::thread::current().id()
    ));
    let _ = std::fs::remove_dir_all(&path);
    let client = BridgeClient::open(path.to_string_lossy().into_owned()).expect("open client");
    let error = client
        .prepare_cgyy_submit_reservation(BridgeCgyySubmitReservationRequest {
            venue_site_id: 4,
            reservation_date: "2026-09-02".to_owned(),
            selections: Vec::new(),
            phone: "010-00000000".to_owned(),
            theme: "测试预约".to_owned(),
            purpose_type: 0,
            joiner_num: 0,
            activity_content: String::new(),
            joiners: String::new(),
            is_philosophy_social_sciences: false,
            is_off_school_joiner: false,
        })
        .await
        .expect_err("invalid Cgyy input must be rejected during prepare");
    assert_eq!(error.code, BridgeErrorCode::InvalidInput);
    assert!(client.write_intents.lock().await.is_empty());

    let invalid_group = client
        .prepare_cgyy_submit_reservation(BridgeCgyySubmitReservationRequest {
            venue_site_id: 4,
            reservation_date: "2026-09-02".to_owned(),
            selections: vec![BridgeCgyyReservationSelection {
                space_id: 6,
                time_id: 101,
                venue_space_group_id: Some(0),
            }],
            phone: "010-00000000".to_owned(),
            theme: "测试预约".to_owned(),
            purpose_type: 1,
            joiner_num: 1,
            activity_content: "脱敏内容".to_owned(),
            joiners: "脱敏参与者".to_owned(),
            is_philosophy_social_sciences: false,
            is_off_school_joiner: false,
        })
        .await
        .expect_err("非正数空间组必须在路线解析前拒绝");
    assert_eq!(invalid_group.code, BridgeErrorCode::InvalidInput);
    assert!(client.write_intents.lock().await.is_empty());
    client.dispose().await.expect("dispose client");
    let _ = std::fs::remove_dir_all(path);
}
