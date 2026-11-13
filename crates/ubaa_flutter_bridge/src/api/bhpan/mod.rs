//! 云盘操作借用现有主客户端锁，退出和路线重开会撤销 Core 句柄。
#![allow(clippy::missing_errors_doc)]
pub(crate) mod convert;
pub mod models;
mod transfer;
use crate::api::client::{BridgeClient, BridgeError, catch_panic, disposed_error};
use futures_util::FutureExt;
use models::{
    BridgeBhpanCapabilities, BridgeBhpanDownloadPreparation, BridgeBhpanPage, BridgeBhpanPrepared,
    BridgeBhpanQuery, BridgeBhpanReadView, BridgeBhpanReceipt, BridgeBhpanShare, BridgeBhpanSize,
    BridgeBhpanTransferProgress, BridgeBhpanWrite,
};
use std::panic::AssertUnwindSafe;
use ubaa_core::facade as c;

/// 进度与取消不等待主客户端网络锁。
pub struct BridgeBhpanTransfer {
    control: c::bhpan::BhpanTransfer,
}
impl BridgeBhpanTransfer {
    #[flutter_rust_bridge::frb(sync)]
    #[must_use]
    pub fn new() -> Self {
        Self {
            control: c::bhpan::BhpanTransfer::new(),
        }
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn cancel(&self) {
        self.control.cancel();
    }
    #[flutter_rust_bridge::frb(sync)]
    #[must_use]
    pub fn progress(&self) -> BridgeBhpanTransferProgress {
        convert::progress(&self.control.progress())
    }
}
impl Default for BridgeBhpanTransfer {
    fn default() -> Self {
        Self::new()
    }
}
fn error(e: c::UbaaError) -> BridgeError {
    BridgeError::from_core(e, Some(crate::api::client::BridgeConnectionMode::Direct))
}

impl BridgeClient {
    #[flutter_rust_bridge::frb(ignore)]
    pub(crate) fn cancel_bhpan_transfers(&self) {
        let mut controls = self
            .bhpan_transfers
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        for control in controls.drain(..) {
            control.cancel();
        }
    }
    fn register_bhpan_transfer(&self, control: c::bhpan::BhpanTransfer) -> Result<(), BridgeError> {
        let mut controls = self
            .bhpan_transfers
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if self.is_disposed.load(std::sync::atomic::Ordering::Acquire) {
            return Err(disposed_error());
        }
        controls.retain(|c| {
            !matches!(
                c.progress().phase,
                c::BhpanTransferPhase::Completed
                    | c::BhpanTransferPhase::Cancelled
                    | c::BhpanTransferPhase::Failed
                    | c::BhpanTransferPhase::OutcomeUnknown
                    | c::BhpanTransferPhase::Blocked
            )
        });
        controls.push(control);
        Ok(())
    }

    pub async fn bhpan_download_preparation(
        &self,
        handles: Vec<String>,
        name: String,
    ) -> Result<BridgeBhpanDownloadPreparation, BridgeError> {
        catch_panic(async {
            let mut g = self.inner.lock().await;
            let p = g
                .as_mut()
                .ok_or_else(disposed_error)?
                .bhpan_download_preparation(&handles, &name)
                .await
                .map_err(error)?;
            Ok(BridgeBhpanDownloadPreparation {
                host: p.host,
                port: p.port,
                method: p.method,
                header_names: p.header_names,
                batch: p.batch,
                destination_verified: p.destination_verified,
            })
        })
        .await
    }

