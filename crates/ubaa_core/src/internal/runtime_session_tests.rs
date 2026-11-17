use std::sync::atomic::AtomicU64;
use std::time::Duration;

use super::*;
use crate::auth::sso_identity;
use crate::session::{DualSessionCoordinator, FileSessionStore, StoredCookie};

struct SharedProfile(std::path::PathBuf);

impl SharedProfile {
    fn new(max_age: Option<i64>) -> Self {
        let root = Self(
            std::env::temp_dir().join(format!("ubaa-shared-profile-{}", uuid::Uuid::new_v4())),
        );
        let coordinator = DualSessionCoordinator::new(root.store()).unwrap();
        let route = coordinator.route_store(ConnectionMode::Direct);
        route
            .compare_exchange(
                0,
                Some(&SessionSnapshot {
                    mode: ConnectionMode::Direct,
                    cookies: vec![StoredCookie {
                        max_age,
                        ..StoredCookie::fixture("SESSION", "fixture")
                    }],
                    authenticated_at: 1_000,
                    last_activity: 1_010,
                }),
            )
            .unwrap();
        root
    }

    fn store(&self) -> FileSessionStore {
        FileSessionStore::new(&self.0).unwrap()
    }

    fn client(
        &self,
        time: &Arc<AtomicU64>,
        cookie: Option<&'static str>,
    ) -> (DualSessionCoordinator, ClientRuntime) {
        let coordinator = DualSessionCoordinator::new(self.store()).unwrap();
        let store = Arc::new(coordinator.route_store(ConnectionMode::Direct));
        let persisted = store.load_versioned().unwrap();
        let time = Arc::clone(time);
        let runtime = ClientRuntime::from_versioned(
            ConnectionMode::Direct,
            Arc::new(IdentityTransport(cookie)),
            store,
            persisted,
            Arc::new(move || UNIX_EPOCH + Duration::from_secs(time.load(Ordering::Relaxed))),
        )
        .unwrap();
        (coordinator, runtime)
    }
}

impl Drop for SharedProfile {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

struct IdentityTransport(Option<&'static str>);

#[async_trait::async_trait]
impl HttpTransport for IdentityTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        if request.url.starts_with("https://sso.buaa.edu.cn/login?") {
            let mut response = HttpResponse::new(302, request.url, Vec::new());
            response.headers.insert("Location".into(), vec!["https://byxt.buaa.edu.cn/jwapp/sys/homeapp/index.do?contextPath=/jwapp&ticket=fixture".into()]);
            if let Some(cookie) = self.0 {
                response
                    .headers
                    .insert("Set-Cookie".into(), vec![cookie.into()]);
            }
            return Ok(response);
        }
        assert!(
            request
                .url
                .starts_with("https://sso.buaa.edu.cn/serviceValidate?")
        );
        Ok(HttpResponse::new(
            200,
            request.url,
            br#"{"user":"fixture","attributes":{"employeeNumber":["fixture"]}}"#.to_vec(),
        ))
    }
}

#[tokio::test]
async fn shared_profile_cookie_unchanged_read_keeps_other_client_current() {
    for cookie in [None, Some("SESSION=fixture; Path=/; Secure")] {
        let profile = SharedProfile::new(None);
        let now = Arc::new(AtomicU64::new(1_011));
        let (first, reader_a) = profile.client(&now, None);
        let (_, mut reader_b) = profile.client(&now, cookie);

        let status = sso_identity::validate_status(&mut reader_b, &mut || {})
            .await
            .unwrap();

        reader_a
            .ensure_session_revision()
            .expect("无变化的只读校验不应使另一实例失去会话所有权");
        assert!(!first.is_conflicted());
        assert_eq!(status.last_activity, 1_011);
        assert_eq!(reader_b.last_activity, Some(1_011));
        assert_eq!(
            profile
                .store()
                .load_dual_versioned()
                .unwrap()
                .snapshot
                .unwrap()
                .sessions
                .direct
                .unwrap()
                .last_activity,
            1_010
        );
    }
}

#[tokio::test]
async fn shared_profile_cookie_change_keeps_external_conflict_terminal() {
    for (header, expected_value, max_age) in [
        ("SESSION=changed; Path=/; Secure", "changed", None),
        (
            "SESSION=fixture; Path=/; Secure; Max-Age=120",
            "fixture",
            Some(120),
        ),
    ] {
        let profile = SharedProfile::new(max_age);
        let now = Arc::new(AtomicU64::new(1_011));
        let (first, mut reader_a) = profile.client(&now, None);
        let (_, mut reader_b) = profile.client(&now, Some(header));
        let before = profile.store().load_dual_versioned().unwrap().revision;

        sso_identity::validate_status(&mut reader_b, &mut || {})
            .await
            .unwrap();

        let persisted = profile.store().load_dual_versioned().unwrap();
        assert_eq!(persisted.revision, before + 1);
        let snapshot = persisted.snapshot.unwrap().sessions.direct.unwrap();
        assert_eq!(
            (
                snapshot.cookies[0].value.as_str(),
                snapshot.cookies[0].max_age
            ),
            (expected_value, max_age)
        );
        assert_eq!(snapshot.cookies[0].created_at, 1_011);
        let mut cleared = false;
        let error = sso_identity::validate_status(&mut reader_a, &mut || cleared = true)
            .await
            .unwrap_err();
        assert!(error.is_session_conflict());
        assert!(cleared);
        assert!(!reader_a.has_local_session());
        assert_eq!(
            reader_a.ensure_session_revision().unwrap_err().code,
            ErrorCode::InternalError
        );
        assert!(first.is_conflicted());
        assert!(reader_a.clear_with(|| {}).is_err());
        assert_eq!(
            profile.store().load_dual_versioned().unwrap().revision,
            before + 1
        );
    }
}

#[tokio::test]
async fn shared_profile_activity_is_saved_at_interval_since_last_write() {
    let profile = SharedProfile::new(None);
    let now = Arc::new(AtomicU64::new(1_069));
    let (_, mut reader) = profile.client(&now, None);
    let before = profile.store().load_dual_versioned().unwrap();

    sso_identity::validate_status(&mut reader, &mut || {})
        .await
        .unwrap();
    assert_eq!(
        profile.store().load_dual_versioned().unwrap().revision,
        before.revision
    );

    now.store(1_070, Ordering::Relaxed);
    sso_identity::validate_status(&mut reader, &mut || {})
        .await
        .unwrap();
    let persisted = profile.store().load_dual_versioned().unwrap();
    assert_eq!(persisted.revision, before.revision + 1);
    assert_eq!(
        persisted
            .snapshot
            .unwrap()
            .sessions
            .direct
            .unwrap()
            .last_activity,
        1_070
    );
}
