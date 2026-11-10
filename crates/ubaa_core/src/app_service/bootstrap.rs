//! 启动配置刷新、更新门控与公告已读状态。

use std::{
    future::{Future, poll_fn},
    pin::pin,
    task::Poll,
    time::Duration,
};

use rusqlite::{OptionalExtension, Transaction, params};
use tokio::time::timeout;

use crate::ports::{HttpRequest, HttpTransport, same_url};

use super::{
    APP_SERVICE_SCHEMA_VERSION, AppBootstrapView, AppService, AppServiceError, AppServiceResult,
    AppUpdateStatus, AppUpdateView, Consent, Surface,
    bootstrap_response::{Bootstrap, parse_response, valid_announcement_id},
    config::AvailableConfig,
    transport::AppServiceTransport,
    version::{compare_versions, valid_release_version},
};

pub(super) const SCHEMA: &str = "
ALTER TABLE app_service_state ADD COLUMN bootstrap_consent_epoch INTEGER NOT NULL DEFAULT 0;
CREATE TABLE app_service_bootstrap (
    channel TEXT PRIMARY KEY,
    attempt INTEGER NOT NULL DEFAULT 0,
    last_attempt INTEGER,
    response_platform TEXT,
    response_version TEXT,
    response TEXT,
    min_supported_version TEXT,
    gate_url TEXT,
    dismissed_version TEXT
);
CREATE TABLE app_service_read_announcements (
    id TEXT PRIMARY KEY
);
";

const BOOTSTRAP_PATH: &str = "/v1/bootstrap";
const BOOTSTRAP_TIMEOUT: Duration = Duration::from_secs(5);
const REFRESH_INTERVAL_MS: i64 = 6 * 60 * 60 * 1000;

struct RefreshAttempt {
    serial: i64,
    consent_epoch: i64,
}

struct StoredBootstrap {
    has_response: bool,
    response: Option<String>,
    minimum: Option<String>,
    gate_url: Option<String>,
    dismissed_version: Option<String>,
}

impl AppService {
    /// 读取同意范围内的更新信息和未过期的未读公告。
    ///
    /// # Errors
    /// 读取安装级存储失败时返回错误。
    pub fn bootstrap_view(&self) -> AppServiceResult<AppBootstrapView> {
        self.store.read(|tx| self.bootstrap_view_in(tx))
    }

    fn bootstrap_view_in(&self, tx: &Transaction<'_>) -> AppServiceResult<AppBootstrapView> {
        let Some(config) = self.config.available() else {
            return Ok(AppBootstrapView::default());
        };
        if !matches!(self.permissions(tx)?.consent, Consent::Agreed(_)) {
            return Ok(AppBootstrapView::default());
        }
        let Some(stored) = load_bootstrap(tx, config)? else {
            return Ok(AppBootstrapView::default());
        };
        let gate_active = below_minimum(config, stored.minimum.as_deref());
        let Some(response) = stored.response else {
            return Ok(AppBootstrapView {
                update: stored.has_response.then_some(AppUpdateView {
                    status: if gate_active {
                        AppUpdateStatus::UpdateRequired
                    } else {
                        AppUpdateStatus::Unknown
                    },
                    latest_version: None,
                    min_supported_version: stored.minimum.filter(|_| gate_active),
                    url: stored.gate_url.filter(|_| gate_active),
                    release_notes: None,
                    gate_active,
                    available_dismissed: false,
                }),
                announcements: Vec::new(),
            });
        };
        let Bootstrap {
            update,
            announcements,
        } = serde_json::from_str(&response).map_err(|_| AppServiceError::StorageUnavailable)?;
        let available_dismissed = update.status == AppUpdateStatus::UpdateAvailable
            && update.latest_version.as_deref().is_some_and(|latest| {
                stored
                    .dismissed_version
                    .as_deref()
                    .is_some_and(|dismissed| compare_versions(latest, dismissed).is_le())
            });
        let mut unread = Vec::new();
        let now = self.now();
        let mut is_read = tx.prepare_cached(
            "SELECT EXISTS(SELECT 1 FROM app_service_read_announcements WHERE id = ?1)",
        )?;
        for announcement in announcements {
            if announcement.ends_at.is_none_or(|ends_at| now < ends_at)
                && !is_read.query_row([&announcement.id], |row| row.get::<_, bool>(0))?
            {
                unread.push(announcement);
            }
        }
        Ok(AppBootstrapView {
            update: Some(AppUpdateView {
                status: update.status,
                latest_version: update.latest_version,
                min_supported_version: if gate_active {
                    stored.minimum
                } else {
                    update.min_supported_version
                },
                url: if gate_active {
                    stored.gate_url
                } else {
                    update.url
                },
                release_notes: update.release_notes,
                gate_active,
                available_dismissed,
            }),
            announcements: unread,
        })
    }

