use super::flows::*;
use super::*;
use ubaa_core::facade::testing::{HttpMethod, set_captcha_recognizer};
use ubaa_core::facade::{LoginInput, NetworkState, RequiredRecoveryControl, RoutePolicy};

fn refuse(transport: &ScenarioTransport) {
    let mut state = transport.state.lock().unwrap();
    state.post_status = 401;
    state.post_body =
        format!("{SYNTHETIC_PAGE}<div id=\"errorDiv\"><p>用户名或密码错误。</p></div>");
}

fn posts(fixture: &Fixture) -> usize {
    fixture
        .requests
        .lock()
        .unwrap()
        .iter()
        .filter(|r| r.method == HttpMethod::Post)
        .count()
}

#[tokio::test]
async fn 完整诊断从本次登录重新采集() {
    const ACCOUNT_A: &str = "synthetic-diagnostics-account-a";
    const ACCOUNT_B: &str = "synthetic-diagnostics-account-b";
    const OLD_RESPONSE: &str = "synthetic-prior-login-response";
    const NEW_RESPONSE: &str = "synthetic-current-login-response";

    for (logout, next_account) in [(true, ACCOUNT_B), (false, ACCOUNT_B), (false, ACCOUNT_A)] {
        let mut fixture = Fixture::new(RoutePolicy::Direct);
        let diagnostics = fixture.client.raw_diagnostics();
        diagnostics.enable();
        login_for_diagnostics(&mut fixture, ACCOUNT_A, OLD_RESPONSE).await;
        assert!(diagnostics.export_json().contains(OLD_RESPONSE));
        let signed_out = if logout {
            fixture.client.logout().await.unwrap();
            Some(serde_json::from_str::<serde_json::Value>(&diagnostics.export_json()).unwrap())
        } else {
            None
        };
        login_for_diagnostics(&mut fixture, next_account, NEW_RESPONSE).await;
        let report = diagnostics.export_json();
        assert!(report.contains(NEW_RESPONSE));
        assert!(!report.contains(OLD_RESPONSE), "诊断仍包含上一轮登录的响应");
        if let Some(signed_out) = signed_out {
            assert_eq!(signed_out["records"], serde_json::json!([]));
        }
    }
}

async fn login_for_diagnostics(fixture: &mut Fixture, account: &str, response: &str) {
    {
        let mut state = fixture.direct.state.lock().unwrap();
        state.page = PLAIN_PAGE.into();
        state.username = account.into();
        state.post_body = response.into();
    }
    let login = fixture
        .client
        .interactive_login_cancellation()
        .begin(account)
        .unwrap();
    fixture
        .client
        .prepare_quiet_login_for(&login)
        .await
        .unwrap();
    let mut credentials = input();
    credentials.username = account.into();
    fixture
        .client
        .submit_quiet_login(&login, credentials)
        .await
        .unwrap();
    let completed = fixture
        .client
        .continue_interactive_login(&login, ConnectionMode::Direct, false)
        .unwrap();
    assert_eq!(
        completed.profile.unwrap().school_id.as_deref(),
        Some(account)
    );
}

const PRIOR_RECOVERY_RESPONSE: &str = "synthetic-before-bound-recovery";
const RECOVERY_RESPONSE: &str = "synthetic-bound-recovery-response";

#[tokio::test]
async fn 静默恢复成功或失败都保留恢复前的诊断() {
    for failed in [false, true] {
        let mut fixture = Fixture::new(RoutePolicy::Direct);
        let diagnostics = fixture.client.raw_diagnostics();
        diagnostics.enable();
        login_for_diagnostics(&mut fixture, SYNTHETIC_USERNAME, PRIOR_RECOVERY_RESPONSE).await;
        if failed {
            refuse(&fixture.direct);
        } else {
            fixture.direct.state.lock().unwrap().post_body = RECOVERY_RESPONSE.into();
        }
        let credentials = input();
        let control = RequiredRecoveryControl::new(std::time::Duration::from_secs(10)).unwrap();
        let result = fixture
            .client
            .login_required_route_controlled(
                ConnectionMode::Direct,
                LoginInput {
                    username: credentials.username,
                    password: credentials.password,
                },
                control.claim().unwrap(),
            )
            .await;
        assert_eq!(result.is_err(), failed);
        let report = diagnostics.export_json();
        if !failed {
            assert!(report.contains(RECOVERY_RESPONSE));
        }
        assert!(
            report.contains(PRIOR_RECOVERY_RESPONSE),
            "静默恢复清掉了故障现场"
        );
    }
}

