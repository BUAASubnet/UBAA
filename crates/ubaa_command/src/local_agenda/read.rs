//! 日程结果仅消费本地 facade；本模块没有网络客户端。
use super::{AgendaAccess, LocalError, LocalResult, agenda_error};
use crate::{AgendaCommand, CLI_JSON_SCHEMA_VERSION, Cli, Command};
use chrono::{Timelike, Utc};
use serde_json::{Value, json};
use std::io::Write;
use ubaa_core::facade::{
    AgendaEntryItem, AgendaQuery, AgendaTime, AgendaTiming, CacheKey, CacheLimits, OfflineCache,
};

impl AgendaAccess {
    pub(super) fn read_command(&self, command: &AgendaCommand) -> LocalResult<Value> {
        let index = self.active()?;
        let identity = index
            .active
            .as_ref()
            .ok_or(LocalError::RegistrationRequired)?;
        let account = &index.accounts[identity];
        let store = self.agenda(account)?;
        let data = match command {
            AgendaCommand::Unsynced => {
                json!({"count": store.unsynced_count().map_err(agenda_error)?})
            }
            AgendaCommand::Show { id } => {
                json!({"item": store.get(*id).map_err(agenda_error)?.ok_or(LocalError::NotFound)?})
            }
            AgendaCommand::List {
                from,
                to,
                school_cache,
                route,
                term,
            } => {
                if from >= to || (*to - *from).num_days() > 3660 {
                    return Err(LocalError::InvalidInput);
                }
                let now = AgendaTime::new(
                    Utc::now()
                        .with_nanosecond(0)
                        .ok_or(LocalError::InvalidInput)?
                        .fixed_offset(),
                );
                let (entries, sources) = if *school_cache {
                    let route = route.ok_or(LocalError::InvalidInput)?.into();
                    let term = term
                        .as_ref()
                        .filter(|s| !s.trim().is_empty())
                        .ok_or(LocalError::InvalidInput)?;
                    let key: [u8; 32] = account
                        .cache_key
                        .as_deref()
                        .ok_or(LocalError::CacheKeyMissing)?
                        .try_into()
                        .map_err(|_| LocalError::MaterialCorrupt)?;
                    // 缺文件不调用 OfflineCache::open，避免读取操作创建空缓存并掩盖缺来源。
                    let path = self
                        .paths
                        .root
                        .join("business-cache")
                        .join(format!("{}.sqlite", account.alias));
                    if !path.try_exists().map_err(|_| LocalError::Storage)? {
                        return Err(LocalError::CacheMissing);
                    }
                    let cache = OfflineCache::open(
                        &self.paths.root,
                        &account.alias,
                        identity,
                        CacheKey::new(key),
                        CacheLimits::default(),
                    )
                    .map_err(|_| LocalError::CacheCorrupt)?;
                    let result = cache
                        .query_agenda(
                            &store,
                            &AgendaQuery::new(route, term.clone(), *from, *to, now),
                        )
                        .map_err(|_| LocalError::CacheCorrupt)?;
                    let sources = cache_sources(&result, now);
                    (result.entries, sources)
                } else {
                    (
                        store
                            .query_local_agenda(&AgendaQuery::new(
                                ubaa_core::facade::ConnectionMode::Direct,
                                String::new(),
                                *from,
                                *to,
                                now,
                            ))
                            .map_err(agenda_error)?
                            .entries,
                        Vec::new(),
                    )
                };
                let entries: Vec<Value> = entries.iter().map(entry_value).collect();
                json!({"from":from,"to":to,"entries":entries,"sources":sources,"schoolCacheIncluded":school_cache})
            }
        };
        self.paths.validate()?;
        let latest = self.active()?;
        if latest.epoch != index.epoch {
            return Err(LocalError::StaleIdentity);
        }
        Ok(data)
    }
}
fn cache_sources(result: &ubaa_core::facade::AgendaQueryResult, now: AgendaTime) -> Vec<Value> {
    result
        .sources
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

fn entry_value(entry: &ubaa_core::facade::AgendaEntry) -> Value {
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
/// 独立本地执行入口，打开客户端前即可调用；锁持续到输出完成。
pub fn run_agenda<O: Write, E: Write>(
    cli: &Cli,
    root: &std::path::Path,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    execute_local(cli, root).render(cli.json, stdout, stderr)
}
pub(crate) struct LocalAttempt {
    operation: String,
    result: LocalResult<Value>,
    // 原兼容入口的作用域锁保持到交付完成。
    _access: Option<AgendaAccess>,
}
pub(crate) fn execute_local(cli: &Cli, root: &std::path::Path) -> LocalAttempt {
    let Command::Agenda(arguments) = &cli.command else {
        return LocalAttempt {
            operation: "list".into(),
            result: Err(LocalError::InvalidInput),
            _access: None,
        };
    };
    let access = AgendaAccess::open(root);
    let result = access
        .as_ref()
        .map_err(|e| *e)
        .and_then(|a| a.read_command(&arguments.command));
    LocalAttempt {
        operation: arguments.command.operation().into(),
        result,
        _access: access.ok(),
    }
}
impl LocalAttempt {
    pub(crate) fn render(
        self,
        json: bool,
        stdout: &mut impl Write,
        stderr: &mut impl Write,
    ) -> i32 {
        render(json, &self.operation, self.result, stdout, stderr)
    }
}
pub(crate) fn render_stop(
    cli: &Cli,
    reason: crate::StopReason,
    stdout: &mut impl Write,
    stderr: &mut impl Write,
) -> i32 {
    let Command::Agenda(arguments) = &cli.command else {
        return 7;
    };
    if writeln!(stderr, "{}", reason.message()).is_err() {
        return 7;
    }
    if cli.json {
        let value = json!({"schemaVersion":CLI_JSON_SCHEMA_VERSION,"ok":false,"error":{"code":"storage","kind":"local","retryable":false,"message":reason.message()},"meta":{"feature":"agenda","operation":arguments.command.operation(),"accountState":"unavailable"}});
        if serde_json::to_writer(&mut *stdout, &value).is_err() || writeln!(stdout).is_err() {
            return 7;
        }
    }
    crate::runtime::finish_output(7, stdout, stderr)
}

fn render<O: Write, E: Write>(
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