    /// 检查当前渠道、安装包版本和共享同意状态，不读取公告或发出请求。
    ///
    /// # Errors
    /// 读取安装级存储失败时返回错误。
    pub fn update_gate_active(&self) -> AppServiceResult<bool> {
        let Some(config) = self.config.available() else {
            return Ok(false);
        };
        self.store.read(|tx| {
            if !matches!(self.permissions(tx)?.consent, Consent::Agreed(_)) {
                return Ok(false);
            }
            let minimum = tx
                .query_row(
                    "SELECT min_supported_version FROM app_service_bootstrap WHERE channel = ?1",
                    [config.channel.wire()],
                    |row| row.get::<_, Option<String>>(0),
                )
                .optional()?
                .flatten();
            Ok(below_minimum(config, minimum.as_deref()))
        })
    }

    /// GUI 启动或重新同意时强制刷新，其他前台触发距上次尝试至少六小时。
    /// 网络、超时、HTTP 或响应校验失败时保留上次成功结果。
    ///
    /// # Errors
    /// 安装级存储或应用服务专用传输不可用时返回错误。
    pub async fn refresh_bootstrap(&self, force: bool) -> AppServiceResult<AppBootstrapView> {
        let Some(endpoint) = self.endpoint().filter(|_| self.surface == Surface::Gui) else {
            return self.bootstrap_view();
        };
        self.refresh_bootstrap_with(&AppServiceTransport::new(endpoint)?, force)
            .await
    }

    pub(crate) async fn refresh_bootstrap_with(
        &self,
        transport: &dyn HttpTransport,
        force: bool,
    ) -> AppServiceResult<AppBootstrapView> {
        let Some(config) = self
            .config
            .available()
            .filter(|_| self.surface == Surface::Gui)
        else {
            return self.bootstrap_view();
        };
        let mut url = config.url.clone();
        url.set_path(BOOTSTRAP_PATH);
        url.query_pairs_mut()
            .append_pair("schema", &APP_SERVICE_SCHEMA_VERSION.to_string())
            .append_pair("platform", config.platform.wire())
            .append_pair("channel", config.channel.wire())
            .append_pair("version", &config.version);
        let request = HttpRequest::get(url.as_str());
        let mut pending =
            pin!(async { timeout(BOOTSTRAP_TIMEOUT, transport.execute(request)).await });
        // 共享同意状态、节流和开始交付在同一短事务内确认，网络等待在事务之外。
        let started = poll_fn(|cx| {
            Poll::Ready(self.store.write(|tx| {
                let attempt = self.claim_bootstrap(tx, config, force)?;
                Ok(attempt.map(|attempt| (attempt, pending.as_mut().poll(cx))))
            }))
        })
        .await?;
        if let Some((attempt, first)) = started {
            let response = match first {
                Poll::Ready(result) => result,
                Poll::Pending => pending.await,
            };
            if let Ok(Ok(response)) = response
                && (200..300).contains(&response.status)
                && same_url(url.as_str(), &response.final_url)
                && let Some(response) = parse_response(&response.body, config.channel)
            {
                self.save_bootstrap(config, &attempt, &response)?;
            }
        }
        self.bootstrap_view()
    }

    fn claim_bootstrap(
        &self,
        tx: &Transaction<'_>,
        config: &AvailableConfig,
        force: bool,
    ) -> AppServiceResult<Option<RefreshAttempt>> {
        if !self.permissions(tx)?.can_bootstrap() {
            return Ok(None);
        }
        let now = self.now().timestamp_millis();
        let serial = tx
            .query_row(
                "INSERT INTO app_service_bootstrap (channel, attempt, last_attempt) VALUES (?1, 1, ?2)
                 ON CONFLICT(channel) DO UPDATE SET attempt = attempt + 1, last_attempt = ?2
                 WHERE ?3 OR last_attempt IS NULL OR last_attempt <= ?4
                 RETURNING attempt",
                params![config.channel.wire(), now, force, now - REFRESH_INTERVAL_MS],
                |row| row.get(0),
            )
            .optional()?;
        serial
            .map(|serial| {
                Ok(RefreshAttempt {
                    serial,
                    consent_epoch: consent_epoch(tx)?,
                })
            })
            .transpose()
    }

