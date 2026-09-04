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
use super::auth::{code_from_url, ensure_login, percent_decode};
use super::http::{post, post_non_idempotent, post_with_query};
use super::parser::{parse_envelope, parse_items, parse_overview, parse_records};
use super::read::get_records;
use super::upload::{build_upload_body, upload_photo};
use super::write::{normalize_submit_request, parse_submit_result, submit_clockin};

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

mod contract;
mod runtime_guards;
mod value_contracts;
