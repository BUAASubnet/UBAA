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
