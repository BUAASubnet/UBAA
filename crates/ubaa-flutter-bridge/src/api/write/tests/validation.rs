use super::*;

#[tokio::test]
async fn ygdk_prepare_rejects_missing_photo_and_time_before_storing_intent() {
    let path = std::env::temp_dir().join(format!(
        "ubaa-bridge-ygdk-input-{}-{:?}",
        std::process::id(),
        std::thread::current().id()
    ));
    let _ = std::fs::remove_dir_all(&path);
    let client = BridgeClient::open(path.to_string_lossy().into_owned()).expect("open client");
    let missing_photo = client
        .prepare_ygdk_submit(BridgeYgdkSubmitRequest {
            item_id: Some(1),
            start_time: Some("08:00".to_owned()),
            end_time: Some("09:00".to_owned()),
            place: None,
            share_to_square: Some(false),
            photo: Some(BridgePhotoUpload {
                bytes: Vec::new(),
                file_name: "photo.jpg".to_owned(),
                mime_type: "image/jpeg".to_owned(),
            }),
        })
        .await
        .expect_err("invalid Ygdk input must be rejected during prepare");
    assert_eq!(missing_photo.code, BridgeErrorCode::InvalidInput);

    let missing_time = client
        .prepare_ygdk_submit(BridgeYgdkSubmitRequest {
            item_id: Some(1),
            start_time: None,
            end_time: Some("09:00".to_owned()),
            place: None,
            share_to_square: Some(false),
            photo: Some(BridgePhotoUpload {
                bytes: vec![1, 2, 3],
                file_name: "photo.jpg".to_owned(),
                mime_type: "image/jpeg".to_owned(),
            }),
        })
        .await
        .expect_err("both Ygdk times must be supplied during prepare");
    assert_eq!(missing_time.code, BridgeErrorCode::InvalidInput);
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
    client.dispose().await.expect("dispose client");
    let _ = std::fs::remove_dir_all(path);
}
