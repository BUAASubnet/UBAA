use std::collections::BTreeSet;
use std::fs;
use std::path::Path;

use ubaa_core::facade::ConnectionMode;
use ubaa_core::facade::testing::{
    HttpMethod, HttpRequest, HttpResponse, HttpTransport, SessionMutation, SessionSnapshot,
    SessionStore, StoredCookie,
};
use ubaa_test_support::{
    ExpectedRequest, MemorySessionStore, MockTransport, assert_fixture_is_sanitized, auth_fixture,
    readonly_fixture,
};

fn has_fixture_extension(path: &Path) -> bool {
    matches!(
        path.extension().and_then(|extension| extension.to_str()),
        Some("html" | "json")
    )
}

fn is_fixture_entry(is_regular_file: bool, name: &str) -> bool {
    is_regular_file && has_fixture_extension(Path::new(name))
}

fn fixture_names_on_disk(directory: &str) -> BTreeSet<String> {
    fs::read_dir(
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../fixtures")
            .join(directory),
    )
    .unwrap_or_else(|error| panic!("{directory} fixture directory is unreadable: {error}"))
    .filter_map(|entry| {
        let entry = entry
            .unwrap_or_else(|error| panic!("{directory} fixture entry is unreadable: {error}"));
        let file_type = entry.file_type().unwrap_or_else(|error| {
            panic!("{directory} fixture entry type is unreadable: {error}")
        });
        if !file_type.is_file() || !has_fixture_extension(&entry.path()) {
            return None;
        }
        let name = entry
            .file_name()
            .into_string()
            .unwrap_or_else(|_| panic!("{directory} fixture file name must be valid UTF-8"));
        debug_assert!(is_fixture_entry(true, &name));
        Some(name)
    })
    .collect()
}

#[test]
fn auth_fixtures_are_synthetic_and_sanitized() {
    assert!(is_fixture_entry(true, "login-page.html"));
    assert!(is_fixture_entry(true, "userinfo-success.json"));
    assert!(!is_fixture_entry(true, ".DS_Store"));
    assert!(!is_fixture_entry(true, ".fixture.json.swp"));
    assert!(!is_fixture_entry(true, "README.txt"));
    assert!(!is_fixture_entry(false, "nested.json"));

    let names = ["login-page.html", "userinfo-success.json"];
    let expected = names
        .iter()
        .map(|name| (*name).to_owned())
        .collect::<BTreeSet<_>>();
    let on_disk = fixture_names_on_disk("auth");
    assert_eq!(on_disk, expected, "auth fixture registry must match disk");

    for name in names {
        let fixture =
            auth_fixture(name).unwrap_or_else(|| panic!("known auth fixture exists: {name}"));
        assert_fixture_is_sanitized(fixture).expect("fixture contains no forbidden material");
    }
}

#[test]
fn readonly_fixtures_are_synthetic_and_sanitized() {
    let names = [
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
        "cgyy-sites.json",
        "cgyy-day.json",
        "cgyy-orders.json",
    ];
    let expected = names
        .iter()
        .map(|name| (*name).to_owned())
        .collect::<BTreeSet<_>>();
    let on_disk = fixture_names_on_disk("readonly");
    assert_eq!(
        on_disk, expected,
        "readonly fixture registry must match disk"
    );

    for name in names {
        let fixture = readonly_fixture(name)
            .unwrap_or_else(|| panic!("known readonly fixture exists: {name}"));
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
