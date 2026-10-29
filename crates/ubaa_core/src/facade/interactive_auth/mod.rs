//! 与普通序列化登录合同隔离的当前页面交互流程。

mod image;
pub(crate) mod state;

use super::UbaaClient;
use crate::auth::interactive::{InteractivePreparation, InteractiveSubmission};
use crate::domain::{
    CaptchaAnswer, CaptchaChallenge, CaptchaFrame, ConnectionMode, DualLoginInput,
    InteractiveLoginCancellation, InteractiveLoginHandle, InteractiveLoginOutcome,
    InteractiveRouteState, LoginInput, LoginOutcome, RouteLoginResult, RouteLoginState,
    RoutePolicy, UserProfile, invalid_interaction,
};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use state::{
    InteractiveContext, PendingCaptcha, StoredRoute, route_at, route_index, safe_interactive_error,
};
use std::sync::Arc;

impl UbaaClient {
    /// 返回可绕过网络锁立即撤销当前交互的控制柄。
    #[must_use]
    pub fn interactive_login_cancellation(&self) -> InteractiveLoginCancellation {
        self.interactive.cancellation.clone()
    }

    /// 用户明确开始一次新手动登录；先原子清旧账号本地槽位，再独立准备两路。
    ///
    /// # Errors
    ///
    /// 输入、所有权、原子清理或当前交互失效时，在后续网络请求前拒绝。
    pub async fn prepare_interactive_login(
        &mut self,
        username: String,
    ) -> Result<InteractiveLoginOutcome> {
        let login = self.interactive.cancellation.begin(&username)?;
        self.prepare_interactive_login_for(&login).await
    }

    /// 准备已同步登记的页面意图；适用于需要排队获取 Core 的宿主。
    ///
    /// # Errors
    ///
    /// 登记后已取消、实例不匹配或会话清理失败时零网络拒绝。
    pub async fn prepare_interactive_login_for(
        &mut self,
        login: &InteractiveLoginHandle,
    ) -> Result<InteractiveLoginOutcome> {
        self.direct_runtime.ensure_primary_client()?;
        login.ensure_owner(&self.interactive.cancellation)?;
        login.claim_preparation()?;
        self.guard_latest_session_ownership()?;
        // 这里只清旧上下文，不能撤销刚刚同步登记的当前意图。
        self.interactive.context = None;
        self.interactive.current_login = None;
        self.direct_runtime.clear_memory();
        self.webvpn_runtime.clear_memory();
        self.direct_auth.clear();
        self.webvpn_auth.clear();
        let revisions = self.sessions.clear_both()?;
        self.direct_runtime.set_session_revision(revisions.direct);
        self.webvpn_runtime.set_session_revision(revisions.webvpn);
        self.interactive.current_login = Some(login.clone());
        let mut context = InteractiveContext {
            login: login.clone(),
            routes: std::array::from_fn(|_| StoredRoute::default()),
        };
        let mut frames = [None, None];
        for (index, frame) in frames.iter_mut().enumerate() {
            self.ensure_interactive_active(&context.login)?;
            *frame = self.prepare_interactive_route(&mut context, index).await?;
        }
        self.finish_interactive(context, frames)
    }

