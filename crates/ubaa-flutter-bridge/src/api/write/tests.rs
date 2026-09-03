use std::future::Future;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::task::{Context, Poll};
use std::time::Duration;

use super::{
    BridgeBykcCourseRequest, BridgeCgyyReservationSelection, BridgeCgyySubmitReservationRequest,
    BridgePhotoUpload, BridgeWriteOperation, BridgeYgdkSubmitRequest, PendingEntry, PendingWrite,
    cgyy_canonical, digest, map_resolution_error, random_id, ygdk_canonical,
};
use crate::api::client::{BridgeClient, BridgeConnectionMode, BridgeErrorCode};
use ubaa_core::facade::testing::{
    DualSessionSnapshot, FileSessionStore, GatewayProbe, HttpMethod, HttpResponse, RouteConfig,
    RouteSessionSnapshot,
};
use ubaa_core::facade::{ErrorCode, ErrorKind, NetworkState, UbaaClient, UbaaError};
use ubaa_test_support::{ExpectedRequest, MockTransport};

fn bykc_login_request() -> ExpectedRequest {
    let url = "https://bykc.buaa.edu.cn/sscv/cas/login";
    ExpectedRequest::new(
        HttpMethod::Get,
        url,
        HttpResponse::new(302, format!("{url}?token=token-safe"), Vec::new()),
    )
}

fn eligible_bykc_detail_request() -> ExpectedRequest {
    let url = "https://bykc.buaa.edu.cn/sscv/queryCourseById";
    ExpectedRequest::new(
        HttpMethod::Post,
        url,
        HttpResponse::new(
            200,
            url,
            r#"{"status":"0","data":{"id":42,"courseName":"可选课程","courseStartDate":"2999-01-01 08:00:00","courseSelectStartDate":"2000-01-01 00:00:00","courseSelectEndDate":"2998-12-31 23:59:59","courseMaxCount":10,"courseCurrentCount":0,"selected":false}}"#
                .as_bytes()
                .to_vec(),
        ),
    )
}

fn incomplete_bykc_detail_request() -> ExpectedRequest {
    let url = "https://bykc.buaa.edu.cn/sscv/queryCourseById";
    ExpectedRequest::new(
        HttpMethod::Post,
        url,
        HttpResponse::new(
            200,
            url,
            r#"{"status":"0","data":{"id":42,"courseName":"字段不完整的课程"}}"#
                .as_bytes()
                .to_vec(),
        ),
    )
}

fn mismatched_bykc_detail_request() -> ExpectedRequest {
    let url = "https://bykc.buaa.edu.cn/sscv/queryCourseById";
    ExpectedRequest::new(
        HttpMethod::Post,
        url,
        HttpResponse::new(
            200,
            url,
            r#"{"status":"0","data":{"id":99,"courseName":"错误课程","courseStartDate":"2999-01-01 08:00:00","courseSelectStartDate":"2000-01-01 00:00:00","courseSelectEndDate":"2998-12-31 23:59:59","courseMaxCount":10,"courseCurrentCount":0,"selected":false}}"#
                .as_bytes()
                .to_vec(),
        ),
    )
}

fn denied_bykc_detail_request() -> ExpectedRequest {
    let url = "https://bykc.buaa.edu.cn/sscv/queryCourseById";
    ExpectedRequest::new(
        HttpMethod::Post,
        url,
        HttpResponse::new(
            200,
            url,
            r#"{"status":"0","data":{"id":42,"courseName":"已选课程","courseStartDate":"2999-01-01 08:00:00","courseSelectStartDate":"2000-01-01 00:00:00","courseSelectEndDate":"2998-12-31 23:59:59","courseMaxCount":10,"courseCurrentCount":1,"selected":true}}"#
                .as_bytes()
                .to_vec(),
        ),
    )
}

fn deselectable_bykc_detail_request() -> ExpectedRequest {
    let url = "https://bykc.buaa.edu.cn/sscv/queryCourseById";
    ExpectedRequest::new(
        HttpMethod::Post,
        url,
        HttpResponse::new(
            200,
            url,
            r#"{"status":"0","data":{"id":42,"courseName":"已选课程","courseStartDate":"2999-01-01 08:00:00","selected":true}}"#
                .as_bytes()
                .to_vec(),
        ),
    )
}

