use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, AtomicUsize, Ordering},
};

use async_trait::async_trait;

use crate::domain::{
    ActionEligibility, ConnectionMode, YgdkClockinSubmitRequest, YgdkPhotoUpload, YgdkSubmitTarget,
};
use crate::ports::{HttpRequest, HttpResponse, HttpTransport};
use crate::runtime::ClientRuntime;
use crate::session::{FileSessionStore, SessionMutation, SessionSnapshot, SessionStore};

use super::YgdkCredential;
use super::auth::{code_from_url, ensure_login, percent_decode, validate_oauth_target};
use super::http::{post, post_non_idempotent, post_with_query};
use super::parser::{parse_envelope, parse_items, parse_overview, parse_records};
use super::read::get_records;
use super::upload::{build_upload_body, upload_photo};
use super::write::{normalize_submit_request, parse_submit_result, submit_clockin};
use crate::connection::to_webvpn_url;

fn valid_submit_request() -> YgdkClockinSubmitRequest {
    YgdkClockinSubmitRequest {
        target: YgdkSubmitTarget {
            classify_id: 1,
            item_id: 2,
        },
        start_time: "2026-04-01 08:00".into(),
        end_time: "2026-04-01 09:00".into(),
        place: Some("操场".into()),
        share_to_square: false,
        photo: YgdkPhotoUpload {
            file_name: "p.jpg".into(),
            mime_type: "image/jpeg".into(),
            bytes: b"JPEG".to_vec(),
        },
    }
}

#[test]
fn 阳光打卡_oauth只允许已证实主机和安全网关包装() {
    for target in [
        "https://app.buaa.edu.cn/uc/api/oauth/index",
        "https://ygdk.buaa.edu.cn/#/home?code=fixture",
    ] {
        assert!(validate_oauth_target(target, ConnectionMode::Direct).is_ok());
    }
    for target in [
        "https://unknown.example.invalid/callback?code=fixture",
        "http://ygdk.buaa.edu.cn/#/home?code=fixture",
        "ftp://unknown.example.invalid/callback?code=fixture",
        "https://user:pass@unknown.example.invalid/callback?code=fixture",
        "https://unknown.example.invalid:8443/callback?code=fixture",
        "http://d.buaa.edu.cn/callback?code=fixture",
        "https://d.buaa.edu.cn./callback?code=fixture",
    ] {
        assert!(validate_oauth_target(target, ConnectionMode::Direct).is_err());
    }
    let wrapped = to_webvpn_url("https://ygdk.buaa.edu.cn/#/home?code=fixture").unwrap();
    assert!(validate_oauth_target(&wrapped, ConnectionMode::WebVpn).is_ok());
    assert!(validate_oauth_target(&wrapped, ConnectionMode::Direct).is_err());
    for target in [
        "https://evil.example.invalid/",
        "https://ygdk.buaa.edu.cn:8443/",
    ] {
        let wrapped = to_webvpn_url(target).unwrap();
        assert!(validate_oauth_target(&wrapped, ConnectionMode::WebVpn).is_err());
    }
    let wrapped_custom_port = to_webvpn_url("https://unknown.example.invalid:8443/callback")
        .expect("生成带自定义端口的 WebVPN 地址");
    assert!(validate_oauth_target(&wrapped_custom_port, ConnectionMode::WebVpn).is_err());
}

fn save_session(store: &FileSessionStore, snapshot: &SessionSnapshot) -> crate::error::Result<()> {
    loop {
        let current = store.load_versioned()?;
        if matches!(
            store.compare_exchange(current.revision, Some(snapshot))?,
            SessionMutation::Applied { .. }
        ) {
            return Ok(());
        }
    }
}

mod auth_redirects;
mod contract;
mod runtime_guards;
mod value_contracts;
