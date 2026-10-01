use super::flows::*;
use super::*;
use std::time::{Duration, Instant};
use ubaa_core::facade::testing::{HttpMethod, RouteConfig};
use ubaa_core::facade::{
    ConnectionMode, DualLoginInput, ErrorCode, LoginReadiness, NetworkState, RoutePolicy,
    SecretValue,
};

#[test]
fn expired_replaced_foreign_and_changed_account_handles_are_rejected_before_http() {
    run(async {
        let mut fixture = Fixture::new(RoutePolicy::Auto);
        let elapsed = Arc::new(AtomicU64::new(0));
        let base = Instant::now();
        let clock = elapsed.clone();
        fixture.client.set_interactive_clock(Arc::new(move || {
            base + Duration::from_millis(clock.load(Ordering::SeqCst))
        }));
        let prepared = fixture
            .client
            .prepare_interactive_login(SYNTHETIC_USERNAME.into())
            .await
            .unwrap();
        let original = prepared.routes[0].challenge.as_ref().unwrap();
        let mut foreign = Fixture::new(RoutePolicy::Auto);
        assert!(
            foreign
                .client
                .submit_interactive_login(&prepared.login, input(), vec![answer(original)])
                .await
                .is_err()
        );
        assert_eq!(foreign.count(), 0);
        let before = fixture.count();
        let mut changed = input();
        changed.username = "synthetic-another-account".into();
        assert!(
            fixture
                .client
                .submit_interactive_login(&prepared.login, changed, vec![answer(original)])
                .await
                .is_err()
        );
        assert_eq!(fixture.count(), before);
        elapsed.store(120_000, Ordering::SeqCst);
        assert!(
            fixture
                .client
                .submit_interactive_login(&prepared.login, input(), vec![answer(original)])
                .await
                .is_err()
        );
        assert_eq!(fixture.count(), before);
        let refreshed = fixture
            .client
            .refresh_interactive_captcha(&prepared.login, ConnectionMode::Direct)
            .await
            .unwrap();
        let replacement = refreshed.routes[0].challenge.as_ref().unwrap();
        assert_ne!(original.revision(), replacement.revision());
        let before = fixture.count();
        assert!(
            fixture
                .client
                .submit_interactive_login(&prepared.login, input(), vec![answer(original)])
                .await
                .is_err()
        );
        assert_eq!(fixture.count(), before);
        fixture.client.interactive_login_cancellation().cancel();
        assert!(
            fixture
                .client
                .submit_interactive_login(&prepared.login, input(), vec![answer(replacement)])
                .await
                .is_err()
        );
        assert_eq!(fixture.count(), before);
    });
}

#[test]
fn cancellation_discards_delayed_images_and_errors_before_next_route() {
    run(async {
        for fail in [false, true] {
            let mut fixture = Fixture::new(RoutePolicy::Auto);
            let gate = Arc::new(Gate {
                started: tokio::sync::Notify::new(),
                released: tokio::sync::Notify::new(),
                fail,
            });
            fixture.direct.state.lock().unwrap().image_gate = Some(gate.clone());
            let control = fixture.client.interactive_login_cancellation();
            let requests = fixture.requests.clone();
            let task = tokio::spawn(async move {
                fixture
                    .client
                    .prepare_interactive_login(SYNTHETIC_USERNAME.into())
                    .await
                    .expect_err("取消后不能返回图片或旧错误")
            });
            gate.started.notified().await;
            control.cancel();
            gate.released.notify_one();
            assert_eq!(task.await.unwrap().code, ErrorCode::InvalidInput);
            assert_eq!(requests.lock().unwrap().len(), 2);
        }
    });
}

#[test]
fn cancellation_after_answer_send_cannot_persist_or_start_another_route() {
    run(async {
        let mut fixture = Fixture::new(RoutePolicy::Auto);
        let prepared = fixture
            .client
            .prepare_interactive_login(SYNTHETIC_USERNAME.into())
            .await
            .unwrap();
        let gate = Arc::new(Gate {
            started: tokio::sync::Notify::new(),
            released: tokio::sync::Notify::new(),
            fail: false,
        });
        fixture.direct.state.lock().unwrap().post_gate = Some(gate.clone());
        let control = fixture.client.interactive_login_cancellation();
        let requests = fixture.requests.clone();
        let task = tokio::spawn(async move {
            let result = fixture
                .client
                .submit_interactive_login(
                    &prepared.login,
                    input(),
                    vec![
                        answer(prepared.routes[0].challenge.as_ref().unwrap()),
                        answer(prepared.routes[1].challenge.as_ref().unwrap()),
                    ],
                )
                .await;
            assert!(fixture.client.active_routes().is_empty());
            result.expect_err("取消后不发布迟到认证成功")
        });
        gate.started.notified().await;
        control.cancel();
        gate.released.notify_one();
        assert_eq!(task.await.unwrap().code, ErrorCode::InvalidInput);
        let requests = requests.lock().unwrap();
        assert_eq!(
            requests
                .iter()
                .filter(|request| request.method == HttpMethod::Post)
                .count(),
            1
        );
        assert!(requests.iter().all(
            |request| !request.url.contains("/api/uc/") && !request.url.contains("/api/login")
        ));
    });
}