fn unknown_deselect_bykc_detail_request() -> ExpectedRequest {
    let url = "https://bykc.buaa.edu.cn/sscv/queryCourseById";
    ExpectedRequest::new(
        HttpMethod::Post,
        url,
        HttpResponse::new(
            200,
            url,
            r#"{"status":"0","data":{"id":42,"courseName":"缺少开课时间","selected":true}}"#
                .as_bytes()
                .to_vec(),
        ),
    )
}

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

#[tokio::test]
async fn 有效准备先复核资格且提交只命中已解析路线() {
    let root = test_root("prepare-commit-route");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let select_url = "https://bykc.buaa.edu.cn/sscv/choseCourse";
    let direct = MockTransport::new([
        bykc_login_request(),
        eligible_bykc_detail_request(),
        eligible_bykc_detail_request(),
        ExpectedRequest::new(
            HttpMethod::Post,
            select_url,
            HttpResponse::new(
                200,
                select_url,
                br#"{"status":"0","data":{"message":"ok"}}"#.to_vec(),
            ),
        ),
    ]);
    let webvpn = MockTransport::new([]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        webvpn.clone(),
    )
    .await;

    let intent = client
        .prepare_bykc_select_course(BridgeBykcCourseRequest { course_id: 42 })
        .await
        .expect("准备写入");
    assert!(matches!(
        intent.operation,
        BridgeWriteOperation::BykcSelectCourse
    ));
    assert_eq!(intent.resolved_route, BridgeConnectionMode::Direct);
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 2);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());

    let result = client
        .commit_write(intent.intent_id.clone())
        .await
        .expect("提交写入");
    assert!(result.success);
    assert!(!result.outcome_unknown);
    assert!(matches!(
        result.operation,
        BridgeWriteOperation::BykcSelectCourse
    ));
    assert_eq!(result.resolved_route, Some(BridgeConnectionMode::Direct));
    direct.assert_exhausted().expect("Direct 脚本必须全部消费");
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 4);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());

    let reused = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("同一 intent 不得重复提交");
    assert_eq!(reused.code, BridgeErrorCode::IntentExpired);
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 4);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 详情标识错配时准备拒绝且不签发意图() {
    let root = test_root("mismatched-bykc-course-id");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([bykc_login_request(), mismatched_bykc_detail_request()]);
    let webvpn = MockTransport::new([]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        webvpn.clone(),
    )
    .await;

    let error = client
        .prepare_bykc_select_course(BridgeBykcCourseRequest { course_id: 42 })
        .await
        .expect_err("错配详情不得准备选课");

    assert_eq!(error.code, BridgeErrorCode::UpstreamChanged);
    assert!(client.write_intents.lock().await.is_empty());
    direct.assert_exhausted().expect("只允许读取错配详情");
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 2);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 提交前资格变化时消费意图且不发送选课写请求() {
    let root = test_root("changed-bykc-eligibility");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        bykc_login_request(),
        eligible_bykc_detail_request(),
        denied_bykc_detail_request(),
    ]);
    let webvpn = MockTransport::new([]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        webvpn.clone(),
    )
    .await;

    let intent = client
        .prepare_bykc_select_course(BridgeBykcCourseRequest { course_id: 42 })
        .await
        .expect("准备写入");
    let error = client
        .commit_write(intent.intent_id.clone())
        .await
        .expect_err("资格变化后不得提交选课");

    assert_eq!(error.code, BridgeErrorCode::OperationConflict);
    assert!(error.retryable);
    direct.assert_exhausted().expect("不得发送选课写请求");
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 3);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());

    let reused = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("资格冲突后的 intent 已消费");
    assert_eq!(reused.code, BridgeErrorCode::IntentExpired);
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 3);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 提交前详情标识错配时消费意图且不发送选课写请求() {
    let root = test_root("mismatched-bykc-course-id-on-commit");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        bykc_login_request(),
        eligible_bykc_detail_request(),
        mismatched_bykc_detail_request(),
    ]);
    let webvpn = MockTransport::new([]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        webvpn.clone(),
    )
    .await;

    let intent = client
        .prepare_bykc_select_course(BridgeBykcCourseRequest { course_id: 42 })
        .await
        .expect("准备写入");
    let error = client
        .commit_write(intent.intent_id.clone())
        .await
        .expect_err("错配详情不得通过提交前复核");

    assert_eq!(error.code, BridgeErrorCode::UpstreamChanged);
    assert!(!error.retryable);
    direct.assert_exhausted().expect("不得发送选课写请求");
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 3);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());

    let reused = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("详情错配后的 intent 已消费");
    assert_eq!(reused.code, BridgeErrorCode::IntentExpired);
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 3);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 资格未知时准备拒绝且不签发意图() {
    let root = test_root("unknown-bykc-eligibility");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([bykc_login_request(), incomplete_bykc_detail_request()]);
    let webvpn = MockTransport::new([]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        webvpn.clone(),
    )
    .await;

    let error = client
        .prepare_bykc_select_course(BridgeBykcCourseRequest { course_id: 42 })
        .await
        .expect_err("资格未知时不得准备选课");

    assert_eq!(error.code, BridgeErrorCode::UpstreamChanged);
    assert!(client.write_intents.lock().await.is_empty());
    direct.assert_exhausted().expect("只允许资格预检请求");
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 2);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 退选资格未知时准备拒绝且不签发意图() {
    let root = test_root("unknown-bykc-deselect-eligibility");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([bykc_login_request(), unknown_deselect_bykc_detail_request()]);
    let webvpn = MockTransport::new([]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        webvpn.clone(),
    )
    .await;

    let error = client
        .prepare_bykc_deselect_course(BridgeBykcCourseRequest { course_id: 42 })
        .await
        .expect_err("资格未知时不得准备退选");

    assert_eq!(error.code, BridgeErrorCode::UpstreamChanged);
    assert!(client.write_intents.lock().await.is_empty());
    direct.assert_exhausted().expect("只允许资格预检请求");
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 2);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 退选详情标识错配时准备拒绝且不签发意图() {
    let root = test_root("mismatched-bykc-deselect-id");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([bykc_login_request(), mismatched_bykc_detail_request()]);
    let webvpn = MockTransport::new([]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        webvpn.clone(),
    )
    .await;

    let error = client
        .prepare_bykc_deselect_course(BridgeBykcCourseRequest { course_id: 42 })
        .await
        .expect_err("错配详情不得准备退选");

    assert_eq!(error.code, BridgeErrorCode::UpstreamChanged);
    assert!(client.write_intents.lock().await.is_empty());
    direct.assert_exhausted().expect("只允许读取错配详情");
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 2);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 有效退选在准备和提交时复核且只命中已解析路线() {
    let root = test_root("prepare-commit-bykc-deselect");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let deselect_url = "https://bykc.buaa.edu.cn/sscv/delChosenCourse";
    let direct = MockTransport::new([
        bykc_login_request(),
        deselectable_bykc_detail_request(),
        deselectable_bykc_detail_request(),
        ExpectedRequest::new(
            HttpMethod::Post,
            deselect_url,
            HttpResponse::new(
                200,
                deselect_url,
                br#"{"status":"0","data":{"message":"ok"}}"#.to_vec(),
            ),
        ),
    ]);
    let webvpn = MockTransport::new([]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        webvpn.clone(),
    )
    .await;

    let intent = client
        .prepare_bykc_deselect_course(BridgeBykcCourseRequest { course_id: 42 })
        .await
        .expect("准备退选");
    assert_eq!(intent.resolved_route, BridgeConnectionMode::Direct);
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 2);

    let result = client
        .commit_write(intent.intent_id)
        .await
        .expect("提交退选");
    assert!(result.success);
    assert!(matches!(
        result.operation,
        BridgeWriteOperation::BykcDeselectCourse
    ));
    assert_eq!(result.resolved_route, Some(BridgeConnectionMode::Direct));
    direct.assert_exhausted().expect("Direct 脚本必须全部消费");
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 4);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 提交前已退选时消费意图且不发送退选写请求() {
    let root = test_root("changed-bykc-deselect-eligibility");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        bykc_login_request(),
        deselectable_bykc_detail_request(),
        eligible_bykc_detail_request(),
    ]);
    let webvpn = MockTransport::new([]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        webvpn.clone(),
    )
    .await;

    let intent = client
        .prepare_bykc_deselect_course(BridgeBykcCourseRequest { course_id: 42 })
        .await
        .expect("准备退选");
    let error = client
        .commit_write(intent.intent_id.clone())
        .await
        .expect_err("已退选后不得再次提交");

    assert_eq!(error.code, BridgeErrorCode::OperationConflict);
    assert!(error.retryable);
    direct.assert_exhausted().expect("不得发送退选写请求");
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 3);
    let reused = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("资格冲突后的 intent 已消费");
    assert_eq!(reused.code, BridgeErrorCode::IntentExpired);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 提交前退选详情标识错配时消费意图且不发送写请求() {
    let root = test_root("mismatched-bykc-deselect-id-on-commit");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        bykc_login_request(),
        deselectable_bykc_detail_request(),
        mismatched_bykc_detail_request(),
    ]);
    let webvpn = MockTransport::new([]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        webvpn.clone(),
    )
    .await;

    let intent = client
        .prepare_bykc_deselect_course(BridgeBykcCourseRequest { course_id: 42 })
        .await
        .expect("准备退选");
    let error = client
        .commit_write(intent.intent_id.clone())
        .await
        .expect_err("错配详情不得通过提交前复核");

    assert_eq!(error.code, BridgeErrorCode::UpstreamChanged);
    assert!(!error.retryable);
    direct.assert_exhausted().expect("不得发送退选写请求");
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 3);
    let reused = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("详情错配后的 intent 已消费");
    assert_eq!(reused.code, BridgeErrorCode::IntentExpired);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 准备后路线变化在无新增请求下消费意图() {
    let root = test_root("route-change");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, true);
    let direct = MockTransport::new([bykc_login_request(), eligible_bykc_detail_request()]);
    let webvpn = MockTransport::new([]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store.clone(),
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        webvpn.clone(),
    )
    .await;
    let intent = client
        .prepare_bykc_select_course(BridgeBykcCourseRequest { course_id: 42 })
        .await
        .expect("准备 Direct 写入");
    assert_eq!(intent.resolved_route, BridgeConnectionMode::Direct);
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 2);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());

    install_core(
        &client,
        store,
        "[route]\ndefault = \"webvpn\"\n",
        direct.clone(),
        webvpn.clone(),
    )
    .await;
    let conflict = client
        .commit_write(intent.intent_id.clone())
        .await
        .expect_err("路线变化必须拒绝旧 intent");
    assert_eq!(conflict.code, BridgeErrorCode::OperationConflict);
    assert!(conflict.retryable);
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 2);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());

    let reused = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("冲突后的 intent 已消费");
    assert_eq!(reused.code, BridgeErrorCode::IntentExpired);
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 2);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 准备后会话修订过期在无新增请求下归约为操作冲突() {
    let root = test_root("stale-session");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([bykc_login_request(), eligible_bykc_detail_request()]);
    let webvpn = MockTransport::new([]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store.clone(),
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        webvpn.clone(),
    )
    .await;
    let intent = client
        .prepare_bykc_select_course(BridgeBykcCourseRequest { course_id: 42 })
        .await
        .expect("准备写入");
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 2);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());

    store
        .save_dual(&DualSessionSnapshot::new(Some(ready_slot(2_002)), None))
        .expect("推进外部会话修订");
    let conflict = client
        .commit_write(intent.intent_id.clone())
        .await
        .expect_err("过期会话必须拒绝旧 intent");
    assert_eq!(conflict.code, BridgeErrorCode::OperationConflict);
    assert!(conflict.retryable);
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 2);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());

    let reused = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("冲突后的 intent 已消费");
    assert_eq!(reused.code, BridgeErrorCode::IntentExpired);
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 2);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 重新登录在提交等待_core_锁时仍能失效旧意图() {
    let root = test_root("intent-lock-order");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([bykc_login_request(), eligible_bykc_detail_request()]);
    let webvpn = MockTransport::new([]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        webvpn.clone(),
    )
    .await;
    let intent = client
        .prepare_bykc_select_course(BridgeBykcCourseRequest { course_id: 42 })
        .await
        .expect("准备写入");

    let inner_guard = client.inner.lock().await;
    let mut commit = Box::pin(client.commit_write(intent.intent_id.clone()));
    let waker = futures_util::task::noop_waker();
    let mut context = Context::from_waker(&waker);
    assert!(matches!(commit.as_mut().poll(&mut context), Poll::Pending));

    // 模拟重新登录/路线重开在同一 Core 锁内使全部旧意图失效。
    client.write_intents.lock().await.clear();
    drop(inner_guard);

    let error = commit.await.expect_err("被并发失效的旧意图不得继续提交");
    assert_eq!(error.code, BridgeErrorCode::IntentExpired);
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 2);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn unknown_or_reused_intent_is_rejected_before_network() {
    let path = std::env::temp_dir().join(format!("ubaa-bridge-write-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&path);
    let client = BridgeClient::open(path.to_string_lossy().into_owned()).expect("open client");
    let error = client
        .commit_write("missing-intent".to_owned())
        .await
        .expect_err("missing intent");
    assert_eq!(error.code, BridgeErrorCode::IntentExpired);
    let _ = std::fs::remove_dir_all(path);
}

#[tokio::test]
async fn expired_intent_is_consumed_and_cannot_be_retried() {
    let path = std::env::temp_dir().join(format!(
        "ubaa-bridge-expired-intent-{}-{:?}",
        std::process::id(),
        std::thread::current().id()
    ));
    let _ = std::fs::remove_dir_all(&path);
    let client = BridgeClient::open(path.to_string_lossy().into_owned()).expect("open client");
    client.write_intents.lock().await.insert(
        "expired".to_owned(),
        PendingEntry {
            request: PendingWrite::BykcSelect(BridgeBykcCourseRequest { course_id: 1 }),
            expires_at: 0,
            resolved_route: BridgeConnectionMode::Direct,
        },
    );
    let first = client
        .commit_write("expired".to_owned())
        .await
        .expect_err("expired intent");
    assert_eq!(first.code, BridgeErrorCode::IntentExpired);
    let second = client
        .commit_write("expired".to_owned())
        .await
        .expect_err("consumed intent cannot be retried");
    assert_eq!(second.code, BridgeErrorCode::IntentExpired);
    client.dispose().await.expect("dispose client");
    let _ = std::fs::remove_dir_all(path);
}

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

async fn install_core(
    bridge: &BridgeClient,
    store: FileSessionStore,
    config: &str,
    direct: MockTransport,
    webvpn: MockTransport,
) {
    let core = UbaaClient::with_routing(
        direct,
        webvpn,
        store,
        RouteConfig::parse(config).expect("解析测试路线配置"),
        NeverProbe,
    )
    .expect("创建测试 Core client");
    *bridge.inner.lock().await = Some(core);
}

fn seed_sessions(root: &Path, direct: bool, webvpn: bool) -> FileSessionStore {
    let store = FileSessionStore::new(root).expect("创建测试会话存储");
    store
        .save_dual(&DualSessionSnapshot::new(
            direct.then(|| ready_slot(1_001)),
            webvpn.then(|| ready_slot(1_001)),
        ))
        .expect("保存测试会话");
    store
}

fn ready_slot(last_activity: i64) -> RouteSessionSnapshot {
    RouteSessionSnapshot {
        cookies: Vec::new(),
        authenticated_at: 1_000,
        last_activity,
    }
}

struct NeverProbe;

impl GatewayProbe for NeverProbe {
    fn probe(&self, _budget: Duration) -> NetworkState {
        panic!("固定路线不得执行网关探测")
    }
}

fn test_root(label: &str) -> PathBuf {
    static NEXT_TEST_ROOT: AtomicU64 = AtomicU64::new(0);
    std::env::temp_dir().join(format!(
        "ubaa-bridge-write-{label}-{}-{}",
        std::process::id(),
        NEXT_TEST_ROOT.fetch_add(1, Ordering::Relaxed)
    ))
}
