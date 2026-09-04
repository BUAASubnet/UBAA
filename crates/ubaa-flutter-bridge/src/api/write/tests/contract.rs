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
    let bykc = BridgeBykcSignCourseRequest {
        course_id: 7,
        lat: Some(39.990_123),
        lng: Some(116.310_456),
        sign_type: 1,
    };
    let bykc_shape = bykc_sign_canonical(&bykc);
    assert_eq!(bykc_shape, "course_id=7;coordinates=present;sign_type=1");
    assert!(!bykc_shape.contains("39.990123"));
    assert!(!bykc_shape.contains("116.310456"));

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
fn 确认摘要移除双向控制零宽与行分隔字符() {
    let value = safe_summary_label(
        "座\u{202e}位\u{2066}A\u{200b}-01\u{2028}完成\u{feff}",
        "未知座位",
    );

    assert_eq!(value, "座位A-01完成");
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

#[test]
fn 博雅签到提交错误按写请求是否已发送区分() {
    let preflight_timeout = map_commit_error(
        BridgeWriteOperation::BykcSignCourse,
        RoutedError {
            error: UbaaError::new(
                ErrorCode::Timeout,
                ErrorKind::Network,
                true,
                "fixture preflight timeout",
            ),
            resolution: None,
        },
    );
    assert_eq!(preflight_timeout.code, BridgeErrorCode::Timeout);

    let preflight_unavailable = map_commit_error(
        BridgeWriteOperation::BykcSignCourse,
        RoutedError {
            error: UbaaError::new(
                ErrorCode::UpstreamUnavailable,
                ErrorKind::Upstream,
                true,
                "fixture preflight unavailable",
            ),
            resolution: None,
        },
    );
    assert_eq!(
        preflight_unavailable.code,
        BridgeErrorCode::UpstreamUnavailable
    );

    let sent_but_unknown = map_commit_error(
        BridgeWriteOperation::BykcSignCourse,
        RoutedError {
            error: UbaaError::new(
                ErrorCode::OutcomeUnknown,
                ErrorKind::Upstream,
                true,
                "fixture write outcome unknown",
            ),
            resolution: None,
        },
    );
    assert_eq!(sent_but_unknown.code, BridgeErrorCode::OutcomeUnknown);
    assert!(!sent_but_unknown.retryable);

    let session_changed = map_commit_error(
        BridgeWriteOperation::BykcSignCourse,
        RoutedError {
            error: UbaaError::new(
                ErrorCode::InternalError,
                ErrorKind::Internal,
                false,
                "local session changed in another process",
            ),
            resolution: None,
        },
    );
    assert_eq!(session_changed.code, BridgeErrorCode::OperationConflict);
}

#[test]
fn 课堂签到提交只信任_core_的显式发送边界分类() {
    let pre_send = map_commit_error(
        BridgeWriteOperation::SigninPerform,
        RoutedError {
            error: UbaaError::new(
                ErrorCode::NetworkError,
                ErrorKind::Network,
                true,
                "fixture preflight network error",
            ),
            resolution: None,
        },
    );
    assert_eq!(pre_send.code, BridgeErrorCode::NetworkError);
    assert!(pre_send.retryable);

    let post_send = map_commit_error(
        BridgeWriteOperation::SigninPerform,
        RoutedError {
            error: UbaaError::new(
                ErrorCode::OutcomeUnknown,
                ErrorKind::Upstream,
                false,
                "fixture outcome unknown",
            ),
            resolution: None,
        },
    );
    assert_eq!(post_send.code, BridgeErrorCode::OutcomeUnknown);
    assert!(!post_send.retryable);
}

#[test]
fn 图书馆预约提交只信任_core_的显式发送边界分类() {
    let pre_send = map_commit_error(
        BridgeWriteOperation::LibbookReserve,
        RoutedError {
            error: UbaaError::new(
                ErrorCode::NetworkError,
                ErrorKind::Network,
                true,
                "fixture preflight network error",
            ),
            resolution: None,
        },
    );
    assert_eq!(pre_send.code, BridgeErrorCode::NetworkError);
    assert!(pre_send.retryable);

    let eligibility_drift = map_commit_error(
        BridgeWriteOperation::LibbookReserve,
        RoutedError {
            error: UbaaError::new(
                ErrorCode::InvalidInput,
                ErrorKind::Input,
                true,
                "fixture libbook eligibility changed",
            ),
            resolution: None,
        },
    );
    assert_eq!(eligibility_drift.code, BridgeErrorCode::OperationConflict);
    assert!(eligibility_drift.retryable);

    let post_send = map_commit_error(
        BridgeWriteOperation::LibbookReserve,
        RoutedError {
            error: UbaaError::new(
                ErrorCode::OutcomeUnknown,
                ErrorKind::Upstream,
                false,
                "fixture libbook outcome unknown",
            ),
            resolution: None,
        },
    );
    assert_eq!(post_send.code, BridgeErrorCode::OutcomeUnknown);
    assert_eq!(post_send.kind, BridgeErrorKind::Upstream);
    assert!(!post_send.retryable);
    assert_eq!(post_send.message, "fixture libbook outcome unknown");
}
