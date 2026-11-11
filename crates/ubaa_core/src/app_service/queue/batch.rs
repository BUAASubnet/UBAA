//! 从最旧的日期开始冻结合法批次，保留未取走的计数。

use super::{
    AppServiceResult, COUNT_LIMIT, Channel, NaiveDate, OptionalExtension, Platform, Surface,
    Transaction, Uuid, minutes, oldest_day, params, purge_expired,
};
use crate::app_service::APP_SERVICE_SCHEMA_VERSION;
use serde::Serialize;
use serde_json::Value;

const BATCH_BYTES: usize = 120 * 1024;
const GROUP_LIMIT: i64 = 8;
const ARRAY_LIMIT: usize = 512;
const MINUTE_CATEGORY: i64 = 3;
const MINUTE_ARRAY_BYTES: usize = ",\"minutes\":[]".len();

/// 已持久化的上传正文。正文可能含用户派生标识，不通过 `Debug` 输出。
pub struct FrozenBatch {
    id: Uuid,
    install_id: Uuid,
    body: Vec<u8>,
}

impl FrozenBatch {
    #[must_use]
    pub fn id(&self) -> Uuid {
        self.id
    }

    #[must_use]
    pub fn install_id(&self) -> Uuid {
        self.install_id
    }

    #[must_use]
    pub fn body(&self) -> &[u8] {
        &self.body
    }

    pub(in crate::app_service) fn into_body(self) -> Vec<u8> {
        self.body
    }
}

pub(in crate::app_service) fn batch_for_send(
    tx: &Transaction<'_>,
    day: NaiveDate,
    install_id: Uuid,
    batch_id: Uuid,
) -> AppServiceResult<Option<FrozenBatch>> {
    let body = tx
        .query_row(
            "SELECT body FROM app_service_batches WHERE id=?1 AND install_id=?2 AND last_day >= ?3",
            params![
                batch_id.to_string(),
                install_id.to_string(),
                oldest_day(day)
            ],
            |row| row.get(0),
        )
        .optional()?;
    Ok(body.map(|body| FrozenBatch {
        id: batch_id,
        install_id,
        body,
    }))
}

fn first_frozen(tx: &Transaction<'_>, install_id: Uuid) -> AppServiceResult<Option<FrozenBatch>> {
    let Some((id, body)) = tx
        .query_row(
            "SELECT id, body FROM app_service_batches WHERE install_id=?1 ORDER BY rowid LIMIT 1",
            [install_id.to_string()],
            |row| Ok((row.get::<_, String>(0)?, row.get(1)?)),
        )
        .optional()?
    else {
        return Ok(None);
    };
    let id = Uuid::parse_str(&id).map_err(|_| rusqlite::Error::InvalidQuery)?;
    Ok(Some(FrozenBatch {
        id,
        install_id,
        body,
    }))
}

pub(in crate::app_service) fn freeze(
    tx: &Transaction<'_>,
    today: NaiveDate,
    install_id: Uuid,
    platform: Platform,
    channel: Channel,
) -> AppServiceResult<Option<FrozenBatch>> {
    purge_expired(tx, today)?;
    if let Some(batch) = first_frozen(tx, install_id)? {
        return Ok(Some(batch));
    }

    let id = Uuid::new_v4();
    let mut payload = Payload {
        schema: APP_SERVICE_SCHEMA_VERSION,
        batch_id: id,
        install_id,
        platform,
        channel,
        days: Vec::new(),
    };
    let mut length = serde_json::to_vec(&payload)?.len();
    let mut taken = Vec::new();
    let mut statement = tx.prepare(
        "SELECT day,version, max(surfaces & 1) | max(surfaces & 2)
         FROM (
            SELECT day,version,surfaces FROM app_service_pending
            UNION ALL
            SELECT day,version,surfaces FROM app_service_minutes WHERE count>0
         ) GROUP BY day,version ORDER BY day,version LIMIT ?1",
    )?;
    let groups = statement.query_map([GROUP_LIMIT], |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, u8>(2)?,
        ))
    })?;
    for group in groups {
        let (day, version, surfaces) = group?;
        let mut part = DayPayload::load(tx, day, version, surfaces)?;
        let mut part_length =
            serde_json::to_vec(&part)?.len() + usize::from(!payload.days.is_empty());
        let mut statement = tx.prepare(
            "SELECT id,category,dimensions,count FROM app_service_pending
             WHERE day=?1 AND version=?2
             UNION ALL
             SELECT id,?3 AS category,dimensions,count FROM app_service_minutes
             WHERE day=?1 AND version=?2 AND count>0 ORDER BY category,id",
        )?;
        let mut rows = statement.query(params![part.day, part.app_version, MINUTE_CATEGORY])?;
        let mut body_full = false;
        let before = taken.len();
        while let Some(row) = rows.next()? {
            let category: i64 = row.get(1)?;
            let items = part.items(category)?;
            if items.len() == ARRAY_LIMIT {
                continue;
            }
            let dimensions: Vec<u8> = row.get(2)?;
            let count: i64 = row.get(3)?;
            let take = count.min(COUNT_LIMIT);
            let item = Item::from_pending(category, &dimensions, take)?;
            let separator = if !items.is_empty() {
                1
            } else if category == MINUTE_CATEGORY {
                MINUTE_ARRAY_BYTES
            } else {
                0
            };
            let item_length = serde_json::to_vec(&item)?.len() + separator;
            if length + part_length + item_length > BATCH_BYTES {
                body_full = true;
                break;
            }
            items.push(item);
            part_length += item_length;
            taken.push((category, row.get::<_, i64>(0)?, count, take));
        }
        if taken.len() > before {
            length += part_length;
            payload.days.push(part);
        }
        if body_full {
            break;
        }
    }

    let Some(last) = payload.days.last() else {
        return Ok(None);
    };
    let body = serde_json::to_vec(&payload)?;
    tx.execute(
        "INSERT INTO app_service_batches(id,install_id,last_day,body) VALUES(?1,?2,?3,?4)",
        params![id.to_string(), install_id.to_string(), last.day, body],
    )?;
    consume(tx, id, taken, payload.days)?;

    Ok(Some(FrozenBatch {
        id,
        install_id,
        body,
    }))
}

