use super::{BhpanTransferPhase, BhpanTransferProgress};
use crate::error::{Result, UbaaError};
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, Ordering},
};

/// 文件任务的本进程进度与取消控制。取消不会向学校发送回滚请求。
#[derive(Clone)]
pub struct BhpanTransfer {
    progress: Arc<Mutex<BhpanTransferProgress>>,
    cancelled: Arc<AtomicBool>,
    cancelled_signal: tokio::sync::watch::Sender<bool>,
    claimed: Arc<AtomicBool>,
}
impl Default for BhpanTransfer {
    fn default() -> Self {
        Self {
            progress: Arc::new(Mutex::new(BhpanTransferProgress {
                phase: BhpanTransferPhase::Queued,
                bytes: 0,
                total: 0,
            })),
            cancelled: Arc::new(AtomicBool::new(false)),
            cancelled_signal: tokio::sync::watch::channel(false).0,
            claimed: Arc::new(AtomicBool::new(false)),
        }
    }
}
impl BhpanTransfer {
    /// 创建尚未发送请求的任务。
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }
    /// 返回不含文件内容或授权的进度。
    #[must_use]
    pub fn progress(&self) -> BhpanTransferProgress {
        self.progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }
    /// 停止尚未发送的阶段。已发送阶段仍可能产生远端结果。
    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Release);
        self.cancelled_signal.send_replace(true);
        let mut p = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        p.phase = match p.phase {
            BhpanTransferPhase::Completed
            | BhpanTransferPhase::Failed
            | BhpanTransferPhase::Blocked
            | BhpanTransferPhase::OutcomeUnknown => p.phase,
            BhpanTransferPhase::Submitting
            | BhpanTransferPhase::Uploading
            | BhpanTransferPhase::Finalizing => BhpanTransferPhase::OutcomeUnknown,
            _ => BhpanTransferPhase::Cancelled,
        };
    }
    /// 等待控制柄的取消信号，最终结果继续由操作结果和终态表达。
    pub async fn cancelled(&self) -> UbaaError {
        let mut signal = self.cancelled_signal.subscribe();
        if let Err(error) = self.ensure_active() {
            return error;
        }
        let _ = signal.changed().await;
        UbaaError::invalid_input("文件任务已取消")
    }
    pub(crate) fn set_total(&self, total: u64) {
        let mut progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if progress.total == 0 {
            progress.total = total;
        }
    }
    pub(crate) fn claim(&self) -> Result<()> {
        self.ensure_active()?;
        self.claimed
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
            .map_err(|_| UbaaError::invalid_input("文件任务已使用，请为新操作创建任务"))?;
        Ok(())
    }
    pub(crate) fn ensure_active(&self) -> Result<()> {
        if self.cancelled.load(Ordering::Acquire) {
            Err(UbaaError::invalid_input(
                "文件任务已取消，已发送阶段的远端结果需另行核对",
            ))
        } else {
            Ok(())
        }
    }
    pub(crate) fn set(&self, phase: BhpanTransferPhase, bytes: u64, total: u64) {
        let mut progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if self.cancelled.load(Ordering::Acquire)
            && !matches!(
                phase,
                BhpanTransferPhase::Completed
                    | BhpanTransferPhase::OutcomeUnknown
                    | BhpanTransferPhase::Failed
                    | BhpanTransferPhase::Blocked
            )
        {
            return;
        }
        *progress = BhpanTransferProgress {
            phase,
            bytes,
            total,
        };
    }
    pub(crate) fn advance(&self, bytes: u64) {
        let mut p = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        p.bytes = p.bytes.saturating_add(bytes);
        if p.total > 0 {
            p.bytes = p.bytes.min(p.total);
        }
    }
}