    pub async fn bhpan_prepare_fast_upload(
        &self,
        parent: String,
        path: String,
        name: String,
        transfer: &BridgeBhpanTransfer,
    ) -> Result<BridgeBhpanPrepared, BridgeError> {
        self.register_bhpan_transfer(transfer.control.clone())?;
        catch_panic(async {
            let mut g=tokio::select! {
                biased;
                interruption=transfer.control.cancelled()=>return Err(if self.is_disposed.load(std::sync::atomic::Ordering::SeqCst){disposed_error()}else{error(interruption)}),
                guard=self.inner.lock()=>guard,
            };
            let p = g
                .as_mut()
                .ok_or_else(disposed_error)?
                .bhpan_prepare_fast_upload(
                    &parent,
                    std::path::PathBuf::from(path),
                    &name,
                    transfer.control.clone(),
                )
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
    pub async fn bhpan_capabilities(&self) -> Result<BridgeBhpanCapabilities, BridgeError> {
        catch_panic(async {
            let guard = self.inner.lock().await;
            let c = guard
                .as_ref()
                .ok_or_else(disposed_error)?
                .bhpan_capabilities();
            Ok(BridgeBhpanCapabilities {
                direct_metadata: c.direct_metadata.into(),
                fast_upload: c.fast_upload.into(),
                webvpn: c.webvpn.into(),
                object_transfer: c.object_transfer.into(),
                conditional_replace: c.conditional_replace.into(),
                limitations: c.limitations,
            })
        })
        .await
    }
    pub async fn bhpan_login(&self) -> Result<(), BridgeError> {
        self.cancel_bhpan_transfers();
        catch_panic(async {
            let mut g = self.inner.lock().await;
            let client = g.as_mut().ok_or_else(disposed_error)?;
            client
                .network_control()
                .run_read(c::ConnectionMode::Direct, false, client.bhpan_login())
                .await
                .map_err(error)
        })
        .await
    }
    pub async fn bhpan_read(
        &self,
        query: BridgeBhpanQuery,
    ) -> Result<BridgeBhpanPage, BridgeError> {
        catch_panic(async {
            let mut g = self.inner.lock().await;
            let client = g.as_mut().ok_or_else(disposed_error)?;
            let network = client.network_control();
            let p = network
                .run_read(
                    c::ConnectionMode::Direct,
                    false,
                    Box::pin(async {
                        let required = |v: Option<String>| {
                            v.filter(|s| !s.is_empty())
                                .ok_or_else(|| c::UbaaError::invalid_input("云盘读取输入缺失"))
                        };
                        match query.view {
                            BridgeBhpanReadView::PersonalRoot => client.bhpan_personal_root().await,
                            BridgeBhpanReadView::Roots => {
                                client
                                    .bhpan_roots(
                                        query
                                            .root
                                            .ok_or_else(|| {
                                                c::UbaaError::invalid_input("文档库分类缺失")
                                            })?
                                            .into(),
                                    )
                                    .await
                            }
                            BridgeBhpanReadView::List => {
                                client.bhpan_list(&required(query.target)?).await
                            }
                            BridgeBhpanReadView::Recycle => client.bhpan_recycle().await,
                            BridgeBhpanReadView::OpenShare => {
                                client
                                    .bhpan_open_share(
                                        &required(query.link)?,
                                        query.password.map(c::SecretValue::new),
                                    )
                                    .await
                            }
                        }
                    }),
                )
                .await
                .map_err(error)?;
            Ok(p.into())
        })
        .await
    }
    pub async fn bhpan_size(&self, item: String) -> Result<BridgeBhpanSize, BridgeError> {
        catch_panic(async {
            let mut g = self.inner.lock().await;
            let client = g.as_mut().ok_or_else(disposed_error)?;
            let s = client
                .network_control()
                .run_read(
                    c::ConnectionMode::Direct,
                    false,
                    Box::pin(client.bhpan_size(&item)),
                )
                .await
                .map_err(error)?;
            Ok(BridgeBhpanSize {
                folders: s.folders,
                files: s.files,
                bytes: s.bytes,
            })
        })
        .await
    }
    pub async fn bhpan_suggest_name(
        &self,
        parent: String,
        name: String,
    ) -> Result<String, BridgeError> {
        catch_panic(async {
            let mut g = self.inner.lock().await;
            let client = g.as_mut().ok_or_else(disposed_error)?;
            client
                .network_control()
                .run_read(
                    c::ConnectionMode::Direct,
                    false,
                    Box::pin(client.bhpan_suggest_name(&parent, &name)),
                )
                .await
                .map_err(error)
        })
        .await
    }
    pub async fn bhpan_shares(
        &self,
        item: Option<String>,
    ) -> Result<Vec<BridgeBhpanShare>, BridgeError> {
        catch_panic(async {
            let mut g = self.inner.lock().await;
            let c = g.as_mut().ok_or_else(disposed_error)?;
            let network = c.network_control();
            let s = network
                .run_read(
                    c::ConnectionMode::Direct,
                    false,
                    Box::pin(async {
                        match item {
                            Some(item) => c.bhpan_share_records(&item).await,
                            None => c.bhpan_share_history().await,
                        }
                    }),
                )
                .await
                .map_err(error)?;
            Ok(s.into_iter().map(Into::into).collect())
        })
        .await
    }
    pub async fn bhpan_share_link(&self, share: String) -> Result<String, BridgeError> {
        catch_panic(async {
            let mut g = self.inner.lock().await;
            let client = g.as_mut().ok_or_else(disposed_error)?;
            client
                .network_control()
                .run_read(
                    c::ConnectionMode::Direct,
                    false,
                    client.bhpan_share_link(&share),
                )
                .await
                .map_err(error)
        })
        .await
    }
    pub async fn bhpan_prepare(
        &self,
        request: BridgeBhpanWrite,
    ) -> Result<BridgeBhpanPrepared, BridgeError> {
        catch_panic(async {
            let mut g = self.inner.lock().await;
            let p = g
                .as_mut()
                .ok_or_else(disposed_error)?
                .bhpan_prepare_write(request.try_into().map_err(error)?)
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
    pub async fn bhpan_commit(&self, handle: String) -> Result<BridgeBhpanReceipt, BridgeError> {
        let mut observation = None;
        let result = AssertUnwindSafe(async {
            let mut g = self.inner.lock().await;
            if self.is_disposed.load(std::sync::atomic::Ordering::Acquire) {
                return Err(disposed_error());
            }
            let client = g.as_mut().ok_or_else(disposed_error)?;
            observation = Some(client.observe_write_boundary());
            let r = client.bhpan_commit_write(&handle).await.map_err(error)?;
            Ok(BridgeBhpanReceipt {
                item: r.item.map(Into::into),
                share: r.share.map(Into::into),
            })
        })
        .catch_unwind()
        .await;
        match result {
            Ok(result) => result,
            Err(_) => Err(if observation.is_some_and(|o| o.may_have_been_sent()) {
                error(c::UbaaError::outcome_unknown(
                    "云盘操作结果待核对，请在原账号与路线刷新目标，不要重复提交",
                ))
            } else {
                crate::api::client::panic_error()
            }),
        }
    }
    pub async fn bhpan_discard(&self, handle: String) -> Result<(), BridgeError> {
        catch_panic(async {
            let mut g = self.inner.lock().await;
            g.as_mut()
                .ok_or_else(disposed_error)?
                .bhpan_discard_write(&handle);
            Ok(())
        })
        .await
    }
}

#[cfg(test)]
mod tests;