#[test]
fn cancelled_prepare_cannot_leave_an_interactive_form_for_the_old_login_api() {
    run(async {
        let mut fixture = Fixture::new(RoutePolicy::Auto);
        let gate = Arc::new(Gate {
            started: tokio::sync::Notify::new(),
            released: tokio::sync::Notify::new(),
            fail: false,
        });
        fixture.direct.state.lock().unwrap().image_gate = Some(gate.clone());
        let control = fixture.client.interactive_login_cancellation();
        let task = tokio::spawn(async move {
            assert!(
                fixture
                    .client
                    .prepare_interactive_login(SYNTHETIC_USERNAME.into())
                    .await
                    .is_err()
            );
            fixture
        });
        gate.started.notified().await;
        control.cancel();
        gate.released.notify_one();
        let mut fixture = task.await.unwrap();
        fixture.direct.state.lock().unwrap().image_gate = None;
        let ordinary = fixture.client.login(input()).await.unwrap();
        assert_eq!(ordinary.readiness, LoginReadiness::NoneReady);
        assert!(
            fixture
                .requests
                .lock()
                .unwrap()
                .iter()
                .all(|request| request.method != HttpMethod::Post)
        );
    });
}

#[test]
fn queued_cancelled_or_already_prepared_intents_cannot_clear_ready_slots_again() {
    run(async {
        let mut fixture = Fixture::new(RoutePolicy::Auto);
        let control = fixture.client.interactive_login_cancellation();
        let queued = control.begin(SYNTHETIC_USERNAME).unwrap();
        control.cancel();
        assert!(
            fixture
                .client
                .prepare_interactive_login_for(&queued)
                .await
                .is_err()
        );
        assert_eq!(fixture.count(), 0);
        fixture.direct.state.lock().unwrap().page = PLAIN_PAGE.into();
        let prepared = fixture
            .client
            .prepare_interactive_login(SYNTHETIC_USERNAME.into())
            .await
            .unwrap();
        let partial = fixture
            .client
            .submit_interactive_login(&prepared.login, input(), Vec::new())
            .await
            .unwrap();
        assert_eq!(partial.readiness, LoginReadiness::Partial);
        let before = fixture.count();
        assert!(
            fixture
                .client
                .prepare_interactive_login_for(&prepared.login)
                .await
                .is_err()
        );
        assert_eq!(fixture.count(), before);
        assert_eq!(fixture.client.active_routes(), vec![ConnectionMode::Direct]);
        fixture
            .client
            .refresh_interactive_captcha(&prepared.login, ConnectionMode::WebVpn)
            .await
            .unwrap();
        assert_eq!(fixture.client.active_routes(), vec![ConnectionMode::Direct]);
        assert_eq!(
            fixture
                .requests
                .lock()
                .unwrap()
                .iter()
                .filter(|request| request.method == HttpMethod::Post)
                .count(),
            1
        );
    });
}

#[test]
fn partial_continue_selects_ready_route_for_both_fixed_mismatches_and_auto() {
    run(async {
        for (policy, ready, expected) in [
            (
                RoutePolicy::Direct,
                ConnectionMode::WebVpn,
                RoutePolicy::WebVpn,
            ),
            (
                RoutePolicy::WebVpn,
                ConnectionMode::Direct,
                RoutePolicy::Direct,
            ),
            (RoutePolicy::Auto, ConnectionMode::Direct, RoutePolicy::Auto),
            (
                RoutePolicy::Direct,
                ConnectionMode::Direct,
                RoutePolicy::Direct,
            ),
        ] {
            let mut fixture = Fixture::new(policy);
            match ready {
                ConnectionMode::Direct => {
                    fixture.direct.state.lock().unwrap().page = PLAIN_PAGE.into();
                }
                ConnectionMode::WebVpn => {
                    fixture.webvpn.state.lock().unwrap().page = PLAIN_PAGE.into();
                }
            }
            let prepared = fixture
                .client
                .prepare_interactive_login(SYNTHETIC_USERNAME.into())
                .await
                .unwrap();
            let partial = fixture
                .client
                .submit_interactive_login(&prepared.login, input(), Vec::new())
                .await
                .unwrap();
            assert_eq!(partial.readiness, LoginReadiness::Partial);
            let before = fixture.count();
            let completed = fixture
                .client
                .continue_interactive_login(&prepared.login, ready, false)
                .unwrap();
            assert_eq!(fixture.count(), before);
            assert_eq!(
                completed.profile.unwrap().username.as_deref(),
                Some(SYNTHETIC_USERNAME)
            );
            assert_eq!(fixture.client.default_route_policy(), expected);
            assert_eq!(RouteConfig::load(&fixture.root).unwrap().default, expected);
            assert_eq!(fixture.client.active_routes(), vec![ready]);
            let user = fixture.client.get_user_info().await.unwrap();
            assert_eq!(user.resolution.mode, ready);
            assert_eq!(
                fixture
                    .requests
                    .lock()
                    .unwrap()
                    .iter()
                    .filter(|request| request.method == HttpMethod::Post)
                    .count(),
                1
            );
        }
    });
}

