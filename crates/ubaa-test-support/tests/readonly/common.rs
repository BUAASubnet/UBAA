use std::collections::{BTreeMap, VecDeque};
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use ubaa_core::facade::testing::{
    HttpMethod, HttpRequest, HttpResponse, HttpTransport, SessionSnapshot, SessionStore,
    StoredCookie,
};
use ubaa_core::facade::{ConnectionMode, Result};
use ubaa_test_support::{ExpectedRequest, MemorySessionStore};
#[derive(Clone)]
pub(crate) struct SpocTransport {
    responses: Arc<Mutex<VecDeque<(String, HttpResponse)>>>,
    requests: Arc<Mutex<Vec<HttpRequest>>>,
}

impl SpocTransport {
    pub(crate) fn new(responses: impl IntoIterator<Item = (String, HttpResponse)>) -> Self {
        Self {
            responses: Arc::new(Mutex::new(responses.into_iter().collect())),
            requests: Arc::new(Mutex::new(Vec::new())),
        }
    }

    pub(crate) fn requests(&self) -> Vec<HttpRequest> {
        self.requests.lock().expect("request log lock").clone()
    }

    pub(crate) fn assert_exhausted(&self) {
        assert!(
            self.responses
                .lock()
                .expect("response script lock")
                .is_empty(),
            "SPOC response script has unused entries"
        );
    }
}

#[async_trait]
impl HttpTransport for SpocTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let (expected_url, response) = self
            .responses
            .lock()
            .expect("response script lock")
            .pop_front()
            .expect("SPOC request script exhausted");
        assert_eq!(request.url, expected_url);
        self.requests
            .lock()
            .expect("request log lock")
            .push(request);
        Ok(response)
    }
}

pub(crate) fn response(status: u16, final_url: &str, body: &str) -> HttpResponse {
    HttpResponse {
        status,
        final_url: final_url.into(),
        headers: BTreeMap::new(),
        body: body.as_bytes().to_vec(),
    }
}

pub(crate) fn redirect(location: &str) -> HttpResponse {
    redirect_from("https://spoc.buaa.edu.cn/spocnewht/cas", location)
}

pub(crate) fn redirect_from(current: &str, location: &str) -> HttpResponse {
    let mut headers = BTreeMap::new();
    headers.insert("Location".into(), vec![location.into()]);
    HttpResponse {
        status: 302,
        final_url: current.into(),
        headers,
        body: Vec::new(),
    }
}

pub(crate) fn session_store() -> MemorySessionStore {
    session_store_with("fixture")
}

pub(crate) fn session_store_with(cookie_value: &str) -> MemorySessionStore {
    session_store_for(ConnectionMode::Direct, cookie_value)
}

pub(crate) fn session_store_for(mode: ConnectionMode, cookie_value: &str) -> MemorySessionStore {
    let store = MemorySessionStore::new();
    store
        .save(&SessionSnapshot {
            mode,
            cookies: vec![StoredCookie::fixture("SID", cookie_value)],
            authenticated_at: 1,
            last_activity: 2,
        })
        .expect("seed session");
    store
}

pub(crate) fn expected_get(url: &str, body: &str) -> ExpectedRequest {
    ExpectedRequest::new(HttpMethod::Get, url, response(200, url, body))
}
