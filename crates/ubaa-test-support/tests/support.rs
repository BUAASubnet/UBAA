use ubaa_core::ports::{HttpMethod, HttpRequest, HttpResponse, HttpTransport};
use ubaa_test_support::{
    ExpectedRequest, MockTransport, assert_fixture_is_sanitized, auth_fixture,
};

#[test]
fn auth_fixtures_are_synthetic_and_sanitized() {
    for name in ["login-page.html", "userinfo-success.json"] {
        let fixture = auth_fixture(name).expect("known fixture exists");
        assert_fixture_is_sanitized(fixture).expect("fixture contains no forbidden material");
    }
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