#[test]
fn zero_ready_and_failed_policy_save_leave_no_false_home_or_reauthentication() {
    run(async {
        let mut fixture = Fixture::new(RoutePolicy::WebVpn);
        let zero = fixture
            .client
            .prepare_interactive_login(SYNTHETIC_USERNAME.into())
            .await
            .unwrap();
        let before = fixture.count();
        assert!(
            fixture
                .client
                .continue_interactive_login(&zero.login, ConnectionMode::Direct, false)
                .is_err()
        );
        assert_eq!(fixture.count(), before);
        assert_eq!(fixture.client.default_route_policy(), RoutePolicy::WebVpn);
        fixture.direct.state.lock().unwrap().page = PLAIN_PAGE.into();
        let prepared = fixture
            .client
            .prepare_interactive_login(SYNTHETIC_USERNAME.into())
            .await
            .unwrap();
        fixture
            .client
            .submit_interactive_login(&prepared.login, input(), Vec::new())
            .await
            .unwrap();
        std::fs::remove_file(fixture.root.join("config.toml")).unwrap();
        std::fs::create_dir(fixture.root.join("config.toml")).unwrap();
        let before = fixture.count();
        assert!(
            fixture
                .client
                .continue_interactive_login(&prepared.login, ConnectionMode::Direct, false)
                .is_err()
        );
        assert_eq!(fixture.count(), before);
        assert_eq!(fixture.client.active_routes(), vec![ConnectionMode::Direct]);
        std::fs::remove_dir(fixture.root.join("config.toml")).unwrap();
        fixture
            .client
            .continue_interactive_login(&prepared.login, ConnectionMode::Direct, false)
            .unwrap();
        assert_eq!(fixture.count(), before);
        assert_eq!(fixture.client.default_route_policy(), RoutePolicy::Direct);
    });
}

#[test]
fn unavailable_auto_continue_is_rejected_until_explicit_ready_route_selection() {
    run(async {
        for (network, ready) in [
            (NetworkState::Campus, ConnectionMode::WebVpn),
            (NetworkState::OffCampus, ConnectionMode::Direct),
        ] {
            let mut fixture = Fixture::with_network(RoutePolicy::Auto, network);
            match ready {
                ConnectionMode::Direct => {
                    fixture.direct.state.lock().unwrap().page = PLAIN_PAGE.into();
                }
                ConnectionMode::WebVpn => {
                    fixture.webvpn.state.lock().unwrap().page = PLAIN_PAGE.into();
                }
            }
            let prepared = fixture
                .client
                .prepare_interactive_login(SYNTHETIC_USERNAME.into())
                .await
                .unwrap();
            let partial = fixture
                .client
                .submit_interactive_login(&prepared.login, input(), Vec::new())
                .await
                .unwrap();
            assert_eq!(partial.readiness, LoginReadiness::Partial);
            let before = fixture.count();
            let error = fixture
                .client
                .continue_interactive_login(&prepared.login, ready, false)
                .expect_err("Auto 当前所选路线未就绪时必须留在交互");
            assert_eq!(error.code, ErrorCode::AuthenticationRequired);
            assert_eq!(fixture.count(), before);
            assert_eq!(fixture.client.default_route_policy(), RoutePolicy::Auto);
            assert_eq!(fixture.client.active_routes(), vec![ready]);
            std::fs::remove_file(fixture.root.join("config.toml")).unwrap();
            std::fs::create_dir(fixture.root.join("config.toml")).unwrap();
            assert!(
                fixture
                    .client
                    .continue_interactive_login(&prepared.login, ready, true)
                    .is_err()
            );
            assert_eq!(fixture.count(), before);
            assert_eq!(fixture.client.default_route_policy(), RoutePolicy::Auto);
            std::fs::remove_dir(fixture.root.join("config.toml")).unwrap();
            let completed = fixture
                .client
                .continue_interactive_login(&prepared.login, ready, true)
                .unwrap();
            assert_eq!(
                completed.profile.unwrap().username.as_deref(),
                Some(SYNTHETIC_USERNAME)
            );
            assert_eq!(fixture.count(), before);
            let user = fixture.client.get_user_info().await.unwrap();
            assert_eq!(user.resolution.mode, ready);
            assert_eq!(
                fixture
                    .requests
                    .lock()
                    .unwrap()
                    .iter()
                    .filter(|request| request.method == HttpMethod::Post)
                    .count(),
                1
            );
        }
    });
}

