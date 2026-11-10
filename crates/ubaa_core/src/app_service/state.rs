//! 同意、统计偏好与删除协调。

use super::{AppService, AppServiceError, AppServiceResult, Surface, queue};
use rusqlite::{Transaction, params};
use uuid::Uuid;

pub(super) const SCHEMA: &str = "
CREATE TABLE app_service_state (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    policy_version INTEGER NOT NULL CHECK (policy_version > 0),
    accepted_policy INTEGER CHECK (accepted_policy > 0 AND accepted_policy <= policy_version),
    basic INTEGER NOT NULL CHECK (basic IN (0, 1) AND (basic = 0 OR accepted_policy IS NULL)),
    telemetry_enabled INTEGER CHECK (telemetry_enabled IN (0, 1)),
    install_id TEXT,
    erasing_install_id TEXT CHECK (erasing_install_id IS NULL OR erasing_install_id = install_id)
);
INSERT INTO app_service_state (id, policy_version, basic) VALUES (1, 1, 0);
";

/// 安装级隐私政策选择；版本为当前等待同意或已同意的政策版本。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Consent {
    Unasked,
    Agreed(u32),
    ReconsentRequired(u32),
    Basic,
}

/// 从共享存储读取的状态。保存的开关值和实际权限分别返回。
#[derive(Clone, Copy)]
pub struct AppServiceState {
    pub consent: Consent,
    pub agreed_policy_version: Option<u32>,
    pub telemetry_enabled: Option<bool>,
    pub install_id: Option<Uuid>,
    pub erasing_install_id: Option<Uuid>,
    pub available: bool,
    pub telemetry_hard_closed: bool,
    surface: Surface,
}

impl AppServiceState {
    /// 只允许已同意的 GUI 请求启动配置。
    #[must_use]
    pub fn can_bootstrap(&self) -> bool {
        self.available && self.agreed() && self.surface == Surface::Gui
    }

    /// GUI 可在任意同意状态下删除；命令模式仅在已同意时重试。
    #[must_use]
    pub fn can_erase(&self) -> bool {
        self.available
            && self.install_id.is_some()
            && (self.surface == Surface::Gui || self.agreed())
    }

    /// 入队、冻结与交付批次共用同一个遥测许可。
    #[must_use]
    pub fn can_telemetry(&self) -> bool {
        self.available
            && self.agreed()
            && self.install_id.is_some()
            && self.erasing_install_id.is_none()
            && self.telemetry_enabled == Some(true)
            && !self.telemetry_hard_closed
    }

    fn agreed(&self) -> bool {
        matches!(self.consent, Consent::Agreed(_))
    }
}

pub(super) struct StoredState {
    policy_version: u32,
    accepted_policy: Option<u32>,
    basic: bool,
    telemetry_enabled: Option<bool>,
    install_id: Option<Uuid>,
    erasing_install_id: Option<Uuid>,
}

impl StoredState {
    pub(super) fn load(tx: &Transaction<'_>) -> AppServiceResult<Self> {
        let (
            policy_version,
            accepted_policy,
            basic,
            telemetry_enabled,
            install_id,
            erasing_install_id,
        ) = tx.query_row(
            "SELECT policy_version, accepted_policy, basic, telemetry_enabled,
                    install_id, erasing_install_id FROM app_service_state WHERE id = 1",
            [],
            |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get::<_, Option<String>>(4)?,
                    row.get::<_, Option<String>>(5)?,
                ))
            },
        )?;
        let parse = |value: Option<String>| {
            value
                .as_deref()
                .map(Uuid::parse_str)
                .transpose()
                .map_err(|_| AppServiceError::StorageUnavailable)
        };
        Ok(Self {
            policy_version,
            accepted_policy,
            basic,
            telemetry_enabled,
            install_id: parse(install_id)?,
            erasing_install_id: parse(erasing_install_id)?,
        })
    }

    fn consent(&self) -> Consent {
        match self.accepted_policy {
            Some(accepted) if accepted == self.policy_version => Consent::Agreed(accepted),
            Some(_) => Consent::ReconsentRequired(self.policy_version),
            None if self.basic => Consent::Basic,
            None => Consent::Unasked,
        }
    }
}

impl AppService {
    /// 读取供宿主显示的最新状态。
    ///
    /// # Errors
    /// 无法读取共享数据库时返回存储错误。
    pub fn snapshot(&self) -> AppServiceResult<AppServiceState> {
        self.store.read(|tx| self.permissions(tx))
    }

    pub(super) fn permissions(&self, tx: &Transaction<'_>) -> AppServiceResult<AppServiceState> {
        let state = StoredState::load(tx)?;
        let consent = state.consent();
        Ok(AppServiceState {
            consent,
            agreed_policy_version: state.accepted_policy,
            telemetry_enabled: state.telemetry_enabled,
            install_id: state.install_id,
            erasing_install_id: state.erasing_install_id,
            available: self.config.available().is_some(),
            telemetry_hard_closed: (self.telemetry_hard_closed)(),
            surface: self.surface,
        })
    }