    fn save_bootstrap(
        &self,
        config: &AvailableConfig,
        attempt: &RefreshAttempt,
        response: &Bootstrap,
    ) -> AppServiceResult<()> {
        let body = serde_json::to_string(response)?;
        let update = &response.update;
        let changes_gate = update.status != AppUpdateStatus::Unknown;
        let sets_gate = update.status == AppUpdateStatus::UpdateRequired;
        self.store.write(|tx| {
            // 撤回或更高版本政策使在途请求失效；同渠道旧尝试不能覆盖后发请求。
            if consent_epoch(tx)? != attempt.consent_epoch {
                return Ok(());
            }
            tx.execute(
                "UPDATE app_service_bootstrap
                    SET response_platform = ?1, response_version = ?2, response = ?3,
                        min_supported_version = CASE WHEN ?4 THEN ?5 ELSE min_supported_version END,
                        gate_url = CASE WHEN ?4 THEN ?6 ELSE gate_url END
                    WHERE channel = ?7 AND attempt = ?8",
                params![
                    config.platform.wire(),
                    config.version,
                    body,
                    changes_gate,
                    sets_gate
                        .then_some(update.min_supported_version.as_deref())
                        .flatten(),
                    sets_gate.then_some(update.url.as_deref()).flatten(),
                    config.channel.wire(),
                    attempt.serial,
                ],
            )?;
            Ok(())
        })
    }

    /// 按公告 ID 保存本机已读状态。读取和发送启动配置都不会上传此状态。
    ///
    /// # Errors
    /// 公告 ID 不合法或安装级存储无法写入时返回错误。
    pub fn mark_announcement_read(&self, id: &str) -> AppServiceResult<()> {
        if !valid_announcement_id(id) {
            return Err(AppServiceError::InvalidPayload);
        }
        self.store.write(|tx| {
            tx.execute(
                "INSERT OR IGNORE INTO app_service_read_announcements (id) VALUES (?1)",
                [id],
            )?;
            Ok(())
        })
    }

    /// 忽略用户看到的正式版本。更高版本将重新出现，迟到的操作不会回退已忽略版本。
    ///
    /// # Errors
    /// 版本不合法或安装级存储无法写入时返回错误。
    pub fn dismiss_update_available(&self, latest_version: &str) -> AppServiceResult<()> {
        let Some(config) = self.config.available() else {
            return Ok(());
        };
        if !valid_release_version(latest_version) {
            return Err(AppServiceError::InvalidPayload);
        }
        self.store.write(|tx| {
            let previous = tx
                .query_row(
                    "SELECT dismissed_version FROM app_service_bootstrap WHERE channel = ?1",
                    [config.channel.wire()],
                    |row| row.get::<_, Option<String>>(0),
                )
                .optional()?
                .flatten();
            if previous.is_none_or(|previous| compare_versions(latest_version, &previous).is_gt()) {
                tx.execute(
                    "INSERT INTO app_service_bootstrap (channel, dismissed_version) VALUES (?1, ?2)
                     ON CONFLICT(channel) DO UPDATE SET dismissed_version = excluded.dismissed_version",
                    params![config.channel.wire(), latest_version],
                )?;
            }
            Ok(())
        })
    }
}

fn below_minimum(config: &AvailableConfig, minimum: Option<&str>) -> bool {
    minimum.is_some_and(|minimum| {
        valid_release_version(minimum) && compare_versions(&config.version, minimum).is_lt()
    })
}

fn consent_epoch(tx: &Transaction<'_>) -> AppServiceResult<i64> {
    Ok(tx.query_row(
        "SELECT bootstrap_consent_epoch FROM app_service_state WHERE id = 1",
        [],
        |row| row.get(0),
    )?)
}

fn load_bootstrap(
    tx: &Transaction<'_>,
    config: &AvailableConfig,
) -> AppServiceResult<Option<StoredBootstrap>> {
    Ok(tx
        .query_row(
            "SELECT CASE WHEN response_platform = ?1 AND response_version = ?2 THEN response END,
                min_supported_version, gate_url, dismissed_version, response IS NOT NULL
             FROM app_service_bootstrap WHERE channel = ?3",
            params![
                config.platform.wire(),
                config.version,
                config.channel.wire()
            ],
            |row| {
                Ok(StoredBootstrap {
                    response: row.get(0)?,
                    minimum: row.get(1)?,
                    gate_url: row.get(2)?,
                    dismissed_version: row.get(3)?,
                    has_response: row.get(4)?,
                })
            },
        )
        .optional()?)
}

#[cfg(test)]
#[path = "tests/bootstrap.rs"]
mod tests;
