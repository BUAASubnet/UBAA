//! 普通登录状态下的单路线静默处理与恢复后的人工交接。

use super::{
    CaptchaChallenge, CaptchaFrame, ConnectionMode, DualLoginInput, InteractiveContext,
    InteractiveLoginHandle, InteractiveLoginOutcome, InteractiveRouteState, LoginInput,
    PendingCaptcha, Result, StoredRoute, UbaaClient, invalid_interaction, route_at, route_index,
    safe_interactive_error,
};
use crate::auth::automatic::PendingManualCaptcha;
use crate::config::FeatureRouteConfig;
use crate::connection::resolve_route;

impl UbaaClient {
    /// 校园网只准备 Direct，校外 Auto 准备两条独立路线。
    ///
    /// # Errors
    /// 账号意图、会话所有权或准备流程失效时返回安全错误。
    pub async fn prepare_quiet_login_for(
        &mut self,
        login: &InteractiveLoginHandle,
    ) -> Result<InteractiveLoginOutcome> {
        login.ensure_owner(&self.interactive.cancellation)?;
        self.check_school_requests()?;
        let resolution = resolve_route(
            self.config.default,
            FeatureRouteConfig::SAFE_DEFAULT,
            self.probe.as_ref(),
        );
        let required = if resolution.policy == crate::domain::RoutePolicy::Auto
            && resolution.diagnostic.network == crate::connection::NetworkState::OffCampus
        {
            None
        } else {
            Some(resolution.mode)
        };
        self.prepare_interactive_routes(login, required).await
    }

    /// 在当前账号意图内完成有界自动认证，只将最终人工输入状态投影给宿主。
    ///
    /// # Errors
    /// 已取消、异实例、账号变化或会话冲突时拒绝；普通 `WebVPN` 登录失败最多重试一次。
    pub async fn submit_quiet_login(
        &mut self,
        login: &InteractiveLoginHandle,
        input: DualLoginInput,
    ) -> Result<InteractiveLoginOutcome> {
        self.ensure_interactive(login)?;
        self.check_school_requests()?;
        if input.username.trim() != login.username() || input.password.expose_secret().is_empty() {
            return Err(invalid_interaction());
        }
        let mut context = self
            .interactive
            .context
            .take()
            .ok_or_else(invalid_interaction)?;
        let mut frames = [None, None];
        let mut enabled = [false; 2];
        for (index, route) in context.routes.iter_mut().enumerate() {
            if route.automatic_attempted
                || !matches!(
                    route.state,
                    InteractiveRouteState::Prepared | InteractiveRouteState::CaptchaRequired
                )
            {
                continue;
            }
            route.automatic_attempted = true;
            if let Some(pending) = route.pending.take() {
                pending.handle.consume();
            }
            enabled[index] = true;
        }
        self.ensure_interactive_active(login)?;
        let (direct, webvpn) = tokio::join!(
            authenticate(
                &mut self.direct_runtime,
                &mut self.direct_auth,
                login,
                &input,
                enabled[0]
            ),
            authenticate(
                &mut self.webvpn_runtime,
                &mut self.webvpn_auth,
                login,
                &input,
                enabled[1]
            ),
        );
        self.ensure_interactive_active(login)?;
        for (index, completed) in [direct, webvpn].into_iter().enumerate() {
            let Some((result, manual)) = completed else {
                continue;
            };
            match result {
                Ok(profile) => self.record_interactive_profile(&mut context, index, profile)?,
                Err(error) if error.is_captcha_required() => {
                    let manual = manual.ok_or_else(invalid_interaction)?;
                    frames[index] = Some(self.adopt_manual_captcha(&mut context, index, manual)?);
                }
                Err(error) => {
                    context.routes[index].state = InteractiveRouteState::Failed;
                    context.routes[index].error = Some(safe_interactive_error(&error));
                }
            }
        }
        self.finish_interactive(context, frames)
    }

    /// 将当前账号的恢复失败交给人工验证，保留既有账号会话和功能路线策略。
    ///
    /// # Errors
    /// 登录句柄、待处理账号或会话所有权不匹配时拒绝。
    pub async fn resume_required_captcha(
        &mut self,
        login: &InteractiveLoginHandle,
        route: ConnectionMode,
    ) -> Result<InteractiveLoginOutcome> {
        self.direct_runtime.ensure_primary_client()?;
        login.ensure_owner(&self.interactive.cancellation)?;
        login.claim_preparation()?;
        self.guard_latest_session_ownership()?;
        let (_, auth) = self.route_parts_for(route);
        let pending = auth.manual_captcha.take().ok_or_else(invalid_interaction)?;
        if pending.username != login.username() {
            return Err(invalid_interaction());
        }
        self.verified_login = None;
        self.interactive.context = None;
        self.interactive.current_login = Some(login.clone());
        let mut context = InteractiveContext {
            login: login.clone(),
            routes: std::array::from_fn(|_| StoredRoute::default()),
            required_route: Some(route),
            keep_route_policy: true,
        };
        let mut frames = [None, None];
        let index = route_index(route);
        if pending.created_at + std::time::Duration::from_mins(2) > (self.interactive.clock)() {
            frames[index] = Some(self.adopt_manual_captcha(&mut context, index, pending)?);
        } else {
            frames[index] = self.prepare_interactive_route(&mut context, index).await?;
        }
        self.finish_interactive(context, frames)
    }

    fn adopt_manual_captcha(
        &mut self,
        context: &mut InteractiveContext,
        index: usize,
        pending: PendingManualCaptcha,
    ) -> Result<CaptchaFrame> {
        if pending.username != context.login.username() {
            return Err(invalid_interaction());
        }
        self.interactive.next_challenge += 1;
        let handle = CaptchaChallenge::new(
            context.login.clone(),
            route_at(index),
            self.interactive.next_challenge,
            pending.created_at,
        );
        handle.ensure(&context.login, route_at(index), (self.interactive.clock)())?;
        context.routes[index].state = InteractiveRouteState::CaptchaRequired;
        context.routes[index].automatic_attempted = true;
        context.routes[index].error = None;
        context.routes[index].pending = Some(PendingCaptcha {
            handle,
            page: pending.page,
        });
        Ok(pending.frame)
    }
}

async fn authenticate(
    runtime: &mut crate::runtime::ClientRuntime,
    auth: &mut crate::auth::AuthWorkflow,
    login: &InteractiveLoginHandle,
    input: &DualLoginInput,
    enabled: bool,
) -> Option<(
    Result<crate::domain::UserProfile>,
    Option<PendingManualCaptcha>,
)> {
    if !enabled {
        return None;
    }
    runtime.set_interactive_login_scope(Some(login.clone()));
    let result = auth
        .login_automatically(
            runtime,
            LoginInput {
                username: input.username.trim().to_owned(),
                password: input.password.clone(),
            },
        )
        .await;
    runtime.set_interactive_login_scope(None);
    Some((result, auth.manual_captcha.take()))
}