#[tokio::test]
async fn 静默恢复核验出不同身份后丢弃原先及恢复期间的诊断() {
    for route in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        let mut fixture = Fixture::new(RoutePolicy::Auto);
        let diagnostics = fixture.client.raw_diagnostics();
        diagnostics.enable();
        login_for_diagnostics(&mut fixture, SYNTHETIC_USERNAME, PRIOR_RECOVERY_RESPONSE).await;
        let transport = match route {
            ConnectionMode::Direct => &fixture.direct,
            ConnectionMode::WebVpn => &fixture.webvpn,
        };
        {
            let mut state = transport.state.lock().unwrap();
            state.page = PLAIN_PAGE.into();
            state.username = "synthetic-mismatched-recovery-account".into();
            state.post_body = RECOVERY_RESPONSE.into();
        }
        let credentials = input();
        let control = RequiredRecoveryControl::new(std::time::Duration::from_secs(10)).unwrap();
        let result = fixture
            .client
            .login_required_route_controlled(
                route,
                LoginInput {
                    username: credentials.username,
                    password: credentials.password,
                },
                control.claim().unwrap(),
            )
            .await;
        match route {
            ConnectionMode::Direct => assert_eq!(
                result.unwrap_err().code,
                ubaa_core::facade::ErrorCode::AuthenticationRequired,
            ),
            ConnectionMode::WebVpn => assert_eq!(
                result.unwrap().data.school_id.as_deref(),
                Some("synthetic-mismatched-recovery-account"),
            ),
        }
        let report: serde_json::Value = serde_json::from_str(&diagnostics.export_json()).unwrap();
        assert_eq!(
            report["records"],
            serde_json::json!([]),
            "诊断含不同账号的响应"
        );
    }
}

#[tokio::test]
async fn 身份核对失败保留安全原因() {
    let mut fixture = Fixture::new(RoutePolicy::Direct);
    {
        let mut state = fixture.direct.state.lock().unwrap();
        state.page = PLAIN_PAGE.into();
        state.username = "synthetic-other-account".into();
    }
    let login = fixture
        .client
        .interactive_login_cancellation()
        .begin(SYNTHETIC_USERNAME)
        .unwrap();
    fixture
        .client
        .prepare_quiet_login_for(&login)
        .await
        .unwrap();
    let result = fixture
        .client
        .submit_quiet_login(&login, input())
        .await
        .unwrap();
    let error = result
        .routes
        .iter()
        .find(|r| r.route == ConnectionMode::Direct)
        .unwrap()
        .error
        .as_ref()
        .unwrap();
    assert_eq!(error.message, "登录身份核对失败");
    let diagnostic = error.diagnostic.unwrap();
    assert_eq!(diagnostic.stage.wire_name(), "identity_validation");
    assert_eq!(diagnostic.reason.unwrap().wire_name(), "identity_mismatch");
    assert!(
        serde_json::to_value(error)
            .unwrap()
            .get("diagnostic")
            .is_none()
    );
    assert!(!error.message.contains("synthetic-other-account"));
}

