//! 单次所需路线恢复的单调期限与取消控制。

use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};
use std::time::{Duration, Instant};

/// 一次恢复调用的单调期限与取消信号，最长两分钟。
#[derive(Clone)]
pub struct RequiredRecoveryControl(Arc<ControlState>);

struct ControlState {
    deadline: Instant,
    cancelled: tokio::sync::watch::Sender<bool>,
    claimed: AtomicBool,
}

/// 已取得的单次调用资格；不能复制或交给第二个调用。
pub struct RequiredRecoveryOperation {
    pub(crate) control: RequiredRecoveryControl,
}

/// 本机恢复中断的原因，不扩大全局学校错误码。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RequiredRecoveryInterruption {
    Cancelled,
    Deadline,
}

impl std::fmt::Debug for RequiredRecoveryControl {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("RequiredRecoveryControl")
    }
}

impl std::fmt::Debug for RequiredRecoveryOperation {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("RequiredRecoveryOperation")
    }
}

impl RequiredRecoveryControl {
    /// 从当前单调时钟计算期限。零时长立即到期。
    ///
    /// # Errors
    /// 超过两分钟时拒绝，调用方需要为下一次独立操作新建控制柄。
    pub fn new(timeout: Duration) -> Result<Self> {
        if timeout > Duration::from_mins(2) {
            return Err(UbaaError::new(
                ErrorCode::InvalidInput,
                ErrorKind::Input,
                false,
                "恢复期限不能超过两分钟",
            ));
        }
        let (cancelled, _) = tokio::sync::watch::channel(false);
        Ok(Self(Arc::new(ControlState {
            deadline: Instant::now() + timeout,
            cancelled,
            claimed: AtomicBool::new(false),
        })))
    }

    /// 立即撤销本次操作，不等待客户端网络锁，也不注销共享会话。
    pub fn cancel(&self) {
        self.0.cancelled.send_replace(true);
    }

    /// 取得唯一调用资格。Bridge 必须在排队获取客户端之前取得资格。
    ///
    /// # Errors
    /// 已取消、已到期或重复使用时拒绝。
    pub fn claim(&self) -> Result<RequiredRecoveryOperation> {
        self.check()?;
        self.0
            .claimed
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
            .map_err(|_| conflict("恢复控制柄已经使用"))?;
        Ok(RequiredRecoveryOperation {
            control: self.clone(),
        })
    }

    /// 在发送和交付的同步边界再次核对，不能仅依赖异步定时器。
    ///
    /// # Errors
    /// 取消返回本机输入错误，由 `interruption_reason` 区分；到期返回不可自动重试的超时。
    pub fn check(&self) -> Result<()> {
        match self.interruption_reason() {
            Some(RequiredRecoveryInterruption::Cancelled) => return Err(conflict("恢复已取消")),
            Some(RequiredRecoveryInterruption::Deadline) => return Err(expired()),
            None => {}
        }
        Ok(())
    }

    /// 返回可信的本机控制原因，绑定层不从错误文案推断取消。
    #[must_use]
    pub fn interruption_reason(&self) -> Option<RequiredRecoveryInterruption> {
        if *self.0.cancelled.borrow() {
            Some(RequiredRecoveryInterruption::Cancelled)
        } else if Instant::now() >= self.0.deadline {
            Some(RequiredRecoveryInterruption::Deadline)
        } else {
            None
        }
    }

    /// 等待取消或期限。允许在客户端锁排队期间监听同一信号。
    pub async fn interrupted(&self) -> UbaaError {
        let mut cancelled = self.0.cancelled.subscribe();
        if let Err(error) = self.check() {
            return error;
        }
        tokio::select! {
            biased;
            _ = cancelled.changed() => conflict("恢复已取消"),
            () = tokio::time::sleep_until(self.0.deadline.into()) => expired(),
        }
    }
}

fn conflict(message: &str) -> UbaaError {
    UbaaError::new(ErrorCode::InternalError, ErrorKind::Input, false, message)
}

fn expired() -> UbaaError {
    UbaaError::new(
        ErrorCode::Timeout,
        ErrorKind::Network,
        false,
        "恢复期限已到",
    )
}
