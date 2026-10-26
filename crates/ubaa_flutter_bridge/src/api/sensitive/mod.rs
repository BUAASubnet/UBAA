//! 门锁专用内存通路；不进入普通读取DTO或缓存。
use super::client::{BridgeClient, BridgeError, catch_panic, disposed_error};
use std::fmt;
use std::sync::atomic::Ordering;
use ubaa_core::facade::CgyyLockDisplayLease;

#[flutter_rust_bridge::frb(opaque)]
#[derive(Clone, Debug)]
pub struct BridgeCgyyLockDisplayLease {
    inner: CgyyLockDisplayLease,
}
impl BridgeCgyyLockDisplayLease {
    #[flutter_rust_bridge::frb(sync)]
    pub fn cancel(&self) {
        self.inner.cancel();
    }
}

pub struct BridgeCgyyLockDisplay {
    pub code: Option<String>,
    pub due_date: Option<String>,
    pub reservation_reference: Option<String>,
    pub venue_name: Option<String>,
    pub site_name: Option<String>,
    pub space_name: Option<String>,
    pub order_name: Option<String>,
    pub reservation_date: Option<String>,
    pub reservation_date_detail: Option<String>,
    pub reservation_start_date: Option<String>,
    pub reservation_end_date: Option<String>,
    pub valid_for_millis: u32,
}
impl fmt::Debug for BridgeCgyyLockDisplay {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("BridgeCgyyLockDisplay([REDACTED])")
    }
}
impl BridgeClient {
    /// 打开专用页面，后续读取使用Core已固定的路线。
    /// # Errors
    /// 已销毁、路线或会话无效时返回安全错误。
    pub async fn open_cgyy_lock_display(&self) -> Result<BridgeCgyyLockDisplayLease, BridgeError> {
        catch_panic(async {
            if self.is_disposed.load(Ordering::SeqCst) {
                return Err(disposed_error());
            }
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            client
                .open_cgyy_lock_display()
                .map(|inner| BridgeCgyyLockDisplayLease { inner })
                .map_err(|e| BridgeError::from_core(e, None))
        })
        .await
    }
    /// fresh读取密码/预约白名单，最长显示30秒；取消不会等待本方法。
    /// # Errors
    /// 已取消、会话或上游错误时不返回材料。
    pub async fn read_cgyy_lock_display(
        &self,
        lease: &BridgeCgyyLockDisplayLease,
    ) -> Result<BridgeCgyyLockDisplay, BridgeError> {
        catch_panic(async {
            if self.is_disposed.load(Ordering::SeqCst) {
                return Err(disposed_error());
            }
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let value = client
                .read_cgyy_lock_display(&lease.inner)
                .await
                .map_err(|e| BridgeError::from_core(e, None))?;
            if self.is_disposed.load(Ordering::SeqCst) {
                return Err(disposed_error());
            }
            Ok(BridgeCgyyLockDisplay {
                code: value.code,
                due_date: value.due_date,
                reservation_reference: value.reservation_reference,
                venue_name: value.venue_name,
                site_name: value.site_name,
                space_name: value.space_name,
                order_name: value.order_name,
                reservation_date: value.reservation_date,
                reservation_date_detail: value.reservation_date_detail,
                reservation_start_date: value.reservation_start_date,
                reservation_end_date: value.reservation_end_date,
                valid_for_millis: 30_000,
            })
        })
        .await
    }
}
