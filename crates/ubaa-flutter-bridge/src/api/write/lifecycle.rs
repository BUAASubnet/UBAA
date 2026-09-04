//! 待确认写入意图的显式生命周期操作。

use super::support::invalid_input;
use crate::api::client::{BridgeClient, BridgeError, catch_panic, disposed_error};

impl BridgeClient {
    /// 放弃一个尚未提交的写入意图。
    ///
    /// 已不存在的标识按幂等成功处理；已经进入 commit 的请求不会被异步中断。
    pub async fn discard_write_intent(&self, intent_id: String) -> Result<(), BridgeError> {
        if intent_id.trim().is_empty() {
            return Err(invalid_input("intent id is required"));
        }
        catch_panic(async {
            // 与 commit、登录和路线重建保持相同的锁顺序，避免取消和提交交错。
            let guard = self.inner.lock().await;
            guard.as_ref().ok_or_else(disposed_error)?;
            self.write_intents.lock().await.remove(&intent_id);
            Ok(())
        })
        .await
    }
}
