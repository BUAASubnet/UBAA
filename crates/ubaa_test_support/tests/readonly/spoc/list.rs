use aes::Aes128;
use aes::cipher::{BlockDecrypt, KeyInit, generic_array::GenericArray};
use base64::Engine as _;
use ubaa_core::facade::testing::{HttpRequest, to_webvpn_url};
use ubaa_core::facade::{ConnectionMode, LoginInput, RouteClient, SecretValue};
use ubaa_test_support::readonly_fixture;

use crate::common::{
    SpocTransport, redirect, redirect_from, response, session_store, session_store_for,
    session_store_with,
};

fn decrypt_spoc_page_request(request: &HttpRequest) -> String {
    let body: serde_json::Value = serde_json::from_slice(&request.body).expect("page request JSON");
    let encoded = body["param"].as_str().expect("encrypted page param");
    let mut encrypted = base64::engine::general_purpose::STANDARD
        .decode(encoded)
        .expect("base64 page param");
    assert_eq!(
        encrypted.len() % 16,
        0,
        "AES-CBC input must be block aligned"
    );
    let cipher = Aes128::new_from_slice(b"inco12345678ocni").expect("static AES key");
    let mut previous = *b"ocni12345678inco";
    for chunk in encrypted.chunks_exact_mut(16) {
        let ciphertext = <[u8; 16]>::try_from(&*chunk).expect("AES block");
        let mut block = GenericArray::clone_from_slice(chunk);
        cipher.decrypt_block(&mut block);
        for (byte, prior) in block.iter_mut().zip(previous) {
            *byte ^= prior;
        }
        chunk.copy_from_slice(&block);
        previous = ciphertext;
    }
    while encrypted.last() == Some(&0) {
        encrypted.pop();
    }
    String::from_utf8(encrypted).expect("UTF-8 page plaintext")
}

#[tokio::test]
async fn spoc_list_follows_cas_and_maps_all_pages() {
    let cas = "https://spoc.buaa.edu.cn/spocnewht/cas";
    let token_url = "https://spoc.buaa.edu.cn/spocnew/cas?token=test-token";
    let transport = SpocTransport::new([
        (cas.into(), redirect(token_url)),
        (
            "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin".into(),
            response(
                200,
                "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin",
                r#"{"code":200,"content":{"jsdm":"01"}}"#,
            ),
        ),
        (
            "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne".into(),
            response(
                200,
                "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne",
                r#"{"code":200,"content":{"dqxq":"Spring","mrxq":"2025-20262"}}"#,
            ),
        ),
        (
            "https://spoc.buaa.edu.cn/spocnewht/jxkj/queryKclb?kcmc=&xnxq=2025-20262".into(),
            response(
                200,
                "https://spoc.buaa.edu.cn/spocnewht/jxkj/queryKclb?kcmc=&xnxq=2025-20262",
                r#"{"code":200,"content":[{"kcid":"course-1","kcmc":"Systems","skjs":"Teacher"},{"kcid":"course-2","kcmc":"Networks","skjs":"Another Teacher"}]}"#,
            ),
        ),
        (
            "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage".into(),
            response(
                200,
                "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage",
                readonly_fixture("spoc-page.json").unwrap(),
            ),
        ),
        (
            "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage".into(),
            response(
                200,
                "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage",
                r#"{"code":200,"content":{"pageNum":2,"pageSize":15,"pages":2,"hasNextPage":false,"list":[{"zyid":"a2","tjzt":"已做","zyjzsj":"2026-03-19T16:00:00.000+00:00","zymc":"Lab","zykssj":"2026-03-16T08:00:00.000+00:00","sskcid":"course-1","kcmc":"Systems","mf":"满分:100"}]}}"#,
            ),
        ),
    ]);
    let observed = transport.clone();
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, transport, session_store())
            .expect("client");

    let result = client
        .spoc_assignments_diagnostics()
        .await
        .expect("SPOC list diagnostics");
    assert_eq!(result.data.global_page_count, 2);
    assert_eq!(result.data.result.term_code, "2025-20262");
    assert_eq!(result.data.result.assignments.len(), 2);
    assert_eq!(result.data.result.assignments[0].assignment_id, "a2");
    assert_eq!(
        result.data.result.assignments[0].submission_status_text,
        "已提交"
    );
    assert_eq!(result.data.result.assignments[1].course_name, "Systems");
    let second = &result.data.result.assignments[1];
    assert_eq!(second.teacher_name.as_deref(), Some("Teacher"));
    assert_eq!(second.due_time.as_deref(), Some("2026-03-31 23:59:59"));
    observed.assert_exhausted();
    let requests = observed.requests();
    assert_eq!(
        requests
            .iter()
            .filter(|request| {
                request.url == "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage"
            })
            .count(),
        2,
        "global pagination must not repeat for each course"
    );
    assert!(!requests[0].headers.contains_key("Accept"));
    assert_eq!(
        String::from_utf8(requests[1].body.clone()).unwrap(),
        r#"{"token":"test-token"}"#
    );
    let page_requests = requests
        .iter()
        .filter(|request| {
            request.url == "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage"
        })
        .collect::<Vec<_>>();
    assert_eq!(
        decrypt_spoc_page_request(page_requests[0]),
        r#"{"pageSize":15,"pageNum":1,"sqlid":"1713252980496efac7d5d9985e81693116d3e8a52ebf2b","xnxq":"2025-20262","kcid":"","yzwz":""}"#
    );
    assert_eq!(
        decrypt_spoc_page_request(page_requests[1]),
        r#"{"pageSize":15,"pageNum":2,"sqlid":"1713252980496efac7d5d9985e81693116d3e8a52ebf2b","xnxq":"2025-20262","kcid":"","yzwz":""}"#
    );
}

