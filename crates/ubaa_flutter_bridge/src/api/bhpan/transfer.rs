use super::models::BridgeBhpanDownloadReceipt;
use super::{
    BridgeBhpanPrepared, BridgeBhpanTransfer, BridgeClient, BridgeError, catch_panic,
    disposed_error, error,
};
impl BridgeClient {
    /// 普通或分片上传共用一次性写确认，文件字节留在 Core。
    pub async fn bhpan_prepare_upload(
        &self,
        parent: String,
        path: String,
        name: String,
        transfer: &BridgeBhpanTransfer,
    ) -> Result<BridgeBhpanPrepared, BridgeError> {
        self.register_bhpan_transfer(transfer.control.clone())?;
        catch_panic(async {
            let mut guard=tokio::select! {
                biased;
                interruption=transfer.control.cancelled()=>return Err(if self.is_disposed.load(std::sync::atomic::Ordering::SeqCst){disposed_error()}else{error(interruption)}),
                guard=self.inner.lock()=>guard,
            };
            if self.is_disposed.load(std::sync::atomic::Ordering::SeqCst) {
                return Err(disposed_error());
            }
            let p = guard
                .as_mut()
                .ok_or_else(disposed_error)?
                .bhpan_prepare_upload(&parent, path.into(), &name, transfer.control.clone())
                .await
                .map_err(error)?;
            Ok(BridgeBhpanPrepared {
                handle: p.handle,
                description: p.description,
                route: p.route.into(),
            })
        })
        .await
    }
    /// 完整下载到宿主选定文件，签名地址和授权头不跨过 Bridge。
    pub async fn bhpan_download(
        &self,
        handles: Vec<String>,
        name: String,
        path: String,
        overwrite: bool,
        transfer: &BridgeBhpanTransfer,
    ) -> Result<BridgeBhpanDownloadReceipt, BridgeError> {
        self.register_bhpan_transfer(transfer.control.clone())?;
        catch_panic(async {
            let mut guard=tokio::select! {
                biased;
                interruption=transfer.control.cancelled()=>return Err(if self.is_disposed.load(std::sync::atomic::Ordering::SeqCst){disposed_error()}else{error(interruption)}),
                guard=self.inner.lock()=>guard,
            };
            if self.is_disposed.load(std::sync::atomic::Ordering::SeqCst) {
                return Err(disposed_error());
            }
            let receipt = guard
                .as_mut()
                .ok_or_else(disposed_error)?
                .bhpan_download(
                    &handles,
                    &name,
                    path.into(),
                    overwrite,
                    transfer.control.clone(),
                )
                .await
                .map_err(error)?;
            Ok(BridgeBhpanDownloadReceipt {
                bytes: receipt.bytes,
                batch: receipt.batch,
            })
        })
        .await
    }
}
