use super::*;

#[test]
fn intent_id_and_digest_are_stable_shapes_without_payload_leak() {
    let first = random_id();
    let second = random_id();
    assert_eq!(first.len(), 32);
    assert_eq!(second.len(), 32);
    assert_ne!(first, second);
    assert_eq!(digest("course_id=7").len(), 64);
    assert_eq!(digest("course_id=7"), digest("course_id=7"));
}

#[test]
fn write_digest_shapes_do_not_include_sensitive_text_or_photo_bytes() {
    let cgyy = BridgeCgyySubmitReservationRequest {
        venue_site_id: 4,
        reservation_date: "2026-09-02".to_owned(),
        selections: vec![BridgeCgyyReservationSelection {
            space_id: 6,
            time_id: 242,
            venue_space_group_id: None,
        }],
        phone: "phone-secret".to_owned(),
        theme: "theme-secret".to_owned(),
        purpose_type: 1,
        joiner_num: 2,
        activity_content: "activity-secret".to_owned(),
        joiners: "joiner-secret".to_owned(),
        is_philosophy_social_sciences: false,
        is_off_school_joiner: true,
    };
    let cgyy_shape = cgyy_canonical(&cgyy);
    for secret in [
        "phone-secret",
        "theme-secret",
        "activity-secret",
        "joiner-secret",
    ] {
        assert!(!cgyy_shape.contains(secret));
    }
    assert!(cgyy_shape.contains("phone=present:12"));

    let ygdk = BridgeYgdkSubmitRequest {
        item_id: Some(1),
        start_time: Some("2026-09-02 08:00".to_owned()),
        end_time: Some("2026-09-02 09:00".to_owned()),
        place: Some("private-place".to_owned()),
        share_to_square: Some(false),
        photo: Some(BridgePhotoUpload {
            bytes: vec![0xde, 0xad, 0xbe, 0xef],
            file_name: "private-photo.jpg".to_owned(),
            mime_type: "image/jpeg".to_owned(),
        }),
    };
    let ygdk_shape = ygdk_canonical(&ygdk);
    assert!(!ygdk_shape.contains("private-place"));
    assert!(!ygdk_shape.contains("private-photo.jpg"));
    assert!(!ygdk_shape.contains("deadbeef"));
    assert!(ygdk_shape.contains("photo=present:4:image/jpeg"));
}

#[test]
fn session_revision_conflict_maps_to_operation_conflict_at_write_boundary() {
    let error = UbaaError::new(
        ErrorCode::InternalError,
        ErrorKind::Internal,
        false,
        "local session changed in another process",
    );
    let mapped = map_resolution_error(error);
    assert_eq!(mapped.code, BridgeErrorCode::OperationConflict);
}
