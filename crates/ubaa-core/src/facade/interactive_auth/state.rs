//! 交互流程内部状态；不保留密码、答案或已返回的像素。

use std::sync::Arc;
use std::time::Instant;

use crate::domain::{
    CaptchaChallenge, CaptchaFrame, ConnectionMode, InteractiveLoginCancellation,
    InteractiveLoginHandle, InteractiveLoginOutcome, InteractiveRouteResult, InteractiveRouteState,
    LoginReadiness, SafeError, UserProfile,
};
use crate::error::UbaaError;
use crate::upstream::interactive_auth::ImageCaptchaPage;

pub(crate) struct InteractiveAuthState {
    pub(crate) cancellation: InteractiveLoginCancellation,
    pub(crate) context: Option<InteractiveContext>,
    pub(crate) current_login: Option<InteractiveLoginHandle>,
    pub(crate) clock: Arc<dyn Fn() -> Instant + Send + Sync>,
    pub(crate) next_challenge: u64,
}

impl Default for InteractiveAuthState {
    fn default() -> Self {
        Self {
            cancellation: InteractiveLoginCancellation::default(),
            context: None,
            current_login: None,
            clock: Arc::new(Instant::now),
            next_challenge: 0,
        }
    }
}

pub(crate) struct PendingCaptcha {
    pub(crate) handle: CaptchaChallenge,
    pub(crate) page: ImageCaptchaPage,
}

pub(crate) struct StoredRoute {
    pub(crate) state: InteractiveRouteState,
    pub(crate) pending: Option<PendingCaptcha>,
    pub(crate) error: Option<SafeError>,
    pub(crate) profile: Option<UserProfile>,
}

impl Default for StoredRoute {
    fn default() -> Self {
        Self {
            state: InteractiveRouteState::Failed,
            pending: None,
            error: None,
            profile: None,
        }
    }
}

pub(crate) struct InteractiveContext {
    pub(crate) login: InteractiveLoginHandle,
    pub(crate) routes: [StoredRoute; 2],
}

impl InteractiveContext {
    pub(crate) fn outcome(
        &self,
        mut frames: [Option<CaptchaFrame>; 2],
        now: Instant,
    ) -> InteractiveLoginOutcome {
        let ready = self
            .routes
            .iter()
            .filter(|route| route.state == InteractiveRouteState::Ready)
            .count();
        InteractiveLoginOutcome {
            login: self.login.clone(),
            routes: std::array::from_fn(|index| InteractiveRouteResult {
                route: route_at(index),
                state: self.routes[index].state,
                challenge: self.routes[index]
                    .pending
                    .as_ref()
                    .map(|pending| pending.handle.clone()),
                valid_for_millis: self.routes[index]
                    .pending
                    .as_ref()
                    .map_or(0, |pending| pending.handle.remaining_millis(now)),
                frame: frames[index].take(),
                error: self.routes[index].error.clone(),
            }),
            readiness: match ready {
                2 => LoginReadiness::AllReady,
                1 => LoginReadiness::Partial,
                _ => LoginReadiness::NoneReady,
            },
            profile: self.routes.iter().find_map(|route| route.profile.clone()),
        }
    }
}

pub(super) const fn route_at(index: usize) -> ConnectionMode {
    if index == 0 {
        ConnectionMode::Direct
    } else {
        ConnectionMode::WebVpn
    }
}

pub(super) const fn route_index(route: ConnectionMode) -> usize {
    match route {
        ConnectionMode::Direct => 0,
        ConnectionMode::WebVpn => 1,
    }
}

pub(super) fn safe_interactive_error(error: &UbaaError) -> SafeError {
    let mut safe = super::super::auth::safe_error(error);
    // 不保留上游认证错误文本，防止其中回显答案、execution 或完整 HTML。
    safe.message = "此路线的登录验证未完成，请重试".into();
    safe
}