#[test]
fn new_manual_account_clears_old_cookie_preparation_and_persisted_slots() {
    run(async {
        for authenticated in [false, true] {
            let mut fixture = Fixture::new(RoutePolicy::Auto);
            for route in [&fixture.direct, &fixture.webvpn] {
                let mut scenario = route.state.lock().unwrap();
                scenario.page = PLAIN_PAGE.into();
                scenario.username = "synthetic-previous-account".into();
            }
            fixture.client.prepare_login().await;
            if authenticated {
                let old = fixture
                    .client
                    .login(DualLoginInput {
                        username: "synthetic-previous-account".into(),
                        password: SecretValue::new("synthetic-old-password"),
                    })
                    .await
                    .unwrap();
                assert_eq!(old.readiness, LoginReadiness::AllReady);
            }
            for route in [&fixture.direct, &fixture.webvpn] {
                let mut scenario = route.state.lock().unwrap();
                scenario.page = SYNTHETIC_PAGE.into();
                scenario.redirect_with_cookie = true;
            }
            let before = fixture.count();
            let current = fixture
                .client
                .prepare_interactive_login(SYNTHETIC_USERNAME.into())
                .await
                .unwrap();
            assert!(current.profile.is_none());
            assert_eq!(current.readiness, LoginReadiness::NoneReady);
            assert!(fixture.client.active_routes().is_empty());
            let requests = fixture.requests.lock().unwrap();
            assert!(!requests[before].headers.contains_key("Cookie"));
            assert!(!requests[before + 2].headers.contains_key("Cookie"));
            assert!(
                requests[before..]
                    .iter()
                    .all(|request| !request.url.contains("logout"))
            );
        }
    });
}

#[test]
fn external_session_conflict_and_logout_reject_old_challenges_before_http() {
    run(async {
        let mut fixture = Fixture::new(RoutePolicy::Auto);
        let prepared = fixture
            .client
            .prepare_interactive_login(SYNTHETIC_USERNAME.into())
            .await
            .unwrap();
        let mut external = UbaaClient::with_transports(
            fixture.direct.clone(),
            fixture.webvpn.clone(),
            FileSessionStore::new(&fixture.root).unwrap(),
        )
        .unwrap();
        external
            .prepare_interactive_login("synthetic-external-owner".into())
            .await
            .unwrap();
        let before = fixture.count();
        assert!(
            fixture
                .client
                .submit_interactive_login(
                    &prepared.login,
                    input(),
                    vec![answer(prepared.routes[0].challenge.as_ref().unwrap())]
                )
                .await
                .is_err()
        );
        assert_eq!(fixture.count(), before);
        assert!(
            fixture
                .client
                .prepare_interactive_login("synthetic-new-owner-attempt".into())
                .await
                .is_err()
        );
        assert_eq!(fixture.count(), before);

        let mut fixture = Fixture::new(RoutePolicy::Auto);
        let prepared = fixture
            .client
            .prepare_interactive_login(SYNTHETIC_USERNAME.into())
            .await
            .unwrap();
        fixture.client.logout().await.unwrap();
        let before = fixture.count();
        assert!(
            fixture
                .client
                .submit_interactive_login(
                    &prepared.login,
                    input(),
                    vec![answer(prepared.routes[0].challenge.as_ref().unwrap())]
                )
                .await
                .is_err()
        );
        assert_eq!(fixture.count(), before);
    });
}

#[test]
fn cancelled_cleanup_preserves_external_session_conflict_for_the_old_api() {
    run(async {
        for (cleanup_first, check_status) in
            [(false, false), (true, false), (false, true), (true, true)]
        {
            let mut fixture = Fixture::new(RoutePolicy::Auto);
            fixture
                .client
                .prepare_interactive_login(SYNTHETIC_USERNAME.into())
                .await
                .unwrap();
            let mut external = UbaaClient::with_transports(
                fixture.direct.clone(),
                fixture.webvpn.clone(),
                FileSessionStore::new(&fixture.root).unwrap(),
            )
            .unwrap();
            external
                .prepare_interactive_login("synthetic-other-owner".into())
                .await
                .unwrap();
            if cleanup_first {
                fixture.client.interactive_login_cancellation().cancel();
                fixture.client.discard_cancelled_interactive_login();
            }
            let before = fixture.count();
            let result = if check_status {
                fixture.client.auth_status().await
            } else {
                fixture.client.login(input()).await
            };
            result.expect_err("清理交互不能丢掉旧实例的所有权冲突");
            assert_eq!(fixture.count(), before);
        }
    });
}