#[tokio::test]
async fn 学号大小写不同仍能登录并保留学校身份() {
    for (policy, route) in [
        (RoutePolicy::Direct, ConnectionMode::Direct),
        (RoutePolicy::WebVpn, ConnectionMode::WebVpn),
    ] {
        let mut fixture = Fixture::new(policy);
        for transport in [&fixture.direct, &fixture.webvpn] {
            let mut state = transport.state.lock().unwrap();
            state.page = PLAIN_PAGE.into();
            state.username = SYNTHETIC_USERNAME.to_ascii_uppercase();
        }
        let login = fixture
            .client
            .interactive_login_cancellation()
            .begin(SYNTHETIC_USERNAME)
            .unwrap();
        fixture
            .client
            .prepare_quiet_login_for(&login)
            .await
            .unwrap();
        let result = fixture
            .client
            .submit_quiet_login(&login, input())
            .await
            .unwrap();
        assert_eq!(
            result
                .routes
                .iter()
                .find(|r| r.route == route)
                .unwrap()
                .state,
            InteractiveRouteState::Ready
        );
        let completed = fixture
            .client
            .continue_interactive_login(&login, route, false)
            .unwrap();
        assert_eq!(
            completed.profile.unwrap().school_id.as_deref(),
            Some(SYNTHETIC_USERNAME.to_ascii_uppercase().as_str())
        );
        let status = fixture.client.auth_status().await.unwrap();
        assert!(
            status
                .routes
                .iter()
                .any(|r| r.route == route && r.state == ubaa_core::facade::RouteLoginState::Ready)
        );
    }
}

#[tokio::test]
async fn 校园网仅认证直连而校外同时建立两套会话() {
    for (network, route) in [
        (NetworkState::Campus, ConnectionMode::Direct),
        (NetworkState::OffCampus, ConnectionMode::Direct),
    ] {
        let mut fixture = Fixture::with_network(RoutePolicy::Auto, network);
        set_captcha_recognizer(&mut fixture.client, |_| Some("a2b3c4".into()));
        let login = fixture
            .client
            .interactive_login_cancellation()
            .begin(SYNTHETIC_USERNAME)
            .unwrap();
        fixture
            .client
            .prepare_quiet_login_for(&login)
            .await
            .unwrap();
        let outcome = fixture
            .client
            .submit_quiet_login(&login, input())
            .await
            .unwrap();
        assert_eq!(
            outcome.required_route,
            (network == NetworkState::Campus).then_some(route)
        );
        assert_eq!(
            outcome
                .routes
                .iter()
                .filter(|r| r.state == InteractiveRouteState::Ready)
                .count(),
            if network == NetworkState::Campus {
                1
            } else {
                2
            }
        );
        fixture
            .client
            .continue_interactive_login(&login, route, false)
            .unwrap();
        if network == NetworkState::Campus {
            assert!(
                fixture
                    .requests
                    .lock()
                    .unwrap()
                    .iter()
                    .all(|r| !r.url.starts_with("https://d.buaa.edu.cn/"))
            );
        }
        assert_eq!(fixture.client.default_route_policy(), RoutePolicy::Auto);
    }
}

#[tokio::test]
async fn 三次失败后交给人工且重复调用不能重置自动次数() {
    let mut fixture = Fixture::new(RoutePolicy::Direct);
    refuse(&fixture.direct);
    set_captcha_recognizer(&mut fixture.client, |_| Some("a2b3c4".into()));
    let login = fixture
        .client
        .interactive_login_cancellation()
        .begin(SYNTHETIC_USERNAME)
        .unwrap();
    fixture
        .client
        .prepare_quiet_login_for(&login)
        .await
        .unwrap();
    let outcome = fixture
        .client
        .submit_quiet_login(&login, input())
        .await
        .unwrap();
    let challenge = outcome.routes[0].challenge.as_ref().unwrap();
    assert!(outcome.routes[0].frame.is_some());
    assert_eq!(posts(&fixture), 3);
    fixture
        .client
        .submit_quiet_login(&login, input())
        .await
        .unwrap();
    assert_eq!(posts(&fixture), 3);
    {
        let mut state = fixture.direct.state.lock().unwrap();
        state.post_status = 200;
        state.post_body = "synthetic-authenticated".into();
    }
    let done = fixture
        .client
        .submit_interactive_login(&login, input(), vec![answer(challenge)])
        .await
        .unwrap();
    assert_eq!(done.routes[0].state, InteractiveRouteState::Ready);
    assert_eq!(posts(&fixture), 4);
}

