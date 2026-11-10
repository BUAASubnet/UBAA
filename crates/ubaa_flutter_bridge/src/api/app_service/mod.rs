//! 通过独立句柄访问 Core 的安装状态，不等待学校客户端或持有业务锁。

pub mod models;
mod panic_telemetry;

pub use models::*;
pub(super) use panic_telemetry::install as install_panic_hook;
#[cfg(test)]
pub(super) use panic_telemetry::suppress as suppress_panic_for_test;

use std::{
    path::Path,
    sync::{Arc, Mutex},
    time::Duration,
};
use ubaa_core::facade::app_service as core;

use super::{
    client::{BridgeError, BridgeErrorCode, BridgeErrorKind},
    shared_account::BridgeSharedAccount,
};

pub struct BridgeAppService {
    inner: Arc<Inner>,
    policy_version: u32,
}

struct Inner {
    core: core::AppService,
    account: Mutex<Option<Arc<core::ConfirmedAccount>>>,
}

impl BridgeAppService {
    /// 使用宿主构建信息和同一配置目录打开安装级状态。
    ///
    /// # Errors
    /// 存储不可用或政策版本无效时返回安全错误。
    #[allow(clippy::too_many_arguments)] // 逐项传递构建信息，避免未经校验的配置对象。
    pub async fn open(
        config_dir: String,
        service_url: Option<String>,
        channel: Option<String>,
        app_version: Option<String>,
        platform: BridgeAppServicePlatform,
        release: bool,
        surface: BridgeAppServiceSurface,
        policy_version: u32,
    ) -> Result<Self, BridgeError> {
        local_task(move || {
            let config = core::AppServiceConfig::from_build(
                service_url.as_deref(),
                channel.as_deref(),
                app_version.as_deref(),
                platform.into(),
                release,
            );
            let service = core::open_installation(
                Path::new(&config_dir),
                config,
                surface.into(),
                policy_version,
            )?;
            let available = service.endpoint().is_some();
            let inner = Arc::new(Inner {
                core: service,
                account: Mutex::default(),
            });
            if available {
                panic_telemetry::register(&inner);
            }
            Ok(Self {
                inner,
                policy_version,
            })
        })
        .await
    }

    /// 读取共享持久化状态；不返回安装 ID 或账号。
    ///
    /// # Errors
    /// 本机存储不可用时返回安全错误。
    pub async fn state(&self) -> Result<BridgeAppServiceState, BridgeError> {
        self.change(|_, _| Ok(())).await
    }

    /// 同意本构建的政策版本并返回实际保存状态。
    ///
    /// # Errors
    /// 命令模式、政策版本过旧或存储失败时返回安全错误。
    pub async fn agree(&self) -> Result<BridgeAppServiceState, BridgeError> {
        self.change(core::AppService::agree).await
    }

    /// 拒绝或撤回同意，进入基础模式并清空待发数据。
    ///
    /// # Errors
    /// 命令模式或存储失败时返回安全错误。
    pub async fn enter_basic(&self) -> Result<BridgeAppServiceState, BridgeError> {
        self.change(|service, _| service.enter_basic()).await
    }

    /// 保存统计开关；关闭时同步清理待发数据。
    ///
    /// # Errors
    /// 命令模式或存储失败时返回安全错误。
    pub async fn set_telemetry(&self, enabled: bool) -> Result<BridgeAppServiceState, BridgeError> {
        self.change(move |service, _| service.set_telemetry(enabled).map(drop))
            .await
    }

    async fn change(
        &self,
        operation: impl FnOnce(&core::AppService, u32) -> core::AppServiceResult<()> + Send + 'static,
    ) -> Result<BridgeAppServiceState, BridgeError> {
        let inner = self.inner.clone();
        let policy = self.policy_version;
        local_task(move || {
            if inner.core.endpoint().is_some() {
                operation(&inner.core, policy)?;
            }
            Ok(BridgeAppServiceState::from_core(
                inner.core.snapshot()?,
                policy,
            ))
        })
        .await
    }

    /// 使用宿主已确认的本机账号绑定；每次入队仍由 Core 复核共享代次。
    #[flutter_rust_bridge::frb(sync)]
    pub fn bind_account(&self, scope: &BridgeSharedAccount, expected_username: String) {
        if let Ok(mut account) = self.inner.account.lock() {
            *account = Some(Arc::new(core::ConfirmedAccount::from_bound_account(
                scope.guard.clone(),
                expected_username,
            )));
        }
    }

    /// 退出、切换账号或丢失已确认绑定时清除本进程的账号引用。
    #[flutter_rust_bridge::frb(sync)]
    pub fn clear_account(&self) {
        if let Ok(mut account) = self.inner.account.lock() {
            *account = None;
        }
    }

