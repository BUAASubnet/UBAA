//! 与客户端登录按钮共用 Core 静默认证，批处理不接收人工验证码。
use crate::evidence::Evidence;
use ubaa_core::facade::{
    ConnectionMode, DualLoginInput, ErrorCode, InteractiveRouteState, LoginInput, RoutePolicy,
    UbaaClient,
};

pub(crate) async fn login(
    client: &mut UbaaClient,
    mode: ConnectionMode,
    input: LoginInput,
    evidence: &mut Evidence,
) -> bool {
    let prepared = match prepare(client, mode, &input.username).await {
        Ok(value) => value,
        Err(error) => {
            evidence.fail("auth", "prepare", error.code);
            evidence.blocked("auth", "login", "prepare_failed");
            return false;
        }
    };
    let login = prepared.login.clone();
    let route = prepared
        .routes
        .iter()
        .find(|route| route.route == mode)
        .expect("固定路线结果必须存在");
    if route.state == InteractiveRouteState::Failed {
        evidence.fail_code(
            "auth",
            "prepare",
            route
                .error
                .as_ref()
                .map_or("upstream_changed", |error| error.code.as_str()),
        );
        evidence.blocked("auth", "login", "prepare_failed");
        client.interactive_login_cancellation().cancel();
        client.discard_cancelled_interactive_login();
        return false;
    }
    evidence.pass_with_fields(
        "auth",
        "prepare",
        None,
        &[("mapping", "embedded_login_state".into())],
    );
    let result = client
        .submit_quiet_login(
            &login,
            DualLoginInput {
                username: input.username,
                password: input.password,
            },
        )
        .await;
    let ready = match result {
        Err(error) => {
            evidence.fail("auth", "login", error.code);
            false
        }
        Ok(outcome) => {
            let route = outcome
                .routes
                .iter()
                .find(|route| route.route == mode)
                .expect("固定路线结果必须存在");
            match route.state {
                InteractiveRouteState::Ready => {
                    match client.continue_interactive_login(&login, mode, false) {
                        Ok(_) => {
                            evidence.pass("auth", "login", None);
                            true
                        }
                        Err(error) => {
                            evidence.fail("auth", "login", error.code);
                            false
                        }
                    }
                }
                InteractiveRouteState::CaptchaRequired => {
                    evidence.fail_code("auth", "login", "captcha_required");
                    false
                }
                _ => {
                    evidence.fail_code(
                        "auth",
                        "login",
                        route.error.as_ref().map_or(
                            crate::evidence::error_code(ErrorCode::AuthenticationRequired),
                            |error| error.code.as_str(),
                        ),
                    );
                    false
                }
            }
        }
    };
    if !ready {
        client.interactive_login_cancellation().cancel();
        client.discard_cancelled_interactive_login();
    }
    ready
}

async fn prepare(
    client: &mut UbaaClient,
    mode: ConnectionMode,
    username: &str,
) -> ubaa_core::facade::Result<ubaa_core::facade::InteractiveLoginOutcome> {
    client.set_default_route_policy(match mode {
        ConnectionMode::Direct => RoutePolicy::Direct,
        ConnectionMode::WebVpn => RoutePolicy::WebVpn,
    })?;
    let login = client.interactive_login_cancellation().begin(username)?;
    client.prepare_quiet_login_for(&login).await
}

#[cfg(test)]
#[path = "../tests/authentication/mod.rs"]
mod tests;
