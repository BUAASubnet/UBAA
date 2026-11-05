use super::{BridgeAgendaError, BridgeAgendaStore, error, task};

impl BridgeAgendaStore {
    /// 读取本机账号已保存的 GUI 自动同步许可，不访问云盘。
    /// # Errors
    /// 账号失效或本机存储不可用时返回日程错误。
    pub async fn sync_enabled(&self) -> Result<bool, BridgeAgendaError> {
        let store = self.store.clone();
        task(move || store.sync_enabled().map_err(error)).await
    }
}