#[tokio::test]
async fn spoc_sequential_reads_reuse_one_route_owned_login() {
    let cas = "https://spoc.buaa.edu.cn/spocnewht/cas";
    let token_url = "https://spoc.buaa.edu.cn/spocnew/cas?token=reused-token";
    let login_url = "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin";
    let term_url = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne";
    let courses_url = "https://spoc.buaa.edu.cn/spocnewht/jxkj/queryKclb?kcmc=&xnxq=2025-20262";
    let assignments_url = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage";
    let term = r#"{"code":200,"content":{"dqxq":"Spring","mrxq":"2025-20262"}}"#;
    let empty_courses = r#"{"code":200,"content":[]}"#;
    let empty_page = r#"{"code":200,"content":{"pageNum":1,"pageSize":15,"pages":1,"hasNextPage":false,"list":[]}}"#;
    let transport = SpocTransport::new([
        (cas.into(), redirect(token_url)),
        (
            login_url.into(),
            response(200, login_url, r#"{"code":200,"content":{"jsdm":"01"}}"#),
        ),
        (term_url.into(), response(200, term_url, term)),
        (
            courses_url.into(),
            response(200, courses_url, empty_courses),
        ),
        (
            assignments_url.into(),
            response(200, assignments_url, empty_page),
        ),
        (term_url.into(), response(200, term_url, term)),
        (
            courses_url.into(),
            response(200, courses_url, empty_courses),
        ),
        (
            assignments_url.into(),
            response(200, assignments_url, empty_page),
        ),
    ]);
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("spoc-reuse-fixture"),
    )
    .unwrap();

    client.spoc_assignments().await.unwrap();
    client.spoc_assignments().await.unwrap();

    observed.assert_exhausted();
    assert_eq!(
        observed
            .requests()
            .iter()
            .filter(|request| request.url == login_url)
            .count(),
        1,
        "one route must reuse its established SPOC token and role"
    );
}

