//! 聚合计数、每日用户登记和持久化批次。

use super::{
    AppServiceResult,
    privacy::TelemetryUser,
    types::{Channel, Platform, Surface, TelemetryEvent},
};
use chrono::{Days, NaiveDate, NaiveDateTime};
use rusqlite::{OptionalExtension, Transaction, params};
use uuid::Uuid;

mod batch;
mod minutes;
#[cfg(test)]
mod tests;

pub use batch::FrozenBatch;
pub(super) use batch::{batch_for_send, freeze};
pub(super) use minutes::MINUTE_SCHEMA;

const COUNT_LIMIT: i64 = 100_000;
const CAPACITY_BYTES: usize = 256 * 1024;
// 一个批次的固定字段和至多八组外壳（含最长版本、两种来源）。
// 含可选分钟数组的字段名。待发事件及用户各自另计序列化长度和分隔符。
const FRAME_RESERVE: usize = 2 * 1024;
// `,"count":100000,` 最多增加 16 字节（含数组分隔符）。
const COUNT_AND_SEPARATOR_BYTES: u8 = 16;

// 用户登记依次保存待发正文、所属冻结批次、已确认组合。
// 日配额单独保存；清空未确认登记后，同一账号仍可补登版本。
pub(super) const SCHEMA: &str = "
    CREATE TABLE app_service_pending(
        id INTEGER PRIMARY KEY,
        day TEXT NOT NULL,
        version TEXT NOT NULL,
        category INTEGER NOT NULL CHECK(category BETWEEN 0 AND 2),
        dimensions BLOB NOT NULL,
        surfaces INTEGER NOT NULL CHECK(surfaces BETWEEN 1 AND 3),
        count INTEGER NOT NULL CHECK(count > 0),
        UNIQUE(day,version,category,dimensions)
    );
    CREATE TABLE app_service_registrations(
        day TEXT NOT NULL,
        version TEXT NOT NULL,
        user_key TEXT NOT NULL,
        pending_body BLOB,
        batch_id TEXT,
        PRIMARY KEY(day,version,user_key)
    );
    CREATE TABLE app_service_daily_accounts(
        day TEXT NOT NULL,
        user_key TEXT NOT NULL,
        PRIMARY KEY(day,user_key)
    );
    CREATE TABLE app_service_batches(
        id TEXT PRIMARY KEY NOT NULL,
        install_id TEXT NOT NULL,
        last_day TEXT NOT NULL,
        body BLOB NOT NULL
    );";

/// 处理上传响应时对当前批次执行的动作。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BatchDisposition {
    Accepted,
    InstallErased,
    InvalidPayload,
    Retry,
}

pub(super) fn finish(
    tx: &Transaction<'_>,
    batch_id: Uuid,
    disposition: BatchDisposition,
) -> AppServiceResult<bool> {
    let id = batch_id.to_string();
    if disposition == BatchDisposition::Retry {
        return Ok(tx.query_row(
            "SELECT EXISTS(SELECT 1 FROM app_service_batches WHERE id=?1)",
            [id],
            |row| row.get(0),
        )?);
    }
    if tx.execute("DELETE FROM app_service_batches WHERE id=?1", [&id])? == 0 {
        return Ok(false);
    }
    if disposition == BatchDisposition::Accepted {
        tx.execute(
            "UPDATE app_service_registrations SET batch_id=NULL WHERE batch_id=?1",
            [&id],
        )?;
    } else {
        tx.execute(
            "DELETE FROM app_service_registrations WHERE batch_id=?1",
            [&id],
        )?;
    }
    Ok(true)
}

pub(super) fn clear(tx: &Transaction<'_>) -> AppServiceResult<()> {
    tx.execute_batch(
        "DELETE FROM app_service_pending;
         DELETE FROM app_service_minutes;
         DELETE FROM app_service_batches;
         DELETE FROM app_service_registrations
         WHERE pending_body IS NOT NULL OR batch_id IS NOT NULL;",
    )?;
    Ok(())
}

pub(super) fn reset(tx: &Transaction<'_>) -> AppServiceResult<()> {
    clear(tx)?;
    tx.execute_batch(
        "DELETE FROM app_service_registrations;
         DELETE FROM app_service_daily_accounts;",
    )?;
    Ok(())
}

