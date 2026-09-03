use std::collections::BTreeMap;

use ubaa_core::facade::testing::{
    HttpMethod, HttpResponse, SessionSnapshot, SessionStore, StoredCookie,
};
use ubaa_core::facade::{ConnectionMode, LoginInput, SecretValue};
use ubaa_test_support::{ExpectedRequest, MemorySessionStore, MockTransport, auth_fixture};

pub(crate) fn response(status: u16, url: &str, body: impl Into<Vec<u8>>) -> HttpResponse {
    HttpResponse::new(status, url, body.into())
}

pub(crate) fn redirect(url: &str, location: &str) -> HttpResponse {
    let mut headers = BTreeMap::new();
    headers.insert("Location".into(), vec![location.into()]);
    HttpResponse {
        status: 302,
        final_url: url.into(),
        headers,
        body: Vec::new(),
    }
}

pub(crate) fn set_cookie(mut response: HttpResponse, cookie: &str) -> HttpResponse {
    response
        .headers
        .insert("Set-Cookie".into(), vec![cookie.into()]);
    response
}

pub(crate) fn login_input() -> LoginInput {
    LoginInput {
        username: "fixture-user".into(),
        password: SecretValue::new("fixture-password"),
    }
}

pub(crate) fn login_page() -> String {
    r#"
    <html><body><form id="fm1" action="/login" method="post">
      <input type="hidden" name="execution" value="e1s1-fixture">
      <input type="hidden" name="lt" value="lt-fixture">
      <input type="text" name="username">
      <input type="password" name="password">
      <input type="checkbox" name="remember" value="yes" checked>
      <input type="submit" name="submit" value="Log in">
      <input type="image" name="ignored-image" value="ignored">
    </form></body></html>
    "#
    .into()
}

pub(crate) fn basic_direct_transport() -> (MockTransport, MemorySessionStore) {
    let login = "https://sso.buaa.edu.cn/login";
    let landing = "https://uc.buaa.edu.cn/landing";
    let activate =
        "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin";
    let status = "https://uc.buaa.edu.cn/api/uc/status";
    let userinfo = "https://uc.buaa.edu.cn/api/uc/userinfo";
    let fixture = auth_fixture("userinfo-success.json").unwrap();
    let transport = MockTransport::new([
        ExpectedRequest::new(
            HttpMethod::Get,
            login,
            set_cookie(
                response(200, login, login_page()),
                "PRELOGIN=fixture; Domain=sso.buaa.edu.cn; Path=/; Secure",
            ),
        ),
        ExpectedRequest::new(
            HttpMethod::Post,
            login,
            set_cookie(
                redirect(login, landing),
                "CASTGC=fixture; Domain=sso.buaa.edu.cn; Path=/; Secure",
            ),
        ),
        ExpectedRequest::new(HttpMethod::Get, landing, response(200, landing, Vec::new())),
        ExpectedRequest::new(
            HttpMethod::Get,
            activate,
            set_cookie(
                response(200, activate, Vec::new()),
                "JSESSIONID=fixture; Domain=uc.buaa.edu.cn; Path=/; Secure",
            ),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            status,
            response(
                200,
                status,
                r#"{"code":0,"data":{"name":"Fixture User","schoolid":"TEST-0001","username":"fixture-user"}}"#,
            ),
        ),
        ExpectedRequest::new(HttpMethod::Get, userinfo, response(200, userinfo, fixture)),
    ]);
    (transport, MemorySessionStore::new())
}

pub(crate) fn persisted_store() -> MemorySessionStore {
    let store = MemorySessionStore::new();
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: vec![StoredCookie::fixture("SESSION", "fixture-cookie")],
            authenticated_at: 1,
            last_activity: 1,
        })
        .unwrap();
    store
}