    /// 只向未完成的普通路线或带本路线有效答案的挑战提交；不缓存密码。
    ///
    /// # Errors
    ///
    /// 异实例、旧账号、重复、过期、已消费或已取消句柄在网络前拒绝。
    pub async fn submit_interactive_login(
        &mut self,
        login: &InteractiveLoginHandle,
        input: DualLoginInput,
        answers: Vec<CaptchaAnswer>,
    ) -> Result<InteractiveLoginOutcome> {
        self.ensure_interactive(login)?;
        if input.username.trim() != login.username() || input.password.expose_secret().is_empty() {
            return Err(invalid_interaction());
        }
        let mut supplied = self.collect_interactive_answers(login, answers)?;
        let mut context = self
            .interactive
            .context
            .take()
            .ok_or_else(invalid_interaction)?;
        let mut frames = [None, None];
        for index in 0..2 {
            self.ensure_interactive_active(login)?;
            let route = route_at(index);
            let credentials = LoginInput {
                username: input.username.trim().to_owned(),
                password: input.password.clone(),
            };
            match context.routes[index].state {
                InteractiveRouteState::Prepared => {
                    let (runtime, auth) = self.route_parts_for(route);
                    runtime.set_interactive_login_scope(Some(login.clone()));
                    let result = auth.login(runtime, credentials).await;
                    runtime.set_interactive_login_scope(None);
                    self.ensure_interactive_active(login)?;
                    match result {
                        Ok(profile) => {
                            self.record_interactive_profile(&mut context, index, profile)?;
                        }
                        Err(error) => {
                            context.routes[index].state = InteractiveRouteState::Failed;
                            context.routes[index].error = Some(safe_interactive_error(&error));
                        }
                    }
                }
                InteractiveRouteState::CaptchaRequired => {
                    let Some(answer) = supplied[index]
                        .take()
                        .filter(|value| !value.answer.expose_secret().trim().is_empty())
                    else {
                        continue;
                    };
                    let pending = context.routes[index]
                        .pending
                        .take()
                        .ok_or_else(invalid_interaction)?;
                    if let Err(error) =
                        pending
                            .handle
                            .ensure(login, route, (self.interactive.clock)())
                    {
                        pending.handle.consume();
                        context.routes[index].error = Some(safe_interactive_error(&error));
                        continue;
                    }
                    pending.handle.consume();
                    let clock = Arc::clone(&self.interactive.clock);
                    let (runtime, auth) = self.route_parts_for(route);
                    runtime.set_interactive_login_scope(Some(login.clone()));
                    let result = auth
                        .submit_image_answer(
                            runtime,
                            credentials,
                            &pending.page,
                            answer.answer.expose_secret(),
                            || pending.handle.ensure_scope(login, route, clock()),
                        )
                        .await;
                    runtime.set_interactive_login_scope(None);
                    self.ensure_interactive_active(login)?;
                    match result {
                        Ok(InteractiveSubmission::Complete(profile)) => {
                            self.record_interactive_profile(&mut context, index, profile)?;
                        }
                        Ok(InteractiveSubmission::Reprepared(page)) => {
                            frames[index] = self
                                .apply_interactive_preparation(&mut context, index, page)
                                .await?;
                        }
                        Err(error) => {
                            context.routes[index].error = Some(safe_interactive_error(&error));
                        }
                    }
                }
                InteractiveRouteState::Ready | InteractiveRouteState::Failed => {}
            }
        }
        self.finish_interactive(context, frames)
    }

    fn collect_interactive_answers(
        &self,
        login: &InteractiveLoginHandle,
        answers: Vec<CaptchaAnswer>,
    ) -> Result<[Option<CaptchaAnswer>; 2]> {
        let context = self
            .interactive
            .context
            .as_ref()
            .ok_or_else(invalid_interaction)?;
        let mut supplied: [Option<CaptchaAnswer>; 2] = [None, None];
        for answer in answers {
            let index = route_index(answer.challenge.route());
            answer
                .challenge
                .ensure(login, route_at(index), (self.interactive.clock)())?;
            let pending = context.routes[index]
                .pending
                .as_ref()
                .ok_or_else(invalid_interaction)?;
            if supplied[index].is_some() || !pending.handle.same(&answer.challenge) {
                return Err(invalid_interaction());
            }
            supplied[index] = Some(answer);
        }
        Ok(supplied)
    }

    /// 点击刷新仅重跑当前路线的已证 GET，不保留旧答案或重发凭据。
    ///
    /// # Errors
    ///
    /// 交互已失效、会话冲突或刷新已完成路线时在网络前拒绝。
    pub async fn refresh_interactive_captcha(
        &mut self,
        login: &InteractiveLoginHandle,
        route: ConnectionMode,
    ) -> Result<InteractiveLoginOutcome> {
        self.ensure_interactive(login)?;
        let index = route_index(route);
        if self
            .interactive
            .context
            .as_ref()
            .ok_or_else(invalid_interaction)?
            .routes[index]
            .state
            == InteractiveRouteState::Ready
        {
            return Err(invalid_interaction());
        }
        let mut context = self
            .interactive
            .context
            .take()
            .ok_or_else(invalid_interaction)?;
        if let Some(old) = context.routes[index].pending.take() {
            old.handle.consume();
        }
        let mut frames = [None, None];
        frames[index] = self.prepare_interactive_route(&mut context, index).await?;
        self.finish_interactive(context, frames)
    }

