//! 安装级服务入口。每次访问按共享数据库中的当前权限执行。

use super::{
    AppServiceConfig, AppServiceError, AppServiceResult, BatchDisposition, FrozenBatch, Surface,
    TelemetryEvent, config, privacy::TelemetryUser, queue, sqlite::Store,
};
use crate::facade::SharedAccountGuard;
use chrono::{DateTime, Datelike, NaiveDate, Utc};
use chrono_tz::Asia::Shanghai;
use std::{path::Path, sync::Arc};
use url::Url;
use uuid::Uuid;

/// 由已确认的账号绑定提供，只在原本机账号代次仍有效时用于登记。
pub struct ConfirmedAccount {
    guard: SharedAccountGuard,
    username: String,
}

impl ConfirmedAccount {
    /// 使用认证成功或会话恢复通过的绑定。离线使用可以沿用仍有效的同一绑定。
    /// 退出或切换时，宿主应丢弃此对象；共享代次失效后 Core 也会拒绝使用旧账号。
    #[must_use]
    pub fn from_bound_account(guard: SharedAccountGuard, expected_username: String) -> Self {
        Self {
            guard,
            username: expected_username,
        }
    }
}

/// GUI 与命令模式共用安装状态和冻结队列；句柄的配置与时钟属于本进程。
pub struct AppService {
    pub(super) store: Store,
    pub(super) config: AppServiceConfig,
    pub(super) surface: Surface,
    pub(super) telemetry_hard_closed: fn() -> bool,
    now: Arc<dyn Fn() -> DateTime<Utc> + Send + Sync>,
}

impl AppService {
    /// 在宿主现有配置目录中打开安装级存储，不依赖账号目录。
    ///
    /// # Errors
    /// 政策版本为零、目录不可用、数据库损坏或版本不受支持时返回错误。
    pub fn open(
        config_dir: &Path,
        config: AppServiceConfig,
        surface: Surface,
        policy_version: u32,
    ) -> AppServiceResult<Self> {
        if policy_version == 0 {
            return Err(AppServiceError::InvalidPolicy);
        }
        let service = Self {
            store: Store::open(config_dir)?,
            config,
            surface,
            telemetry_hard_closed: config::telemetry_hard_closed,
            now: Arc::new(Utc::now),
        };
        if service.config.available().is_some() {
            service.require_policy(policy_version)?;
        }
        Ok(service)
    }

    #[cfg(test)]
    pub(super) fn with_runtime(
        mut self,
        now: impl Fn() -> DateTime<Utc> + Send + Sync + 'static,
        hard_close: bool,
    ) -> Self {
        self.now = Arc::new(now);
        self.telemetry_hard_closed = if hard_close { || true } else { || false };
        self
    }

    /// 返回已验证的服务地址。具体操作仍需读取共享权限。
    #[must_use]
    pub fn endpoint(&self) -> Option<&Url> {
        self.config.available().map(|available| &available.url)
    }

    pub(super) fn now(&self) -> DateTime<Utc> {
        (self.now)()
    }

    pub(super) fn today(&self) -> NaiveDate {
        self.now().with_timezone(&Shanghai).date_naive()
    }

    /// 在同一事务中检查权限、累加白名单计数并登记仍有效的已确认账号。
    ///
    /// # Errors
    /// 存储不可用时返回错误，调用方应保留原业务结果。
    pub fn enqueue(
        &self,
        event: &TelemetryEvent,
        account: Option<&ConfirmedAccount>,
    ) -> AppServiceResult<bool> {
        let Some(config) = self.config.available() else {
            return Ok(false);
        };
        if !event.is_valid() {
            return Ok(false);
        }
        // 先取账号许可，再开 SQLite 事务。撤销的旧绑定不能为新计数登记用户。
        let bound = account.and_then(|account| {
            account
                .guard
                .try_acquire_for_telemetry()
                .ok()
                .map(|permit| (account, permit))
        });
        self.store.write(|tx| {
            if !self.permissions(tx)?.can_telemetry() {
                return Ok(false);
            }
            let today = self.today();
            let user = bound.as_ref().and_then(|(account, _)| {
                TelemetryUser::from_confirmed_username(&account.username, today.year())
            });
            queue::enqueue(
                tx,
                today,
                &config.version,
                self.surface,
                event,
                user.as_ref(),
            )
        })
    }

    /// 从共享队列选取首个仍有效的冻结批次，或者从待发计数冻结一个合法子集。
    ///
    /// # Errors
    /// 存储或编码失败时不取走待发数据。
    pub fn freeze_next(&self) -> AppServiceResult<Option<FrozenBatch>> {
        let Some(config) = self.config.available() else {
            return Ok(None);
        };
        self.store.write(|tx| {
            let state = self.permissions(tx)?;
            match state.install_id {
                Some(install) if state.can_telemetry() => {
                    queue::freeze(tx, self.today(), install, config.platform, config.channel)
                }
                _ => Ok(None),
            }
        })
    }

    /// 发送前重新读取共享权限与批次行，并在同一短事务中调用同步交付函数。
    /// 交付函数只启动传输，必须立即返回；等待响应在事务外进行。
    /// 两个进程可以先后交付同一批次，响应无需相互等待。
    ///
    /// # Errors
    /// 无法读取存储时返回错误，不交付批次。
    pub fn with_batch_for_send<R>(
        &self,
        id: Uuid,
        handoff: impl FnOnce(FrozenBatch) -> R,
    ) -> AppServiceResult<Option<R>> {
        self.with_batch_for_send_in(id, |_, batch| Ok(handoff(batch)))
    }

    pub(super) fn with_batch_for_send_in<R>(
        &self,
        id: Uuid,
        handoff: impl FnOnce(&rusqlite::Transaction<'_>, FrozenBatch) -> AppServiceResult<R>,
    ) -> AppServiceResult<Option<R>> {
        self.store.write(|tx| {
            let state = self.permissions(tx)?;
            let batch = match state.install_id {
                Some(install) if state.can_telemetry() => {
                    queue::batch_for_send(tx, self.today(), install, id)
                }
                _ => Ok(None),
            }?;
            batch.map(|batch| handoff(tx, batch)).transpose()
        })
    }

    /// 只处理仍存在的批次。重试沿用原 ID 和正文。
    ///
    /// # Errors
    /// 无法完成数据库事务时返回错误。
    pub fn finish_batch(&self, id: Uuid, disposition: BatchDisposition) -> AppServiceResult<bool> {
        self.store.write(|tx| queue::finish(tx, id, disposition))
    }

    /// 删除发送前读取共享标记。基础模式的命令进程不能重试删除。
    ///
    /// # Errors
    /// 无法读取存储时返回错误。
    pub fn pending_erase_for_send(&self) -> AppServiceResult<Option<Uuid>> {
        self.store.read(|tx| {
            let state = self.permissions(tx)?;
            Ok(state.erasing_install_id.filter(|_| state.can_erase()))
        })
    }
}

impl From<rusqlite::Error> for AppServiceError {
    fn from(_: rusqlite::Error) -> Self {
        Self::StorageUnavailable
    }
}

impl From<serde_json::Error> for AppServiceError {
    fn from(_: serde_json::Error) -> Self {
        Self::InvalidPayload
    }
}