#[tokio::test]
async fn 校外任一路线已就绪即可继续且另一条验证码不强制切换策略() {
    for failed in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        let mut fixture = Fixture::with_network(RoutePolicy::Auto, NetworkState::OffCampus);
        if failed == ConnectionMode::Direct {
            refuse(&fixture.direct);
        } else {
            refuse(&fixture.webvpn);
        }
        set_captcha_recognizer(&mut fixture.client, |_| Some("a2b3c4".into()));
        let login = fixture
            .client
            .interactive_login_cancellation()
            .begin(SYNTHETIC_USERNAME)
            .unwrap();
        fixture
            .client
            .prepare_quiet_login_for(&login)
            .await
            .unwrap();
        let outcome = fixture
            .client
            .submit_quiet_login(&login, input())
            .await
            .unwrap();
        let ready = outcome
            .routes
            .iter()
            .find(|route| route.state == InteractiveRouteState::Ready)
            .unwrap()
            .route;
        assert_ne!(ready, failed);
        assert!(
            outcome.routes.iter().any(|route| route.route == failed
                && route.state == InteractiveRouteState::CaptchaRequired)
        );
        fixture
            .client
            .continue_interactive_login(&login, ready, false)
            .unwrap();
        assert_eq!(fixture.client.default_route_policy(), RoutePolicy::Auto);
    }
}

#[tokio::test]
async fn 会话恢复耗尽后沿原路线交接人工且保留自动路线策略() {
    let mut fixture = Fixture::new(RoutePolicy::Auto);
    refuse(&fixture.webvpn);
    set_captcha_recognizer(&mut fixture.client, |_| Some("a2b3c4".into()));
    let credentials = input();
    let control = RequiredRecoveryControl::new(std::time::Duration::from_secs(10)).unwrap();
    let error = fixture
        .client
        .login_required_route_controlled(
            ConnectionMode::WebVpn,
            LoginInput {
                username: credentials.username,
                password: credentials.password,
            },
            control.claim().unwrap(),
        )
        .await
        .unwrap_err();
    assert!(error.is_captcha_required());
    assert_eq!(posts(&fixture), 3);
    let before = fixture.count();
    let login = fixture
        .client
        .interactive_login_cancellation()
        .begin(SYNTHETIC_USERNAME)
        .unwrap();
    let outcome = fixture
        .client
        .resume_required_captcha(&login, ConnectionMode::WebVpn)
        .await
        .unwrap();
    assert_eq!(fixture.count(), before, "交接已有图片不重启识别或请求");
    assert_eq!(outcome.required_route, Some(ConnectionMode::WebVpn));
    {
        let mut state = fixture.webvpn.state.lock().unwrap();
        state.post_status = 200;
        state.post_body = "synthetic-authenticated".into();
    }
    fixture
        .client
        .submit_interactive_login(
            &login,
            input(),
            vec![answer(outcome.routes[1].challenge.as_ref().unwrap())],
        )
        .await
        .unwrap();
    fixture
        .client
        .continue_interactive_login(&login, ConnectionMode::WebVpn, false)
        .unwrap();
    assert_eq!(fixture.client.default_route_policy(), RoutePolicy::Auto);
    assert_eq!(posts(&fixture), 4);
}

#[tokio::test]
async fn 识别期间取消不会发送答案() {
    let mut fixture = Fixture::new(RoutePolicy::Direct);
    let control = fixture.client.interactive_login_cancellation();
    let login = control.begin(SYNTHETIC_USERNAME).unwrap();
    fixture
        .client
        .prepare_quiet_login_for(&login)
        .await
        .unwrap();
    set_captcha_recognizer(&mut fixture.client, move |_| {
        control.cancel();
        Some("a2b3c4".into())
    });
    assert!(
        fixture
            .client
            .submit_quiet_login(&login, input())
            .await
            .is_err()
    );
    assert_eq!(posts(&fixture), 0);
}
