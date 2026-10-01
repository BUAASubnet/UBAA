//! 只供当前登录页面使用的非持久化交互类型。

use std::fmt;
use std::sync::{
    Arc,
    atomic::{AtomicBool, AtomicU64, Ordering},
};
use std::time::{Duration, Instant};

use super::{ConnectionMode, LoginReadiness, SafeError, SecretValue, UserProfile};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

/// 可在网络操作之外立即撤销当前交互的控制柄。
#[derive(Clone, Default)]
pub struct InteractiveLoginCancellation(pub(crate) Arc<AtomicU64>);

impl InteractiveLoginCancellation {
    /// 同步撤销句柄；不等待网络锁，也不擦除系统内存。
    pub fn cancel(&self) {
        self.0.fetch_add(1, Ordering::SeqCst);
    }

    /// 先登记当前页面的新登录意图，排队后的准备不能越过随后发生的取消。
    ///
    /// # Errors
    ///
    /// 账号为空时拒绝创建上下文。
    pub fn begin(&self, username: &str) -> Result<InteractiveLoginHandle> {
        let username = username.trim().to_owned();
        if username.is_empty() {
            return Err(invalid_interaction());
        }
        let generation = self.0.fetch_add(1, Ordering::SeqCst).wrapping_add(1);
        Ok(InteractiveLoginHandle(Arc::new(InteractiveLoginLease {
            cancellation: self.clone(),
            generation,
            username,
            started: AtomicBool::new(false),
        })))
    }
}

impl fmt::Debug for InteractiveLoginCancellation {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("InteractiveLoginCancellation")
    }
}

struct InteractiveLoginLease {
    cancellation: InteractiveLoginCancellation,
    generation: u64,
    username: String,
    started: AtomicBool,
}

/// Core 生成的登录上下文，不能由宿主构造或序列化。
#[derive(Clone)]
pub struct InteractiveLoginHandle(Arc<InteractiveLoginLease>);

impl InteractiveLoginHandle {
    /// 仅返回本地撤销状态，不读取或暴露账号与服务器材料。
    #[must_use]
    pub fn is_active(&self) -> bool {
        self.ensure_active().is_ok()
    }
    pub(crate) fn claim_preparation(&self) -> Result<()> {
        self.ensure_active()?;
        self.0
            .started
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
            .map_err(|_| invalid_interaction())?;
        Ok(())
    }
    pub(crate) fn ensure_active(&self) -> Result<()> {
        if self.0.generation != self.0.cancellation.0.load(Ordering::SeqCst) {
            return Err(invalid_interaction());
        }
        Ok(())
    }

    pub(crate) fn ensure_owner(&self, control: &InteractiveLoginCancellation) -> Result<()> {
        if !Arc::ptr_eq(&self.0.cancellation.0, &control.0) {
            return Err(invalid_interaction());
        }
        self.ensure_active()
    }

    pub(crate) fn same(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.0, &other.0)
    }

    pub(crate) fn username(&self) -> &str {
        &self.0.username
    }
}

impl fmt::Debug for InteractiveLoginHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("InteractiveLoginHandle([OPAQUE])")
    }
}

struct CaptchaLease {
    login: InteractiveLoginHandle,
    route: ConnectionMode,
    revision: u64,
    expires_at: Instant,
    consumed: AtomicBool,
}

/// 路线内的一次性挑战；不包含宿主可读的上游 id、execution 或地址。
#[derive(Clone)]
pub struct CaptchaChallenge(Arc<CaptchaLease>);

impl CaptchaChallenge {
    /// 仅撤销这个路线的挑战，不影响另一条已就绪路线。
    pub fn cancel(&self) {
        self.consume();
    }
    pub(crate) fn new(
        login: InteractiveLoginHandle,
        route: ConnectionMode,
        revision: u64,
        now: Instant,
    ) -> Self {
        Self(Arc::new(CaptchaLease {
            login,
            route,
            revision,
            expires_at: now + Duration::from_mins(2),
            consumed: AtomicBool::new(false),
        }))
    }

    /// 本地替换代次，仅供当前页面释放旧帧；不是上游挑战标识。
    #[must_use]
    pub fn revision(&self) -> u64 {
        self.0.revision
    }

    pub(crate) fn remaining_millis(&self, now: Instant) -> u32 {
        u32::try_from(self.0.expires_at.saturating_duration_since(now).as_millis())
            .unwrap_or(120_000)
    }

    pub(crate) fn same(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.0, &other.0)
    }

    pub(crate) fn route(&self) -> ConnectionMode {
        self.0.route
    }

    pub(crate) fn ensure(
        &self,
        login: &InteractiveLoginHandle,
        route: ConnectionMode,
        now: Instant,
    ) -> Result<()> {
        self.ensure_scope(login, route, now)?;
        if self.0.consumed.load(Ordering::SeqCst) {
            return Err(invalid_interaction());
        }
        Ok(())
    }

    pub(crate) fn consume(&self) {
        self.0.consumed.store(true, Ordering::SeqCst);
    }

    pub(crate) fn ensure_scope(
        &self,
        login: &InteractiveLoginHandle,
        route: ConnectionMode,
        now: Instant,
    ) -> Result<()> {
        self.0.login.ensure_active()?;
        if !self.0.login.same(login) || self.0.route != route || now >= self.0.expires_at {
            return Err(invalid_interaction());
        }
        Ok(())
    }
}

impl fmt::Debug for CaptchaChallenge {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("CaptchaChallenge([OPAQUE])")
    }
}

/// 答案只属于这一次带句柄的提交；不进入通用 `LoginInput` 或 JSON。
#[derive(Debug)]
pub struct CaptchaAnswer {
    pub challenge: CaptchaChallenge,
    pub answer: SecretValue,
}

pub(crate) fn invalid_interaction() -> UbaaError {
    UbaaError::new(
        ErrorCode::InvalidInput,
        ErrorKind::Input,
        false,
        "当前验证已失效，请重新准备",
    )
}

/// 已通过资源约束的 RGBA 像素帧，不参与任何序列化。
///
/// ```compile_fail
/// use ubaa_core::facade::CaptchaFrame;
/// let frame = CaptchaFrame { width: 1, height: 1, rgba: vec![0; 4] };
/// serde_json::to_string(&frame).unwrap();
/// ```
pub struct CaptchaFrame {
    pub width: u32,
    pub height: u32,
    pub rgba: Vec<u8>,
}

impl fmt::Debug for CaptchaFrame {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("CaptchaFrame([REDACTED])")
    }
}

/// 与旧非交互状态隔离；准备完成不等于拥有认证会话。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum InteractiveRouteState {
    Prepared,
    CaptchaRequired,
    Ready,
    Failed,
}

/// 当前路线的专用登录结果，不进入普通业务快照或 CLI。
#[derive(Debug)]
pub struct InteractiveRouteResult {
    pub route: ConnectionMode,
    pub state: InteractiveRouteState,
    pub challenge: Option<CaptchaChallenge>,
    pub valid_for_millis: u32,
    pub frame: Option<CaptchaFrame>,
    pub error: Option<SafeError>,
}

/// 两条路线的真实就绪摘要；图片仅属于这次交互返回值。
#[derive(Debug)]
pub struct InteractiveLoginOutcome {
    pub login: InteractiveLoginHandle,
    pub routes: [InteractiveRouteResult; 2],
    pub readiness: LoginReadiness,
    pub profile: Option<UserProfile>,
}