#[tokio::test]
async fn successful_primary_login_invalidates_the_cached_spoc_credential() {
    let cas = "https://spoc.buaa.edu.cn/spocnewht/cas";
    let spoc_login = "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin";
    let term = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne";
    let courses = "https://spoc.buaa.edu.cn/spocnewht/jxkj/queryKclb?kcmc=&xnxq=2025-20262";
    let assignments = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage";
    let primary_login = "https://sso.buaa.edu.cn/login";
    let activate =
        "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin";
    let status = "https://uc.buaa.edu.cn/api/uc/status";
    let userinfo = "https://uc.buaa.edu.cn/api/uc/userinfo";
    let profile = r#"{"code":0,"data":{"name":"Fixture User","schoolid":"TEST-0001","username":"fixture-user"}}"#;
    let term_body = r#"{"code":200,"content":{"dqxq":"Spring","mrxq":"2025-20262"}}"#;
    let empty_courses = r#"{"code":200,"content":[]}"#;
    let empty_page = r#"{"code":200,"content":{"pageNum":1,"pageSize":15,"pages":1,"hasNextPage":false,"list":[]}}"#;
    let transport = SpocTransport::new([
        (
            cas.into(),
            redirect("https://spoc.buaa.edu.cn/spocnew/cas?token=first-token"),
        ),
        (
            spoc_login.into(),
            response(200, spoc_login, r#"{"code":200,"content":{"jsdm":"01"}}"#),
        ),
        (term.into(), response(200, term, term_body)),
        (courses.into(), response(200, courses, empty_courses)),
        (assignments.into(), response(200, assignments, empty_page)),
        (
            primary_login.into(),
            redirect_from(primary_login, "/already-authenticated"),
        ),
        (activate.into(), response(200, activate, "")),
        (status.into(), response(200, status, profile)),
        (userinfo.into(), response(200, userinfo, profile)),
        (
            cas.into(),
            redirect("https://spoc.buaa.edu.cn/spocnew/cas?token=second-token"),
        ),
        (
            spoc_login.into(),
            response(200, spoc_login, r#"{"code":200,"content":{"jsdm":"02"}}"#),
        ),
        (term.into(), response(200, term, term_body)),
        (courses.into(), response(200, courses, empty_courses)),
        (assignments.into(), response(200, assignments, empty_page)),
    ]);
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("spoc-primary-relogin-fixture"),
    )
    .unwrap();

    client.spoc_assignments().await.unwrap();
    client.prepare_login().await.unwrap();
    client
        .login(LoginInput {
            username: "fixture-user".into(),
            password: SecretValue::new("fixture-password"),
        })
        .await
        .unwrap();
    client.spoc_assignments().await.unwrap();

    observed.assert_exhausted();
    assert_eq!(
        observed
            .requests()
            .iter()
            .filter(|request| request.url == spoc_login)
            .count(),
        2
    );
}

#[tokio::test]
async fn spoc_login_follows_the_bounded_direct_cas_chain() {
    let cas = "https://spoc.buaa.edu.cn/spocnewht/cas";
    let sso = "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fspoc.buaa.edu.cn";
    let service = "https://spoc.buaa.edu.cn/spocnewht/casLogin?ticket=fixture-ticket";
    let token = "https://spoc.buaa.edu.cn/spocnew/cas?token=chain-token";
    let login = "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin";
    let term = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne";
    let courses = "https://spoc.buaa.edu.cn/spocnewht/jxkj/queryKclb?kcmc=&xnxq=2025-20262";
    let assignments = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage";
    let transport = SpocTransport::new([
        (cas.into(), redirect_from(cas, sso)),
        (sso.into(), redirect_from(sso, service)),
        (service.into(), redirect_from(service, token)),
        (
            login.into(),
            response(200, login, r#"{"code":200,"content":{"jsdm":"01"}}"#),
        ),
        (
            term.into(),
            response(
                200,
                term,
                r#"{"code":200,"content":{"dqxq":"Spring","mrxq":"2025-20262"}}"#,
            ),
        ),
        (
            courses.into(),
            response(200, courses, r#"{"code":200,"content":[]}"#),
        ),
        (
            assignments.into(),
            response(
                200,
                assignments,
                r#"{"code":200,"content":{"pageNum":1,"pageSize":15,"pages":1,"hasNextPage":false,"list":[]}}"#,
            ),
        ),
    ]);
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("spoc-chain-fixture"),
    )
    .unwrap();

    client.spoc_assignments().await.unwrap();

    observed.assert_exhausted();
    assert_eq!(observed.requests().len(), 7);
}

#[tokio::test]
async fn spoc_webvpn_login_resolves_gateway_relative_redirects_without_double_encoding() {
    let cas = "https://spoc.buaa.edu.cn/spocnewht/cas";
    let sso = "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fspoc.buaa.edu.cn";
    let token = "https://spoc.buaa.edu.cn/spocnew/cas?token=webvpn-chain-token";
    let login = "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin";
    let term = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne";
    let courses = "https://spoc.buaa.edu.cn/spocnewht/jxkj/queryKclb?kcmc=&xnxq=2025-20262";
    let assignments = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage";
    let webvpn_cas = to_webvpn_url(cas).unwrap();
    let webvpn_sso = to_webvpn_url(sso).unwrap();
    let webvpn_token = to_webvpn_url(token).unwrap();
    let webvpn_login = to_webvpn_url(login).unwrap();
    let webvpn_term = to_webvpn_url(term).unwrap();
    let webvpn_courses = to_webvpn_url(courses).unwrap();
    let webvpn_assignments = to_webvpn_url(assignments).unwrap();
    let relative_sso = webvpn_sso
        .strip_prefix("https://d.buaa.edu.cn")
        .unwrap()
        .to_owned();
    let relative_token = webvpn_token
        .strip_prefix("https://d.buaa.edu.cn")
        .unwrap()
        .to_owned();
    let transport = SpocTransport::new([
        (
            webvpn_cas.clone(),
            redirect_from(&webvpn_cas, &relative_sso),
        ),
        (
            webvpn_sso.clone(),
            redirect_from(&webvpn_sso, &relative_token),
        ),
        (
            webvpn_login.clone(),
            response(
                200,
                &webvpn_login,
                r#"{"code":200,"content":{"jsdm":"01"}}"#,
            ),
        ),
        (
            webvpn_term.clone(),
            response(
                200,
                &webvpn_term,
                r#"{"code":200,"content":{"dqxq":"Spring","mrxq":"2025-20262"}}"#,
            ),
        ),
        (
            webvpn_courses.clone(),
            response(200, &webvpn_courses, r#"{"code":200,"content":[]}"#),
        ),
        (
            webvpn_assignments.clone(),
            response(
                200,
                &webvpn_assignments,
                r#"{"code":200,"content":{"pageNum":1,"pageSize":15,"pages":1,"hasNextPage":false,"list":[]}}"#,
            ),
        ),
    ]);
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::WebVpn,
        transport,
        session_store_for(ConnectionMode::WebVpn, "spoc-webvpn-chain-fixture"),
    )
    .unwrap();

    client.spoc_assignments().await.unwrap();

    observed.assert_exhausted();
    assert_eq!(observed.requests()[1].url, webvpn_sso);
}

#[tokio::test]
async fn direct_and_webvpn_clients_do_not_share_spoc_credentials() {
    let cas = "https://spoc.buaa.edu.cn/spocnewht/cas";
    let login_url = "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin";
    let term_url = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne";
    let courses_url = "https://spoc.buaa.edu.cn/spocnewht/jxkj/queryKclb?kcmc=&xnxq=2025-20262";
    let assignments_url = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage";
    let term = r#"{"code":200,"content":{"dqxq":"Spring","mrxq":"2025-20262"}}"#;
    let empty_courses = r#"{"code":200,"content":[]}"#;
    let empty_page = r#"{"code":200,"content":{"pageNum":1,"pageSize":15,"pages":1,"hasNextPage":false,"list":[]}}"#;
    let first_transport = SpocTransport::new([
        (
            cas.into(),
            redirect("https://spoc.buaa.edu.cn/spocnew/cas?token=first-token"),
        ),
        (
            login_url.into(),
            response(200, login_url, r#"{"code":200,"content":{"jsdm":"01"}}"#),
        ),
        (term_url.into(), response(200, term_url, term)),
        (
            courses_url.into(),
            response(200, courses_url, empty_courses),
        ),
        (
            assignments_url.into(),
            response(200, assignments_url, empty_page),
        ),
    ]);
    let webvpn_cas = to_webvpn_url(cas).unwrap();
    let webvpn_token =
        to_webvpn_url("https://spoc.buaa.edu.cn/spocnew/cas?token=second-token").unwrap();
    let webvpn_login = to_webvpn_url(login_url).unwrap();
    let webvpn_term = to_webvpn_url(term_url).unwrap();
    let webvpn_courses = to_webvpn_url(courses_url).unwrap();
    let webvpn_assignments = to_webvpn_url(assignments_url).unwrap();
    let second_transport = SpocTransport::new([
        (
            webvpn_cas.clone(),
            redirect_from(&webvpn_cas, &webvpn_token),
        ),
        (
            webvpn_login.clone(),
            response(
                200,
                &webvpn_login,
                r#"{"code":200,"content":{"jsdm":"02"}}"#,
            ),
        ),
        (webvpn_term.clone(), response(200, &webvpn_term, term)),
        (
            webvpn_courses.clone(),
            response(200, &webvpn_courses, empty_courses),
        ),
        (
            webvpn_assignments.clone(),
            response(200, &webvpn_assignments, empty_page),
        ),
    ]);
    let first_observed = first_transport.clone();
    let second_observed = second_transport.clone();
    let mut first = RouteClient::with_transport(
        ConnectionMode::Direct,
        first_transport,
        session_store_with("spoc-first-route-fixture"),
    )
    .unwrap();
    let mut second = RouteClient::with_transport(
        ConnectionMode::WebVpn,
        second_transport,
        session_store_for(ConnectionMode::WebVpn, "spoc-second-route-fixture"),
    )
    .unwrap();

    first.spoc_assignments().await.unwrap();
    second.spoc_assignments().await.unwrap();

    first_observed.assert_exhausted();
    second_observed.assert_exhausted();
    assert_eq!(
        first_observed.requests()[1]
            .headers
            .get("Token")
            .map(String::as_str),
        Some("Inco-first-token")
    );
    assert_eq!(
        second_observed.requests()[1]
            .headers
            .get("Token")
            .map(String::as_str),
        Some("Inco-second-token")
    );
}
