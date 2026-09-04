use std::future::Future;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::task::{Context, Poll};
use std::time::Duration;

use super::support::{
    bykc_sign_canonical, cgyy_canonical, digest, map_commit_error, map_resolution_error, random_id,
    safe_summary_label, ygdk_canonical,
};
use super::{
    BridgeBykcCourseRequest, BridgeBykcSignCourseRequest, BridgeCgyyReservationSelection,
    BridgeCgyySubmitReservationRequest, BridgePhotoUpload, BridgeWriteOperation,
    BridgeYgdkSubmitRequest, PendingEntry, PendingWrite,
};
use crate::api::client::{BridgeClient, BridgeConnectionMode, BridgeErrorCode, BridgeErrorKind};
use ubaa_core::facade::testing::{
    DualSessionSnapshot, FileSessionStore, GatewayProbe, HttpMethod, HttpResponse, RouteConfig,
    RouteSessionSnapshot,
};
use ubaa_core::facade::{ErrorCode, ErrorKind, NetworkState, RoutedError, UbaaClient, UbaaError};
use ubaa_test_support::{ExpectedRequest, MockTransport};

mod bykc;
mod contract;
mod libbook;
mod lifecycle;
mod signin;
mod validation;

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

fn summarized_selectable_bykc_detail_request() -> ExpectedRequest {
    let url = "https://bykc.buaa.edu.cn/sscv/queryCourseById";
    ExpectedRequest::new(
        HttpMethod::Post,
        url,
        HttpResponse::new(
            200,
            url,
            r#"{"status":"0","data":{"id":42,"courseName":"安全\n课程\u0000","courseStartDate":"2999-01-01 08:00:00","courseSelectStartDate":"2000-01-01 00:00:00","courseSelectEndDate":"2998-12-31 23:59:59","courseMaxCount":10,"courseCurrentCount":0,"selected":false}}"#
                .as_bytes()
                .to_vec(),
        ),
    )
}

fn summarized_deselectable_bykc_detail_request() -> ExpectedRequest {
    let url = "https://bykc.buaa.edu.cn/sscv/queryCourseById";
    ExpectedRequest::new(
        HttpMethod::Post,
        url,
        HttpResponse::new(
            200,
            url,
            r#"{"status":"0","data":{"id":42,"courseName":"已选\n课程\u0000","courseStartDate":"2999-01-01 08:00:00","courseCancelEndDate":"2998-11-30 23:59:59","selected":true}}"#
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

fn bykc_all_config_request() -> ExpectedRequest {
    let url = "https://bykc.buaa.edu.cn/sscv/getAllConfig";
    ExpectedRequest::new(
        HttpMethod::Post,
        url,
        HttpResponse::new(
            200,
            url,
            br#"{"status":"0","data":{"semester":[{"semesterStartDate":"2000-01-01 00:00:00","semesterEndDate":"2999-12-31 23:59:59"}]}}"#.to_vec(),
        ),
    )
}

fn signable_bykc_chosen_request() -> ExpectedRequest {
    bykc_chosen_sign_request(
        r#"{"status":"0","data":{"courseList":[{"id":9,"checkin":0,"pass":0,"courseInfo":{"id":42,"courseName":"脱敏资格课程","courseSignConfig":"{\"signStartDate\":\"2000-01-01 00:00:00\",\"signEndDate\":\"2999-12-31 23:59:59\",\"signOutStartDate\":\"2000-01-01 00:00:00\",\"signOutEndDate\":\"2999-12-31 23:59:59\",\"signPointList\":[{\"lat\":39.9,\"lng\":116.3,\"radius\":100.0}]}"}}]}}"#,
    )
}

fn denied_bykc_chosen_sign_request() -> ExpectedRequest {
    bykc_chosen_sign_request(
        r#"{"status":"0","data":{"courseList":[{"id":9,"checkin":1,"pass":0,"courseInfo":{"id":42,"courseName":"脱敏资格课程","courseSignConfig":"{\"signStartDate\":\"2000-01-01 00:00:00\",\"signEndDate\":\"2999-12-31 23:59:59\",\"signOutStartDate\":\"2000-01-01 00:00:00\",\"signOutEndDate\":\"2999-12-31 23:59:59\",\"signPointList\":[{\"lat\":39.9,\"lng\":116.3,\"radius\":100.0}]}"}}]}}"#,
    )
}

fn unknown_bykc_chosen_sign_request() -> ExpectedRequest {
    bykc_chosen_sign_request(
        r#"{"status":"0","data":{"courseList":[{"id":9,"checkin":0,"courseInfo":{"id":42,"courseName":"脱敏资格课程","courseSignConfig":"{\"signStartDate\":\"2000-01-01 00:00:00\",\"signEndDate\":\"2999-12-31 23:59:59\",\"signOutStartDate\":\"2000-01-01 00:00:00\",\"signOutEndDate\":\"2999-12-31 23:59:59\",\"signPointList\":[{\"lat\":39.9,\"lng\":116.3,\"radius\":100.0}]}"}}]}}"#,
    )
}

fn bykc_chosen_sign_request(body: &'static str) -> ExpectedRequest {
    let url = "https://bykc.buaa.edu.cn/sscv/queryChosenCourse";
    ExpectedRequest::new(
        HttpMethod::Post,
        url,
        HttpResponse::new(200, url, body.as_bytes().to_vec()),
    )
}

fn bykc_sign_write_request(status: u16, body: &'static str) -> ExpectedRequest {
    let url = "https://bykc.buaa.edu.cn/sscv/signCourseByUser";
    ExpectedRequest::new(
        HttpMethod::Post,
        url,
        HttpResponse::new(status, url, body.as_bytes().to_vec()),
    )
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
