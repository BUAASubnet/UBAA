use std::{
    future::Future,
    sync::{Arc, OnceLock},
    time::{Duration, Instant},
};
use tokio::sync::Notify;
/// 停止原因只投影到既有 v13 错误，不增加取消退出码。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum StopReason {
    Cancelled,
    Deadline,
}
impl StopReason {
    #[must_use]
    pub const fn message(self) -> &'static str {
        match self {
            Self::Cancelled => "命令已取消",
            Self::Deadline => "命令总期限已到达",
        }
    }
}
#[derive(Clone)]
pub struct CommandControl {
    deadline: Instant,
    cancelled: Arc<OnceLock<Instant>>,
    notify: Arc<Notify>,
}
impl Default for CommandControl {
    fn default() -> Self {
        Self::new(Instant::now(), Duration::from_mins(2))
    }
}
impl CommandControl {
    /// 起点由宿主尽早捕获，所有阶段共用同一个单调期限。
    #[must_use]
    pub fn new(start: Instant, budget: Duration) -> Self {
        Self {
            deadline: start + budget.min(Duration::from_mins(2)),
            cancelled: Arc::default(),
            notify: Arc::default(),
        }
    }
    pub fn cancel(&self) {
        self.cancelled.get_or_init(Instant::now);
        self.notify.notify_waiters();
    }
    /// # Errors
    /// 返回取消或期限到达。
    pub fn check(&self) -> Result<(), StopReason> {
        if self.cancelled.get().is_some_and(|at| *at < self.deadline) {
            Err(StopReason::Cancelled)
        } else if Instant::now() >= self.deadline {
            Err(StopReason::Deadline)
        } else {
            Ok(())
        }
    }
    pub(crate) fn cleanup(&self) -> Self {
        let mut cleanup = Self::new(Instant::now(), Duration::from_secs(2));
        let stopped = self
            .cancelled
            .get()
            .copied()
            .unwrap_or(self.deadline)
            .min(self.deadline);
        cleanup.deadline = cleanup.deadline.min(stopped + Duration::from_secs(2));
        cleanup
    }
    pub(crate) fn earlier(&self, other: &Self) -> Self {
        if self.deadline <= other.deadline {
            self.clone()
        } else {
            other.clone()
        }
    }
    pub(crate) async fn run<T>(&self, work: impl Future<Output = T>) -> Result<T, StopReason> {
        let cancelled = self.notify.notified();
        tokio::pin!(cancelled);
        cancelled.as_mut().enable();
        self.check()?;
        tokio::select! { biased;
            () = cancelled => Err(self.check().err().unwrap_or(StopReason::Cancelled)),
            () = tokio::time::sleep_until(self.deadline.into()) => Err(StopReason::Deadline),
            value = work => { self.check()?; Ok(value) }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]
    async fn 取消会丢弃在途等待且拒绝迟到结果() {
        let control = CommandControl::default();
        let cancel = control.clone();
        let ready = Arc::new(Notify::new());
        let cancel_ready = ready.clone();
        let task = tokio::spawn(async move {
            cancel_ready.notified().await;
            cancel.cancel();
        });
        let result = control
            .run(async move {
                ready.notify_one();
                std::future::pending::<()>().await;
            })
            .await;
        assert_eq!(result, Err(StopReason::Cancelled));
        task.await.unwrap();
    }
    #[tokio::test]
    async fn 各阶段沿用同一期限且不重新计时() {
        let control = CommandControl::new(Instant::now(), Duration::from_millis(30));
        control.run(async {}).await.unwrap();
        let result = control.run(std::future::pending::<()>()).await;
        assert_eq!(result, Err(StopReason::Deadline));
        assert_eq!(control.run(async {}).await, Err(StopReason::Deadline));
    }
    #[test]
    fn 取消后的收尾不会因延迟处理重新获得两秒() {
        let control = CommandControl::default();
        control
            .cancelled
            .set(Instant::now().checked_sub(Duration::from_secs(3)).unwrap())
            .unwrap();
        assert_eq!(control.cleanup().check(), Err(StopReason::Deadline));
    }
}