    /// 用户明确选择就绪路线后结束交互；只按需原子保存策略，不重开 Core。
    ///
    /// # Errors
    ///
    /// 零就绪、选中未就绪路线、会话失效或配置保存失败时保留可恢复交互并失败。
    pub fn continue_interactive_login(
        &mut self,
        login: &InteractiveLoginHandle,
        selected_route: ConnectionMode,
        pin_ready_route: bool,
    ) -> Result<LoginOutcome> {
        self.ensure_interactive(login)?;
        let context = self
            .interactive
            .context
            .as_ref()
            .ok_or_else(invalid_interaction)?;
        if context.routes[route_index(selected_route)].state != InteractiveRouteState::Ready
            || !self.active_routes().contains(&selected_route)
        {
            return Err(invalid_interaction());
        }
        let state = context.outcome([None, None], (self.interactive.clock)());
        if self.default_route_policy() == RoutePolicy::Auto && !pin_ready_route {
            self.resolve_operation(super::types::Operation::User)
                .map_err(|failure| failure.error)?;
        }
        self.ensure_interactive_active(login)?;
        let outcome = LoginOutcome {
            readiness: state.readiness,
            routes: state.routes.map(|route| RouteLoginResult {
                route: route.route,
                state: if route.state == InteractiveRouteState::Ready {
                    RouteLoginState::Ready
                } else {
                    RouteLoginState::Failed
                },
                error: route.error,
            }),
            profile: state.profile,
        };
        let required_policy = if pin_ready_route {
            let fixed = match selected_route {
                ConnectionMode::Direct => RoutePolicy::Direct,
                ConnectionMode::WebVpn => RoutePolicy::WebVpn,
            };
            (self.default_route_policy() != fixed).then_some(fixed)
        } else {
            match (self.default_route_policy(), selected_route) {
                (RoutePolicy::Direct, ConnectionMode::WebVpn) => Some(RoutePolicy::WebVpn),
                (RoutePolicy::WebVpn, ConnectionMode::Direct) => Some(RoutePolicy::Direct),
                _ => None,
            }
        };
        if let Some(policy) = required_policy {
            self.set_default_route_policy(policy)?;
        }
        self.clear_interactive_context();
        Ok(outcome)
    }

    fn ensure_interactive(&mut self, login: &InteractiveLoginHandle) -> Result<()> {
        login.ensure_owner(&self.interactive.cancellation)?;
        let current = self
            .interactive
            .context
            .as_ref()
            .ok_or_else(invalid_interaction)?;
        if !current.login.same(login) {
            return Err(invalid_interaction());
        }
        self.guard_latest_session_ownership()?;
        login.ensure_active()
    }

    async fn prepare_interactive_route(
        &mut self,
        context: &mut InteractiveContext,
        index: usize,
    ) -> Result<Option<CaptchaFrame>> {
        let (runtime, auth) = self.route_parts_for(route_at(index));
        runtime.set_interactive_login_scope(Some(context.login.clone()));
        let result = auth.prepare_interactive(runtime).await;
        runtime.set_interactive_login_scope(None);
        self.ensure_interactive_active(&context.login)?;
        match result {
            Ok(page) => {
                self.apply_interactive_preparation(context, index, page)
                    .await
            }
            Err(error) => {
                // 已要求验证码的刷新失败不能降级为普通登录或恢复旧挑战。
                if context.routes[index].state != InteractiveRouteState::CaptchaRequired {
                    context.routes[index].state = InteractiveRouteState::Failed;
                }
                context.routes[index].error = Some(safe_interactive_error(&error));
                Ok(None)
            }
        }
    }

