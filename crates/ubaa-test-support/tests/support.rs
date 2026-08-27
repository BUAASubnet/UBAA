use std::io::{Read, Write};
use std::net::TcpListener;

use ubaa_core::domain::ConnectionMode;
use ubaa_core::error::{ErrorCode, ErrorKind};
use ubaa_core::ports::{HttpMethod, HttpRequest, HttpResponse, HttpTransport, ReqwestTransport};
use ubaa_core::session::{SessionMutation, SessionSnapshot, SessionStore, StoredCookie};
use ubaa_test_support::{
    ExpectedRequest, MemorySessionStore, MockTransport, assert_fixture_is_sanitized, auth_fixture,
    readonly_fixture,
};

#[test]
fn auth_fixtures_are_synthetic_and_sanitized() {
    for name in ["login-page.html", "userinfo-success.json"] {
        let fixture = auth_fixture(name).expect("known fixture exists");
        assert_fixture_is_sanitized(fixture).expect("fixture contains no forbidden material");
    }
}

#[test]
fn readonly_fixtures_are_synthetic_and_sanitized() {
    for name in [
        "schedule-terms.json",
        "schedule-weeks.json",
        "schedule-week.json",
        "schedule-today.json",
        "exam.json",
        "grades-page.html",
        "grades.json",
        "classroom.json",
        "spoc-page.json",
        "spoc-detail.json",
        "judge-courses.html",
        "judge-assignments.html",
        "judge-detail.html",
    ] {
        let fixture = readonly_fixture(name).expect("known fixture exists");
        assert_fixture_is_sanitized(fixture).expect("fixture contains no forbidden material");
    }
}

#[test]
fn memory_session_store_compare_exchange_rejects_stale_and_concurrent_mutations() {
    let store = MemorySessionStore::new();
    let original = memory_snapshot(0);
    store.save(&original).unwrap();
    let stale = store.load_versioned().unwrap();
    store.clear().unwrap();

    assert_eq!(
        store
            .compare_exchange(stale.revision, Some(&memory_snapshot(1)))
            .unwrap(),
        SessionMutation::Conflict
    );
    assert!(store.load().unwrap().is_none());

    store.save(&original).unwrap();
    let revision = store.load_versioned().unwrap().revision;
    let barrier = std::sync::Arc::new(std::sync::Barrier::new(2));
    let handles = (1..=2)
        .map(|index| {
            let store = store.clone();
            let barrier = std::sync::Arc::clone(&barrier);
            std::thread::spawn(move || {
                let candidate = memory_snapshot(index);
                barrier.wait();
                let mutation = store.compare_exchange(revision, Some(&candidate)).unwrap();
                (candidate, mutation)
            })
        })
        .collect::<Vec<_>>();
    let results = handles
        .into_iter()
        .map(|handle| handle.join().unwrap())
        .collect::<Vec<_>>();
    let winners = results
        .iter()
        .filter(|(_, mutation)| matches!(mutation, SessionMutation::Applied { .. }))
        .collect::<Vec<_>>();

    assert_eq!(winners.len(), 1);
    assert_eq!(store.load().unwrap(), Some(winners[0].0.clone()));
}

#[tokio::test]
async fn mock_transport_records_and_validates_scripted_requests() {
    let transport = MockTransport::new([ExpectedRequest::new(
        HttpMethod::Get,
        "https://example.invalid/test",
        HttpResponse::new(200, "https://example.invalid/test", b"fixture".to_vec()),
    )]);

    let response = transport
        .execute(HttpRequest::get("https://example.invalid/test"))
        .await
        .expect("scripted response succeeds");

    assert_eq!(response.status, 200);
    assert_eq!(response.body, b"fixture");
    transport.assert_exhausted().expect("all requests consumed");
}

#[test]
fn expected_request_debug_redacts_scripted_url() {
    let secret = "expected-request-debug-token";
    let url = format!("https://example.invalid/test?token={secret}");
    let expected = ExpectedRequest::new(
        HttpMethod::Get,
        &url,
        HttpResponse::new(200, &url, Vec::new()),
    );

    let debug = format!("{expected:?}");

    assert!(!debug.contains(secret), "debug output leaked URL token");
}

#[test]
fn mock_transport_debug_redacts_scripted_url() {
    let secret = "mock-transport-debug-token";
    let url = format!("https://example.invalid/test?token={secret}");
    let transport = MockTransport::new([ExpectedRequest::new(
        HttpMethod::Get,
        &url,
        HttpResponse::new(200, &url, Vec::new()),
    )]);

    let debug = format!("{transport:?}");

    assert!(!debug.contains(secret), "debug output leaked URL token");
}

#[tokio::test]
async fn request_mismatch_error_redacts_url_from_display_and_serializable_message() {
    let secret = "request-mismatch-token";
    let expected_url = "https://example.invalid/expected";
    let actual_url = format!("https://example.invalid/actual?token={secret}");
    let transport = MockTransport::new([ExpectedRequest::new(
        HttpMethod::Get,
        expected_url,
        HttpResponse::new(200, expected_url, Vec::new()),
    )]);

    let error = transport
        .execute(HttpRequest::get(actual_url))
        .await
        .expect_err("mismatched URL must fail");
    let display = error.to_string();

    assert!(!display.contains(secret), "display leaked URL token");
    assert_eq!(
        error.message, "unexpected request method/url mismatch",
        "the serialized message must be a fixed safe summary"
    );
}

#[tokio::test]
async fn reqwest_transport_rejects_oversized_chunked_response() {
    const LIMIT: usize = 8 * 1024 * 1024;
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let address = listener.local_addr().unwrap();
    let server = std::thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let mut request = [0_u8; 4096];
        let _ = stream.read(&mut request);
        stream
            .write_all(
                b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n",
            )
            .unwrap();
        let chunk = vec![b'x'; 64 * 1024];
        let mut remaining = LIMIT + 1;
        while remaining > 0 {
            let length = remaining.min(chunk.len());
            if write!(stream, "{length:X}\r\n")
                .and_then(|()| stream.write_all(&chunk[..length]))
                .and_then(|()| stream.write_all(b"\r\n"))
                .is_err()
            {
                return;
            }
            remaining -= length;
        }
        let _ = stream.write_all(b"0\r\n\r\n");
    });
    let transport = ReqwestTransport::new().unwrap();

    let error = transport
        .execute(HttpRequest::get(format!("http://{address}/oversized")))
        .await
        .expect_err("an oversized streamed response must be rejected");

    assert_eq!(error.code, ErrorCode::UpstreamChanged);
    assert_eq!(error.kind, ErrorKind::Upstream);
    assert!(!error.retryable);
    assert_eq!(error.message, "上游响应体超过允许大小");
    server.join().unwrap();
}

fn memory_snapshot(index: i64) -> SessionSnapshot {
    SessionSnapshot {
        mode: ConnectionMode::Direct,
        cookies: vec![StoredCookie::fixture(
            format!("SESSION-{index}"),
            format!("fixture-cookie-{index}"),
        )],
        authenticated_at: 1_000 + index,
        last_activity: 2_000 + index,
    }
}