    /// 聚合一条普通计数。
    ///
    /// # Errors
    /// 本机存储不可用时返回安全错误。
    pub async fn enqueue_counter(
        &self,
        event: BridgeTelemetryCounter,
        feature: BridgeTelemetryFeature,
        route: BridgeTelemetryRoute,
        result: BridgeTelemetryResult,
    ) -> Result<bool, BridgeError> {
        self.enqueue(core::TelemetryEvent::Counter(core::CounterDimensions {
            event: event.into(),
            feature: feature.into(),
            route: route.into(),
            result: result.into(),
        }))
        .await
    }

    /// 聚合一条错误计数；Core 复核错误码和可选源码位置。
    ///
    /// # Errors
    /// 本机存储不可用时返回安全错误。
    #[allow(clippy::too_many_arguments)] // 每个错误字段在 FRB 边界上单独标注类型。
    pub async fn enqueue_error(
        &self,
        event: BridgeTelemetryError,
        feature: BridgeTelemetryFeature,
        route: BridgeTelemetryRoute,
        error_code: String,
        error_kind: BridgeErrorKind,
        retryable: bool,
        source: Option<String>,
    ) -> Result<bool, BridgeError> {
        self.enqueue(core::TelemetryEvent::Error(core::ErrorDimensions {
            event: event.into(),
            feature: feature.into(),
            route: route.into(),
            error_code,
            error_kind: error_kind.into(),
            retryable,
            source,
        }))
        .await
    }

    /// 聚合一条已分桶的耗时。
    ///
    /// # Errors
    /// 本机存储不可用时返回安全错误。
    pub async fn enqueue_timing(
        &self,
        metric: BridgeTelemetryTiming,
        feature: BridgeTelemetryFeature,
        route: BridgeTelemetryRoute,
        bucket: BridgeTelemetryBucket,
    ) -> Result<bool, BridgeError> {
        self.enqueue(core::TelemetryEvent::Timing(core::TimingDimensions {
            metric: metric.into(),
            feature: feature.into(),
            route: route.into(),
            bucket: bucket.into(),
        }))
        .await
    }

    async fn enqueue(&self, event: core::TelemetryEvent) -> Result<bool, BridgeError> {
        let inner = self.inner.clone();
        let account = inner
            .account
            .lock()
            .ok()
            .and_then(|account| account.clone());
        local_task(move || inner.core.enqueue(&event, account.as_deref())).await
    }

    /// 执行一次调度的上传或删除重试；没有删除操作时 `erase` 为 `unavailable`。
    ///
    /// # Errors
    /// 本机存储或传输不可用时返回安全错误。
    pub async fn upload(
        &self,
        force: bool,
        budget_millis: Option<u32>,
    ) -> Result<BridgeAppServiceUpload, BridgeError> {
        let budget = budget_millis.map(|ms| Duration::from_millis(u64::from(ms)));
        let attempt =
            panic_telemetry::suppress_async(self.inner.core.upload_scheduled(force, budget))
                .await?;
        Ok(BridgeAppServiceUpload {
            erase: attempt.erase.into(),
            batches_sent: attempt.batches_sent,
        })
    }

    /// 发起或手动重试删除；网络失败保留 Core 的删除标记。
    ///
    /// # Errors
    /// 命令模式或无法读取共享删除标记时返回安全错误。
    pub async fn erase(&self) -> Result<BridgeAppServiceEraseOutcome, BridgeError> {
        let attempt = panic_telemetry::suppress_async(self.inner.core.erase_once()).await;
        match attempt {
            Ok(result @ (core::EraseAttempt::Completed | core::EraseAttempt::Pending)) => {
                return Ok(result.into());
            }
            Err(error @ core::AppServiceError::GuiRequired) => return Err(error.into()),
            _ => {}
        }
        let state = self.state().await?;
        if state.erase_pending {
            return Ok(BridgeAppServiceEraseOutcome::Pending);
        }
        Ok(attempt?.into())
    }
}

async fn local_task<T: Send + 'static>(
    operation: impl FnOnce() -> core::AppServiceResult<T> + Send + 'static,
) -> Result<T, BridgeError> {
    Ok(
        tokio::task::spawn_blocking(move || panic_telemetry::suppress(operation))
            .await
            .map_err(|_| super::client::panic_error())??,
    )
}

impl From<core::AppServiceError> for BridgeError {
    fn from(error: core::AppServiceError) -> Self {
        let (code, kind) = match error {
            core::AppServiceError::InvalidPolicy | core::AppServiceError::GuiRequired => {
                (BridgeErrorCode::InvalidInput, BridgeErrorKind::Input)
            }
            _ => (BridgeErrorCode::InternalError, BridgeErrorKind::Internal),
        };
        Self::local(code, kind, false, error.to_string())
    }
}

#[cfg(test)]
pub(super) mod tests;
