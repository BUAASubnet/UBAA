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
    /// 按当前网络和显式策略准备本次实际需要的路线，不触发另一条路线认证。
    ///
    /// # Errors
    /// 账号意图、会话所有权或准备流程失效时返回安全错误。
    pub async fn prepare_quiet_login_for(
        &mut self,
        login: &InteractiveLoginHandle,
    ) -> Result<InteractiveLoginOutcome> {
        let route = resolve_route(
            self.config.default,
            FeatureRouteConfig::SAFE_DEFAULT,
            self.probe.as_ref(),
        )
        .mode;
        self.prepare_interactive_routes(login, Some(route)).await
    }

    /// 在当前账号意图内完成有界自动认证，只将最终人工输入状态投影给宿主。
    ///
    /// # Errors
    /// 已取消、异实例、账号变化或会话冲突时拒绝，普通网络错误不重放凭据。
    pub async fn submit_quiet_login(
        &mut self,
        login: &InteractiveLoginHandle,
        input: DualLoginInput,
    ) -> Result<InteractiveLoginOutcome> {
        self.ensure_interactive(login)?;
        if input.username.trim() != login.username() || input.password.expose_secret().is_empty() {
            return Err(invalid_interaction());
        }
        let mut context = self
            .interactive
            .context
            .take()
            .ok_or_else(invalid_interaction)?;
        let mut frames = [None, None];
        for (index, frame) in frames.iter_mut().enumerate() {
            if context.routes[index].automatic_attempted
                || !matches!(
                    context.routes[index].state,
                    InteractiveRouteState::Prepared | InteractiveRouteState::CaptchaRequired
                )
            {
                continue;
            }
            context.routes[index].automatic_attempted = true;
            self.ensure_interactive_active(login)?;
            if let Some(pending) = context.routes[index].pending.take() {
                pending.handle.consume();
            }
            let route = route_at(index);
            let (runtime, auth) = self.route_parts_for(route);
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
            let manual = auth.manual_captcha.take();
            self.ensure_interactive_active(login)?;
            match result {
                Ok(profile) => self.record_interactive_profile(&mut context, index, profile)?,
                Err(error) if error.is_captcha_required() => {
                    let manual = manual.ok_or_else(invalid_interaction)?;
                    *frame = Some(self.adopt_manual_captcha(&mut context, index, manual)?);
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