    async fn apply_interactive_preparation(
        &mut self,
        context: &mut InteractiveContext,
        index: usize,
        page: InteractivePreparation,
    ) -> Result<Option<CaptchaFrame>> {
        context.routes[index].error = None;
        context.routes[index].pending = None;
        match page {
            InteractivePreparation::Plain => {
                context.routes[index].state = InteractiveRouteState::Prepared;
            }
            InteractivePreparation::Ready(profile) => {
                self.record_interactive_profile(context, index, profile)?;
            }
            InteractivePreparation::Image(page) => {
                context.routes[index].state = InteractiveRouteState::CaptchaRequired;
                self.interactive.next_challenge += 1;
                let handle = CaptchaChallenge::new(
                    context.login.clone(),
                    route_at(index),
                    self.interactive.next_challenge,
                    (self.interactive.clock)(),
                );
                let runtime = self.runtime_for(route_at(index));
                runtime.set_interactive_login_scope(Some(context.login.clone()));
                let result = image::fetch_captcha_frame(runtime, &page.id).await;
                runtime.set_interactive_login_scope(None);
                self.ensure_interactive_active(&context.login)?;
                match result {
                    Ok(frame) => {
                        if let Err(error) = handle.ensure(
                            &context.login,
                            route_at(index),
                            (self.interactive.clock)(),
                        ) {
                            handle.consume();
                            context.routes[index].error = Some(safe_interactive_error(&error));
                            return Ok(None);
                        }
                        context.routes[index].pending = Some(PendingCaptcha { handle, page });
                        return Ok(Some(frame));
                    }
                    Err(error) => {
                        handle.consume();
                        context.routes[index].error = Some(safe_interactive_error(&error));
                    }
                }
            }
        }
        Ok(None)
    }

    fn record_interactive_profile(
        &mut self,
        context: &mut InteractiveContext,
        index: usize,
        profile: UserProfile,
    ) -> Result<()> {
        let username = context.login.username();
        if profile.username.as_deref() != Some(username)
            && profile.school_id.as_deref() != Some(username)
        {
            let (runtime, auth) = self.route_parts_for(route_at(index));
            runtime.clear_with(|| auth.clear())?;
            context.routes[index].state = InteractiveRouteState::Failed;
            context.routes[index].error = Some(safe_interactive_error(&UbaaError::new(
                ErrorCode::UpstreamChanged,
                ErrorKind::Upstream,
                false,
                "认证资料与当前账号不一致",
            )));
            return Ok(());
        }
        context.routes[index].state = InteractiveRouteState::Ready;
        context.routes[index].pending = None;
        context.routes[index].error = None;
        context.routes[index].profile = Some(profile);
        Ok(())
    }

    fn finish_interactive(
        &mut self,
        mut context: InteractiveContext,
        mut frames: [Option<CaptchaFrame>; 2],
    ) -> Result<InteractiveLoginOutcome> {
        self.guard_latest_session_ownership()?;
        context.login.ensure_owner(&self.interactive.cancellation)?;
        let now = (self.interactive.clock)();
        for (index, stored) in context.routes.iter_mut().enumerate() {
            if stored.pending.as_ref().is_some_and(|pending| {
                pending
                    .handle
                    .ensure(&context.login, route_at(index), now)
                    .is_err()
            }) {
                if let Some(pending) = stored.pending.take() {
                    pending.handle.consume();
                }
                frames[index] = None;
                stored.error = Some(safe_interactive_error(&invalid_interaction()));
            }
        }
        let outcome = context.outcome(frames, now);
        self.interactive.context = Some(context);
        Ok(outcome)
    }

    pub(super) fn clear_interactive_context(&mut self) {
        self.interactive.cancellation.cancel();
        let had_login = self.interactive.current_login.take().is_some();
        if self.interactive.context.take().is_some() || had_login {
            self.direct_auth.clear();
            self.webvpn_auth.clear();
        }
    }

    /// 在空闲或异步返回后释放已经撤销的 Core 准备状态；不发网络请求。
    pub fn discard_cancelled_interactive_login(&mut self) {
        if self
            .interactive
            .current_login
            .as_ref()
            .is_some_and(|login| !login.is_active())
        {
            // 先确认修订再清 pending，不能让旧实例误走普通入口的空会话同步分支。
            let _ = self.guard_latest_session_ownership();
            self.clear_interactive_context();
        }
    }

    fn ensure_interactive_active(&mut self, login: &InteractiveLoginHandle) -> Result<()> {
        let result = login.ensure_active();
        self.discard_cancelled_interactive_login();
        result
    }

    /// 测试专用单调时钟注入，生产构造器始终使用 Instant。
    #[cfg(feature = "test-contract")]
    #[doc(hidden)]
    pub fn set_interactive_clock(
        &mut self,
        clock: Arc<dyn Fn() -> std::time::Instant + Send + Sync>,
    ) {
        self.interactive.clock = clock;
    }
}
