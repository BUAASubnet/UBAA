//! 单次提交的发送观察独立于运行时收尾，panic 展开不能擦掉已发送事实。
use super::UbaaClient;
use crate::domain::ConnectionMode;
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};

/// 只报告请求是否交给传输层，不提供写入或会话权限。
pub struct WriteBoundaryObservation {
    signal: Arc<AtomicBool>,
}
impl WriteBoundaryObservation {
    /// 请求可能已被上游处理；不能据此推断成功或允许重放。
    #[must_use]
    pub fn may_have_been_sent(&self) -> bool {
        self.signal.load(Ordering::SeqCst)
    }
}

impl UbaaClient {
    /// 观察下一次宿主提交中的两条路线；丢弃观察者后不保留跨操作信号。
    pub fn observe_write_boundary(&mut self) -> WriteBoundaryObservation {
        let signal = Arc::new(AtomicBool::new(false));
        for route in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
            self.runtime_for(route)
                .observe_write_boundary(Arc::downgrade(&signal));
        }
        WriteBoundaryObservation { signal }
    }
}