pub(super) fn enqueue(
    tx: &Transaction<'_>,
    now: NaiveDateTime,
    version: &str,
    surface: Surface,
    event: &TelemetryEvent,
    user: Option<&TelemetryUser>,
) -> AppServiceResult<bool> {
    if !event.is_valid() {
        return Ok(false);
    }
    let day = now.date();
    purge_expired(tx, day)?;
    let (category, dimensions) = match event {
        TelemetryEvent::Counter(dimensions) => (0, serde_json::to_vec(dimensions)?),
        TelemetryEvent::Error(dimensions) => (1, serde_json::to_vec(dimensions)?),
        TelemetryEvent::Timing(dimensions) => (2, serde_json::to_vec(dimensions)?),
    };
    let day = day.to_string();
    let count: i64 = tx
        .query_row(
            "SELECT count FROM app_service_pending
             WHERE day=?1 AND version=?2 AND category=?3 AND dimensions=?4",
            params![day, version, category, dimensions],
            |row| row.get(0),
        )
        .optional()?
        .unwrap_or(0);
    let registration = match user {
        Some(user) if should_register(tx, &day, version, user.key())? => {
            Some((user.key(), serde_json::to_vec(user)?))
        }
        _ => None,
    };
    let event_delta = if count % COUNT_LIMIT == 0 {
        dimensions.len() + usize::from(COUNT_AND_SEPARATOR_BYTES)
    } else {
        0
    };
    let user_delta = registration.as_ref().map_or(0, |(_, body)| body.len() + 1);
    let Some(spare) =
        CAPACITY_BYTES.checked_sub(queued_bytes(tx)? + event_delta + user_delta + FRAME_RESERVE)
    else {
        return Ok(false);
    };
    let surfaces = match surface {
        Surface::Gui => 1,
        Surface::Command => 2,
    };
    tx.execute(
        "INSERT INTO app_service_pending(day,version,category,dimensions,surfaces,count)
         VALUES(?1,?2,?3,?4,?5,1)
         ON CONFLICT(day,version,category,dimensions) DO UPDATE
         SET count=count+1, surfaces=surfaces | excluded.surfaces",
        params![day, version, category, dimensions, surfaces],
    )?;
    if let Some((key, body)) = registration {
        tx.execute(
            "INSERT INTO app_service_registrations(day,version,user_key,pending_body) VALUES(?1,?2,?3,?4)",
            params![day, version, key, body],
        )?;
        tx.execute(
            "INSERT OR IGNORE INTO app_service_daily_accounts(day,user_key) VALUES(?1,?2)",
            params![day, key],
        )?;
    }
    if let Some(dimensions) = minutes::Dimensions::from_event(now.time(), event) {
        minutes::record(tx, &day, version, surfaces, &dimensions, spare)?;
    }
    Ok(true)
}

fn should_register(
    tx: &Transaction<'_>,
    day: &str,
    version: &str,
    key: &str,
) -> AppServiceResult<bool> {
    Ok(tx.query_row(
        "SELECT NOT EXISTS(
            SELECT 1 FROM app_service_registrations WHERE day=?1 AND version=?2 AND user_key=?3
         ) AND (
            EXISTS(SELECT 1 FROM app_service_daily_accounts WHERE day=?1 AND user_key=?3)
            OR (SELECT count(*) FROM app_service_daily_accounts WHERE day=?1) < 3
         )",
        params![day, version, key],
        |row| row.get(0),
    )?)
}

fn queued_bytes(tx: &Transaction<'_>) -> AppServiceResult<usize> {
    let size: i64 = tx.query_row(
        "SELECT
            (SELECT coalesce(sum((length(dimensions)+?1)*(1+(count-1)/?2)),0) FROM app_service_pending)
            + (SELECT coalesce(sum((length(dimensions)+?1)*(1+(count-1)/?2)),0)
               FROM app_service_minutes WHERE count>0)
            + (SELECT coalesce(sum(length(pending_body)+1),0) FROM app_service_registrations)
            + (SELECT coalesce(sum(length(body)),0) FROM app_service_batches)",
        params![COUNT_AND_SEPARATOR_BYTES, COUNT_LIMIT],
        |row| row.get(0),
    )?;
    usize::try_from(size).map_err(|_| rusqlite::Error::InvalidQuery.into())
}

fn oldest_day(today: NaiveDate) -> String {
    today
        .checked_sub_days(Days::new(7))
        .unwrap_or(NaiveDate::MIN)
        .to_string()
}

fn purge_expired(tx: &Transaction<'_>, today: NaiveDate) -> AppServiceResult<()> {
    let cutoff = oldest_day(today);
    tx.execute("DELETE FROM app_service_pending WHERE day < ?1", [&cutoff])?;
    tx.execute("DELETE FROM app_service_minutes WHERE day < ?1", [&cutoff])?;
    tx.execute(
        "DELETE FROM app_service_registrations WHERE day < ?1",
        [&cutoff],
    )?;
    tx.execute(
        "DELETE FROM app_service_daily_accounts WHERE day < ?1",
        [&cutoff],
    )?;
    tx.execute(
        "DELETE FROM app_service_batches WHERE last_day < ?1",
        [&cutoff],
    )?;
    Ok(())
}
