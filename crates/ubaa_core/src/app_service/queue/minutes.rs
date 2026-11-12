//! 登录与功能加载的匿名分钟计数。

use super::{
    AppServiceResult, COUNT_AND_SEPARATOR_BYTES, COUNT_LIMIT, OptionalExtension, TelemetryEvent,
    Transaction, params,
};
use crate::app_service::types::{CounterEvent, CounterResult, ErrorEvent, Feature};
use chrono::{NaiveTime, Timelike};
use serde::{Deserialize, Serialize};

const DAY_KEY_LIMIT: i64 = 600;

// count 为 0 时只占用当日键配额，不参与待发容量或批次选择。
pub(in crate::app_service) const MINUTE_SCHEMA: &str = "
    CREATE TABLE app_service_minutes(
        id INTEGER PRIMARY KEY,
        day TEXT NOT NULL,
        version TEXT NOT NULL,
        dimensions BLOB NOT NULL,
        surfaces INTEGER NOT NULL CHECK(surfaces BETWEEN 1 AND 3),
        count INTEGER NOT NULL CHECK(count >= 0),
        UNIQUE(day,version,dimensions)
    );";

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
enum Event {
    AuthStarted,
    AuthSucceeded,
    AuthFailed,
    FeatureLoaded,
}

#[derive(Deserialize, Serialize)]
pub(super) struct Dimensions {
    minute: u32,
    event: Event,
    feature: Feature,
    result: CounterResult,
}

impl Dimensions {
    pub(super) fn from_event(time: NaiveTime, event: &TelemetryEvent) -> Option<Self> {
        let (event, feature, result) = match event {
            TelemetryEvent::Counter(counter) => match counter.event {
                CounterEvent::AuthStarted => {
                    (Event::AuthStarted, Feature::Auth, CounterResult::Success)
                }
                CounterEvent::AuthSucceeded => {
                    (Event::AuthSucceeded, Feature::Auth, CounterResult::Success)
                }
                CounterEvent::FeatureLoaded => {
                    (Event::FeatureLoaded, counter.feature, counter.result)
                }
                _ => return None,
            },
            TelemetryEvent::Error(error) if error.event == ErrorEvent::AuthFailed => {
                (Event::AuthFailed, Feature::Auth, CounterResult::Failure)
            }
            _ => return None,
        };
        Some(Self {
            minute: time.hour() * 60 + time.minute(),
            event,
            feature,
            result,
        })
    }
}

pub(super) fn record(
    tx: &Transaction<'_>,
    day: &str,
    version: &str,
    surfaces: i64,
    dimensions: &Dimensions,
    spare: usize,
) -> AppServiceResult<()> {
    let dimensions = serde_json::to_vec(dimensions)?;
    let count: Option<i64> = tx
        .query_row(
            "SELECT count FROM app_service_minutes WHERE day=?1 AND version=?2 AND dimensions=?3",
            params![day, version, dimensions],
            |row| row.get(0),
        )
        .optional()?;
    // 每新增一个可发送的分段，都按 count 的最大长度预留正文空间。
    if count.unwrap_or(0) % COUNT_LIMIT == 0
        && dimensions.len() + usize::from(COUNT_AND_SEPARATOR_BYTES) > spare
    {
        return Ok(());
    }
    if count.is_none()
        && tx.query_row(
            "SELECT count(*) FROM app_service_minutes WHERE day=?1",
            [day],
            |row| row.get::<_, i64>(0),
        )? >= DAY_KEY_LIMIT
    {
        return Ok(());
    }
    tx.execute(
        "INSERT INTO app_service_minutes(day,version,dimensions,surfaces,count)
         VALUES(?1,?2,?3,?4,1)
         ON CONFLICT(day,version,dimensions) DO UPDATE
         SET count=count+1,
             surfaces=CASE WHEN count=0 THEN excluded.surfaces ELSE surfaces | excluded.surfaces END",
        params![day, version, dimensions, surfaces],
    )?;
    Ok(())
}
