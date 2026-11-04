use super::{LocalError, LocalResult};
use crate::CLI_JSON_SCHEMA_VERSION;
use serde_json::{Value, json};
use std::io::Write;
use ubaa_core::facade::{AgendaEntryItem, AgendaTime, AgendaTiming};
pub(crate) fn cache_sources(
    result: &ubaa_core::facade::AgendaQueryResult,
    now: AgendaTime,
) -> Vec<Value> {
    source_values(&result.sources, now)
}
pub(crate) fn source_values(
    sources: &[ubaa_core::facade::AgendaSourceAvailability],
    now: AgendaTime,
) -> Vec<Value> {
    sources
        .iter()
        .map(|source| {
            json!({
                "feature": source.feature,
                "observations": source.observations.iter().map(|v| json!({
                    "scope": v.scope, "fetchedAt": v.fetched_at,
                    "lastVerifiedAt":v.last_verified_at, "lastAttemptAt":v.last_attempt_at,
                    "lastAttemptSucceeded":v.last_attempt_succeeded,"completeness":v.completeness,
                    "fresh":v.is_fresh(now.datetime.timestamp(), 300)
                })).collect::<Vec<_>>(),
                "missingScopes":source.missing_scopes,"semesterImported":source.semester_imported,
                "unprojectableCount":source.unprojectable_count
            })
        })
        .collect()
}

pub(crate) fn entry_value(entry: &ubaa_core::facade::AgendaEntry) -> Value {
    let item = match &entry.item {
        AgendaEntryItem::Local(value) => {
            json!({"origin":"local","occurrence":{"itemId":value.item_id,"recurrenceId":value.recurrence_id,"content":value.content,"completedAt":value.completed_at,"overridden":value.overridden}})
        }
        AgendaEntryItem::School(value) => json!({"origin":"school","key":value.key,
                            "title":value.title,"subtitle":value.subtitle,"location":value.location,
                            "statusLabel":value.status_label,"upstreamCompleted":value.upstream_status.completed(),
                            "feature":value.navigation.feature()}),
    };
    json!({"item":item,"timing":timing(&entry.timing()),"completed":entry.completed,"hidden":entry.hidden,"note":entry.note})
}

fn timing(value: &AgendaTiming) -> Value {
    match value {
        AgendaTiming::Period { start, end } => json!({"kind":"period","start":start,"end":end}),
        AgendaTiming::Deadline(due) => json!({"kind":"deadline","due":due}),
        AgendaTiming::AllDay { from, to } => json!({"kind":"all_day","from":from,"to":to}),
        AgendaTiming::Undated => json!({"kind":"undated"}),
    }
}
pub(crate) fn render<O: Write, E: Write>(
    json_mode: bool,
    operation: &str,
    result: LocalResult<Value>,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    let exit = result.as_ref().err().map_or(0, |e| e.exit());
    if json_mode {
        let meta = json!({"feature":"agenda","operation":operation,"accountState":if result.as_ref().err().is_some_and(|e| matches!(e, LocalError::RegistrationRequired | LocalError::MaterialUnavailable | LocalError::MaterialCorrupt | LocalError::Storage | LocalError::StaleIdentity)) {"unavailable"} else {"active"}});
        let value = match result {
            Ok(data) => {
                json!({"schemaVersion":CLI_JSON_SCHEMA_VERSION,"ok":true,"data":data,"meta":meta})
            }
            Err(error) => {
                json!({"schemaVersion":CLI_JSON_SCHEMA_VERSION,"ok":false,"error":{"code":error,"kind":"local","retryable":false,"message":error.message()},"meta":meta})
            }
        };
        if serde_json::to_writer(&mut *stdout, &value).is_err() || writeln!(stdout).is_err() {
            return 7;
        }
    } else {
        match result {
            Ok(data) if operation == "unsynced" => {
                if writeln!(stdout, "本机日程待同步记录：{}", data["count"]).is_err() {
                    return 7;
                }
            }
            Ok(data) if operation == "list" => {
                if human_list(&data, stdout) != 0 {
                    return 7;
                }
            }
            Ok(data) => {
                if serde_json::to_writer_pretty(&mut *stdout, &data).is_err()
                    || writeln!(stdout).is_err()
                {
                    return 7;
                }
            }
            Err(error) => {
                if writeln!(stderr, "错误：{}", error.message()).is_err() {
                    return 7;
                }
            }
        }
    }
    crate::runtime::finish_output(exit, stdout, stderr)
}

fn human_list<O: Write>(data: &Value, stdout: &mut O) -> i32 {
    if writeln!(
        stdout,
        "本机日程 {} 至 {}（结束日期不含）",
        data["from"].as_str().unwrap_or(""),
        data["to"].as_str().unwrap_or("")
    )
    .is_err()
    {
        return 7;
    }
    if let Some(entries) = data["entries"].as_array() {
        for entry in entries {
            let item = &entry["item"];
            let title = item["occurrence"]["content"]["title"]
                .as_str()
                .or_else(|| item["title"].as_str())
                .unwrap_or("");
            let state = if entry["completed"] == true {
                "已完成"
            } else {
                "未完成"
            };
            if writeln!(stdout, "{state} | {title} | {}", entry["timing"]).is_err() {
                return 7;
            }
        }
        if entries.is_empty() && writeln!(stdout, "范围内没有事项。").is_err() {
            return 7;
        }
    }
    if let Some(sources) = data["sources"].as_array() {
        for source in sources {
            let missing = source["missingScopes"].as_array().map_or(0, Vec::len);
            let stale = source["observations"]
                .as_array()
                .map_or(0, |v| v.iter().filter(|o| o["fresh"] == false).count());
            if writeln!(
                stdout,
                "学校缓存 {}：缺少 {missing} 个范围，过期或不完整 {stale} 个范围。",
                source["feature"]
            )
            .is_err()
            {
                return 7;
            }
        }
    }

    0
}