fn consume(
    tx: &Transaction<'_>,
    batch_id: Uuid,
    taken: Vec<(i64, i64, i64, i64)>,
    days: Vec<DayPayload>,
) -> AppServiceResult<()> {
    for (category, id, count, take) in taken {
        if category == MINUTE_CATEGORY {
            tx.execute(
                "UPDATE app_service_minutes SET count=count-?2 WHERE id=?1",
                params![id, take],
            )?;
        } else if count == take {
            tx.execute("DELETE FROM app_service_pending WHERE id=?1", [id])?;
        } else {
            tx.execute(
                "UPDATE app_service_pending SET count=count-?2 WHERE id=?1",
                params![id, take],
            )?;
        }
    }
    for part in days {
        tx.execute(
            "UPDATE app_service_registrations SET pending_body=NULL, batch_id=?3
             WHERE day=?1 AND version=?2 AND pending_body IS NOT NULL",
            params![part.day, part.app_version, batch_id.to_string()],
        )?;
    }

    Ok(())
}

#[derive(Serialize)]
struct Payload {
    schema: u32,
    batch_id: Uuid,
    install_id: Uuid,
    platform: Platform,
    channel: Channel,
    days: Vec<DayPayload>,
}

#[derive(Serialize)]
#[serde(untagged)]
enum Item {
    Daily(Value),
    Minute {
        #[serde(flatten)]
        dimensions: minutes::Dimensions,
        count: i64,
    },
}

impl Item {
    fn from_pending(category: i64, dimensions: &[u8], count: i64) -> AppServiceResult<Self> {
        if category == MINUTE_CATEGORY {
            return Ok(Self::Minute {
                dimensions: serde_json::from_slice(dimensions)?,
                count,
            });
        }
        let mut item: serde_json::Map<String, Value> = serde_json::from_slice(dimensions)?;
        item.insert("count".to_owned(), Value::from(count));
        Ok(Self::Daily(Value::Object(item)))
    }
}

#[derive(Serialize)]
struct DayPayload {
    day: String,
    app_version: String,
    surfaces: Vec<Surface>,
    users: Vec<Value>,
    counters: Vec<Item>,
    errors: Vec<Item>,
    timings: Vec<Item>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    minutes: Vec<Item>,
}

impl DayPayload {
    fn load(
        tx: &Transaction<'_>,
        day: String,
        app_version: String,
        surface_mask: u8,
    ) -> AppServiceResult<Self> {
        let mut statement = tx.prepare(
            "SELECT pending_body FROM app_service_registrations
             WHERE day=?1 AND version=?2 AND pending_body IS NOT NULL ORDER BY user_key",
        )?;
        let mut rows = statement.query(params![day, app_version])?;
        let mut users = Vec::new();
        while let Some(row) = rows.next()? {
            let body: Vec<u8> = row.get(0)?;
            users.push(serde_json::from_slice(&body)?);
        }
        let surfaces = [(1, Surface::Gui), (2, Surface::Command)]
            .into_iter()
            .filter_map(|(bit, surface)| (surface_mask & bit != 0).then_some(surface))
            .collect();
        Ok(Self {
            day,
            app_version,
            surfaces,
            users,
            counters: Vec::new(),
            errors: Vec::new(),
            timings: Vec::new(),
            minutes: Vec::new(),
        })
    }

    fn items(&mut self, category: i64) -> AppServiceResult<&mut Vec<Item>> {
        Ok(match category {
            0 => &mut self.counters,
            1 => &mut self.errors,
            2 => &mut self.timings,
            MINUTE_CATEGORY => &mut self.minutes,
            _ => return Err(rusqlite::Error::InvalidQuery.into()),
        })
    }
}
