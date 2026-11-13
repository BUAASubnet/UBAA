//! 换网观察和读取取消无需排队等待客户端锁。
use super::client::{BridgeClient, BridgeError, BridgeNetworkState, disposed_error};
use std::sync::atomic::Ordering;
use std::time::Duration;

/// 一次换网的固定恢复期限，不能结束后续换网任务。
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeNetworkChange {
    inner: ubaa_core::facade::ClientNetworkChange,
}

impl BridgeNetworkChange {
    /// 独立探测当前校园网环境。
    pub async fn inspect(&self) -> BridgeNetworkState {
        self.inner.inspect().await.into()
    }

    /// 本次恢复和原查询完成后解除期限。
    #[flutter_rust_bridge::frb(sync)]
    pub fn finish(&self) {
        self.inner.finish();
    }

    /// 停止本次读取并解除期限，不取消后来的换网任务。
    #[flutter_rust_bridge::frb(sync)]
    pub fn cancel(&self) {
        self.inner.cancel();
    }
}

impl BridgeClient {
    /// 立即更新联网状态，取消旧读取并开始统一的恢复期限。
    /// # Errors
    /// 客户端已关闭或期限超过两分钟时拒绝。
    #[flutter_rust_bridge::frb(sync)]
    pub fn begin_network_change(
        &self,
        online: bool,
        timeout_millis: u32,
    ) -> Result<BridgeNetworkChange, BridgeError> {
        if self.is_disposed.load(Ordering::SeqCst) {
            return Err(disposed_error());
        }
        self.network_control
            .begin_change(online, Duration::from_millis(u64::from(timeout_millis)))
            .map(|inner| BridgeNetworkChange { inner })
            .map_err(|error| BridgeError::from_core(error, None))
    }

    /// 手动切换前同步取消普通读取，已发送写入仍按原结果收尾。
    #[flutter_rust_bridge::frb(sync)]
    pub fn cancel_network_reads(&self) {
        self.network_control.cancel_reads();
    }
}