    /// 登记当前构建的政策版本，保留更高版本及待发数据。
    ///
    /// # Errors
    /// 版本为零或数据库无法写入时返回错误。
    pub fn require_policy(&self, version: u32) -> AppServiceResult<()> {
        if version == 0 {
            return Err(AppServiceError::InvalidPolicy);
        }
        self.store.write(|tx| {
            tx.execute(
                "UPDATE app_service_state SET policy_version = ?1,
                    bootstrap_consent_epoch = bootstrap_consent_epoch + 1 WHERE policy_version < ?1",
                [version],
            )?;
            Ok(())
        })
    }

    /// 同意当前版本。仅 GUI 能写入同意，旧构建不能覆盖新版政策。
    ///
    /// # Errors
    /// 非 GUI、政策版本为零或过旧，或数据库无法写入时返回错误。
    pub fn agree(&self, version: u32) -> AppServiceResult<()> {
        self.require_gui()?;
        if version == 0 {
            return Err(AppServiceError::InvalidPolicy);
        }
        self.store.write(|tx| {
            let state = StoredState::load(tx)?;
            if version < state.policy_version {
                return Err(AppServiceError::InvalidPolicy);
            }
            let install_id = state.install_id.unwrap_or_else(Uuid::new_v4).to_string();
            tx.execute(
                "UPDATE app_service_state SET policy_version = ?1, accepted_policy = ?1,
                    basic = 0, telemetry_enabled = COALESCE(telemetry_enabled, 1),
                    bootstrap_consent_epoch = bootstrap_consent_epoch + (accepted_policy IS NOT ?1),
                    install_id = ?2 WHERE id = 1",
                params![version, install_id],
            )?;
            Ok(())
        })
    }

    /// 拒绝或撤回同意，并在同一事务清空待发数据。
    ///
    /// # Errors
    /// 非 GUI 或数据库无法写入时返回错误。
    pub fn enter_basic(&self) -> AppServiceResult<()> {
        self.require_gui()?;
        self.store.write(|tx| {
            tx.execute(
                "UPDATE app_service_state SET basic = 1, accepted_policy = NULL,
                    bootstrap_consent_epoch = bootstrap_consent_epoch + (basic = 0) WHERE id = 1",
                [],
            )?;
            queue::clear(tx)
        })
    }

    /// 修改独立开关。硬关闭或未同意时拒绝开启；关闭时清空待发数据。
    ///
    /// # Errors
    /// 非 GUI 或数据库无法写入时返回错误。
    pub fn set_telemetry(&self, enabled: bool) -> AppServiceResult<bool> {
        self.require_gui()?;
        self.store.write(|tx| {
            let state = self.permissions(tx)?;
            if enabled
                && (!state.available
                    || state.telemetry_hard_closed
                    || !matches!(state.consent, Consent::Agreed(_)))
            {
                return Ok(false);
            }
            tx.execute(
                "UPDATE app_service_state SET telemetry_enabled = ?1 WHERE id = 1",
                [enabled],
            )?;
            if !enabled {
                queue::clear(tx)?;
            }
            Ok(true)
        })
    }

    /// 持久化删除标记；重复调用返回同一个待删除的安装 ID。
    ///
    /// # Errors
    /// 非 GUI 或数据库无法写入时返回错误。
    pub fn begin_erase(&self) -> AppServiceResult<Option<Uuid>> {
        self.require_gui()?;
        self.store.write(|tx| {
            let state = self.permissions(tx)?;
            if !state.can_erase() {
                return Ok(None);
            }
            let install = state.install_id;
            if state.erasing_install_id.is_none() {
                tx.execute(
                    "UPDATE app_service_state SET erasing_install_id = install_id WHERE id = 1",
                    [],
                )?;
            }
            Ok(install)
        })
    }

    /// 仅在删除响应为 204 后调用。迟到的成功响应不能清除新安装的数据。
    ///
    /// # Errors
    /// 数据库无法写入时返回错误。
    pub fn finish_erase(&self, erased_install: Uuid) -> AppServiceResult<bool> {
        self.store.write(|tx| {
            let changed = tx.execute(
                "UPDATE app_service_state SET install_id = ?1, erasing_install_id = NULL
                    WHERE id = 1 AND install_id = ?2 AND erasing_install_id = ?2",
                params![Uuid::new_v4().to_string(), erased_install.to_string()],
            )?;
            if changed == 1 {
                queue::reset(tx)?;
            }
            Ok(changed == 1)
        })
    }

    fn require_gui(&self) -> AppServiceResult<()> {
        if self.surface != Surface::Gui {
            return Err(AppServiceError::GuiRequired);
        }
        Ok(())
    }
}
