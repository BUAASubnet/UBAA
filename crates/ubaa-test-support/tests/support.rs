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
