use super::{
    LocalError, LocalResult,
    format::{cache_sources, entry_value, render, source_values},
};
use crate::{
    AgendaCommand, AgendaCompletionOverride, AgendaOverlayCommand, AgendaScope, Command,
    CommandControl, PreparedCommand,
};
use chrono::{DateTime, Timelike, Utc};
use serde::Deserialize;
use serde_json::{Value, json};
use std::{
    collections::BTreeSet,
    fs::{self, OpenOptions},
    io::Write,
    path::{Path, PathBuf},
};
use ubaa_core::facade::{
    AgendaContent, AgendaExportOptions, AgendaItem, AgendaKind, AgendaQuery, AgendaStore,
    AgendaTime, CacheError, OfflineCache, SchoolAgendaKey, SchoolAgendaOverlay, SharedAccountGuard,
};

pub struct SharedAgendaResult {
    operation: String,
    result: LocalResult<Value>,
    ics: Option<String>,
    scope: SharedAccountGuard,
    diagnostic: Option<String>,
}
impl SharedAgendaResult {
    pub fn render(
        mut self,
        json: bool,
        control: &CommandControl,
        stdout: &mut impl Write,
        stderr: &mut impl Write,
    ) -> i32 {
        if control.check().is_err() {
            self.result = Err(LocalError::Storage);
            self.ics = None;
        }
        if self.scope.check().is_err() {
            self.result = Err(LocalError::StaleIdentity);
            self.ics = None;
        }
        if let Some(message) = self.diagnostic
            && writeln!(stderr, "{message}").is_err()
        {
            return 7;
        }
        if let Some(ics) = self.ics {
            if stdout.write_all(ics.as_bytes()).is_err() {
                return 7;
            }
            crate::runtime::finish_output(0, stdout, stderr)
        } else {
            render(json, &self.operation, self.result, stdout, stderr)
        }
    }
}
/// 同一输入快照只执行一次，学校缓存句柄由共享账号服务提供。
#[must_use]
pub fn execute_shared_agenda(
    prepared: &PreparedCommand,
    store: &AgendaStore,
    cache: Option<&OfflineCache>,
    scope: SharedAccountGuard,
    control: &CommandControl,
) -> SharedAgendaResult {
    let Command::Agenda(arguments) = &prepared.plan.cli().command else {
        unreachable!("仅本地日程计划使用此入口")
    };
    let operation = arguments.command.operation().to_owned();
    let mut ics = None;
    let mut diagnostic = None;
    let result = (|| {
        control.check().map_err(|_| LocalError::Storage)?;
        scope.check().map_err(|_| LocalError::StaleIdentity)?;
        let now = AgendaTime::new(
            Utc::now()
                .with_nanosecond(0)
                .ok_or(LocalError::InvalidInput)?
                .fixed_offset(),
        );
        let data = execute(
            &arguments.command,
            &prepared.input,
            prepared.plan.cli().json,
            store,
            cache,
            &scope,
            control,
            now,
            &mut ics,
            &mut diagnostic,
        )?;
        control.check().map_err(|_| LocalError::Storage)?;
        scope.check().map_err(|_| LocalError::StaleIdentity)?;
        Ok(data)
    })();
    SharedAgendaResult {
        operation,
        result,
        ics,
        scope,
        diagnostic,
    }
}
fn error(error: CacheError) -> LocalError {
    match error {
        CacheError::InvalidInput => LocalError::InvalidInput,
        CacheError::Inactive => LocalError::RegistrationRequired,
        CacheError::Superseded => LocalError::StaleIdentity,
        _ => LocalError::AgendaCorrupt,
    }
}
fn time(raw: &str) -> LocalResult<AgendaTime> {
    DateTime::parse_from_rfc3339(raw)
        .map(AgendaTime::new)
        .map_err(|_| LocalError::InvalidInput)
}
fn occurrence(scope: AgendaScope, at: Option<&str>) -> LocalResult<Option<AgendaTime>> {
    if !matches!(scope, AgendaScope::All) && at.is_none() {
        return Err(LocalError::InvalidInput);
    }
    at.map(time).transpose()
}
pub(crate) fn validate_arguments(command: &AgendaCommand) -> LocalResult<()> {
    match command {
        AgendaCommand::List { from, to, .. } | AgendaCommand::Export { from, to, .. }
            if from >= to || (*to - *from).num_days() > 3660 =>
        {
            Err(LocalError::InvalidInput)
        }
        AgendaCommand::Edit { scope, at, .. } | AgendaCommand::Delete { scope, at, .. } => {
            occurrence(*scope, at.as_deref()).map(|_| ())
        }
        AgendaCommand::Complete(args) | AgendaCommand::Reopen(args) => {
            args.at.as_deref().map(time).transpose().map(|_| ())
        }
        _ => Ok(()),
    }
}
pub(crate) fn validate_input(command: &AgendaCommand, input: &[u8]) -> LocalResult<()> {
    match command {
        AgendaCommand::Create { .. } | AgendaCommand::Edit { .. } => {
            let value = draft(input)?;
            value.content()?;
            for date in value.exdates.unwrap_or_default() {
                time(&date)?;
            }
        }
        AgendaCommand::Overlay {
            command:
                AgendaOverlayCommand::Set {
                    note_file: Some(_), ..
                },
        } => {
            std::str::from_utf8(input).map_err(|_| LocalError::InvalidInput)?;
        }
        _ => {}
    }
    Ok(())
}
pub(crate) fn input_path(command: &AgendaCommand) -> Option<&Path> {
    match command {
        AgendaCommand::Create { input, .. } | AgendaCommand::Edit { input, .. } => Some(input),
        AgendaCommand::Overlay {
            command:
                AgendaOverlayCommand::Set {
                    note_file: Some(path),
                    ..
                },
        } => Some(path),
        _ => None,
    }
}
pub(crate) fn confirmed(command: &AgendaCommand) -> bool {
    match command {
        AgendaCommand::Create {
            confirm_local_write,
            ..
        }
        | AgendaCommand::Edit {
            confirm_local_write,
            ..
        }
        | AgendaCommand::Delete {
            confirm_local_write,
            ..
        }
        | AgendaCommand::Clear {
            confirm_local_write,
            ..
        }
        | AgendaCommand::Overlay {
            command:
                AgendaOverlayCommand::Set {
                    confirm_local_write,
                    ..
                }
                | AgendaOverlayCommand::Clear {
                    confirm_local_write,
                    ..
                },
        } => *confirm_local_write,
        AgendaCommand::Complete(args) | AgendaCommand::Reopen(args) => args.confirm_local_write,
        _ => true,
    }
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Draft {
    kind: AgendaKind,
    title: String,
    location: Option<String>,
    notes: Option<String>,
    color: Option<String>,
    start: Option<String>,
    end: Option<String>,
    #[serde(default)]
    all_day: bool,
    due: Option<String>,
    rrule: Option<String>,
    exdates: Option<Vec<String>>,
}
impl Draft {
    fn content(&self) -> LocalResult<AgendaContent> {
        Ok(AgendaContent {
            kind: self.kind,
            title: self.title.clone(),
            location: self.location.clone(),
            notes: self.notes.clone(),
            color: self.color.clone(),
            start: self.start.as_deref().map(time).transpose()?,
            end: self.end.as_deref().map(time).transpose()?,
            all_day: self.all_day,
            due: self.due.as_deref().map(time).transpose()?,
        })
    }
}
fn draft(bytes: &[u8]) -> LocalResult<Draft> {
    serde_json::from_slice(bytes).map_err(|_| LocalError::InvalidInput)
}
#[allow(clippy::too_many_arguments, clippy::too_many_lines)]
fn execute(
    command: &AgendaCommand,
    input: &[u8],
    json_mode: bool,
    store: &AgendaStore,
    cache: Option<&OfflineCache>,
    scope: &SharedAccountGuard,
    control: &CommandControl,
    now: AgendaTime,
    ics: &mut Option<String>,
    diagnostic: &mut Option<String>,
) -> LocalResult<Value> {
    if !confirmed(command) && !matches!(command, AgendaCommand::Clear { .. }) {
        return Err(LocalError::InvalidInput);
    }
    match command {
        AgendaCommand::Sync { .. } => Err(LocalError::InvalidInput),
        AgendaCommand::Unsynced => Ok(json!({"count":store.unsynced_count().map_err(error)?})),
        AgendaCommand::Show { id } => {
            Ok(json!({"item":store.get(*id).map_err(error)?.ok_or(LocalError::NotFound)?}))
        }
        AgendaCommand::List {
            from,
            to,
            school_cache,
            route,
            term,
        } => {
            let query = AgendaQuery::new(
                route.map_or(ubaa_core::facade::ConnectionMode::Direct, Into::into),
                term.clone().unwrap_or_default(),
                *from,
                *to,
                now,
            );
            let result = if *school_cache {
                cache
                    .ok_or(LocalError::CacheMissing)?
                    .query_agenda(store, &query)
            } else {
                store.query_local_agenda(&query)
            }
            .map_err(error)?;
            Ok(
                json!({"from":from,"to":to,"entries":result.entries.iter().map(entry_value).collect::<Vec<_>>(),"sources":cache_sources(&result,now),"schoolCacheIncluded":school_cache}),
            )
        }
        AgendaCommand::Create { .. } => {
            let draft = draft(input)?;
            let mut item = AgendaItem::new(draft.content()?, now);
            item.rrule = draft.rrule;
            item.exdates = draft
                .exdates
                .unwrap_or_default()
                .iter()
                .map(|v| time(v))
                .collect::<LocalResult<BTreeSet<_>>>()?;
            store.create(item.clone()).map_err(error)?;
            Ok(json!({"item":item}))
        }
        AgendaCommand::Edit { id, scope, at, .. } => {
            let draft = draft(input)?;
            let exdates = match &draft.exdates {
                Some(dates) => dates
                    .iter()
                    .map(|value| time(value))
                    .collect::<LocalResult<Vec<_>>>()?,
                None => store
                    .get(*id)
                    .map_err(error)?
                    .ok_or(LocalError::NotFound)?
                    .exdates
                    .into_iter()
                    .collect(),
            };
            let successor = store
                .edit_draft(
                    *id,
                    (*scope).into(),
                    occurrence(*scope, at.as_deref())?,
                    draft.content()?,
                    (draft.rrule, exdates),
                    now,
                )
                .map_err(error)?;
            Ok(json!({"item":store.get(*id).map_err(error)?,"successorId":successor}))
        }
        AgendaCommand::Delete { id, scope, at, .. } => {
            store
                .delete(
                    *id,
                    (*scope).into(),
                    occurrence(*scope, at.as_deref())?,
                    now,
                )
                .map_err(error)?;
            Ok(json!({"id":id,"deleted":true}))
        }
        AgendaCommand::Complete(args) | AgendaCommand::Reopen(args) => {
            let at = args.at.as_deref().map(time).transpose()?;
            store
                .complete(
                    args.id,
                    at,
                    matches!(command, AgendaCommand::Complete(_)),
                    now,
                )
                .map_err(error)?;
            Ok(json!({"item":store.get(args.id).map_err(error)?}))
        }
        AgendaCommand::Overlay { command: overlay } => {
            let (source, upstream_id) = match overlay {
                AgendaOverlayCommand::Set {
                    source,
                    upstream_id,
                    ..
                }
                | AgendaOverlayCommand::Clear {
                    source,
                    upstream_id,
                    ..
                } => (source, upstream_id),
            };
            let key = SchoolAgendaKey {
                source: source.clone(),
                upstream_id: upstream_id.clone(),
            };
            match overlay {
                AgendaOverlayCommand::Clear { .. } => {
                    store.clear_overlay(&key, now).map_err(error)?;
                }
                AgendaOverlayCommand::Set {
                    completion,
                    hidden,
                    note_file,
                    ..
                } => {
                    let mut value = store
                        .overlay(&key)
                        .map_err(error)?
                        .filter(|v| v.deleted_at.is_none())
                        .unwrap_or(SchoolAgendaOverlay {
                            key: key.clone(),
                            completed_at: None,
                            completion_override: false,
                            hidden: false,
                            note: None,
                            updated_at: now,
                            deleted_at: None,
                            locally_modified: true,
                        });
                    if let Some(completion) = completion {
                        value.completed_at =
                            matches!(completion, AgendaCompletionOverride::Complete).then_some(now);
                        value.completion_override =
                            !matches!(completion, AgendaCompletionOverride::Inherit);
                    }
                    if let Some(hidden) = hidden {
                        value.hidden = *hidden;
                    }
                    if note_file.is_some() {
                        let note =
                            std::str::from_utf8(input).map_err(|_| LocalError::InvalidInput)?;
                        value.note = (!note.is_empty()).then(|| note.to_owned());
                    }
                    store.set_overlay(value, now).map_err(error)?;
                }
            }
            Ok(json!({"overlay":store.overlay(&key).map_err(error)?}))
        }
        AgendaCommand::Clear {
            expected_unsynced,
            confirm_local_write,
        } => {
            if !confirm_local_write || expected_unsynced.is_none() {
                let count = store.unsynced_count().map_err(error)?;
                *diagnostic = Some(format!(
                    "本机日程有 {count} 条未同步记录；清除需要 --confirm-local-write 和 --expected-unsynced {count}"
                ));
                return Err(LocalError::InvalidInput);
            }
            let expected = expected_unsynced.ok_or(LocalError::InvalidInput)?;
            Ok(
                json!({"clearedUnsynced":store.clear_local_data_if_unsynced(expected).map_err(error)?}),
            )
        }
        AgendaCommand::Export {
            from,
            to,
            school_cache,
            route,
            term,
            output,
            stdout,
            overwrite,
            include_hidden,
            exclude_completed,
        } => {
            if *stdout && json_mode {
                return Err(LocalError::InvalidInput);
            }
            let mut query = AgendaQuery::new(
                route.map_or(ubaa_core::facade::ConnectionMode::Direct, Into::into),
                term.clone().unwrap_or_default(),
                *from,
                *to,
                now,
            );
            query.include_hidden = *include_hidden;
            let (snapshot, sources) = if *school_cache {
                let result = cache
                    .ok_or(LocalError::CacheMissing)?
                    .export_agenda_ics(store, &query, !exclude_completed)
                    .map_err(error)?;
                (result.snapshot, Some(result.sources))
            } else {
                (
                    store
                        .export_local_ics(&AgendaExportOptions {
                            from: *from,
                            to: *to,
                            generated_at: now,
                            include_hidden: *include_hidden,
                            include_completed: !exclude_completed,
                        })
                        .map_err(error)?,
                    None,
                )
            };
            if *stdout {
                *ics = Some(snapshot.ics);
            } else {
                let path = output.as_ref().ok_or(LocalError::InvalidInput)?;
                deliver_file(path, snapshot.ics.as_bytes(), *overwrite, scope, control)?;
            }
            Ok(
                json!({"from":from,"to":to,"exportedCount":snapshot.exported_count,"skippedUnknownTimeCount":snapshot.skipped_unknown_time_count,"delivery":if *stdout{"stdout"}else{"file"},"schoolCacheIncluded":school_cache,"sources":sources.map(|sources|source_values(&sources,now))}),
            )
        }
    }
}
struct PendingFile(PathBuf);
impl Drop for PendingFile {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.0);
    }
}
fn deliver_file(
    path: &Path,
    bytes: &[u8],
    overwrite: bool,
    scope: &SharedAccountGuard,
    control: &CommandControl,
) -> LocalResult<()> {
    let parent = path
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    let temporary = PendingFile(parent.join(format!(".ubaa-{}.ics", uuid::Uuid::new_v4())));
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut file = options
        .open(&temporary.0)
        .map_err(|_| LocalError::Storage)?;
    file.write_all(bytes)
        .and_then(|()| file.sync_all())
        .map_err(|_| LocalError::Storage)?;
    drop(file);
    control.check().map_err(|_| LocalError::Storage)?;
    scope
        .with_current(|| {
            if overwrite {
                if let Ok(metadata) = fs::symlink_metadata(path)
                    && !metadata.file_type().is_file()
                {
                    return Err(LocalError::Storage);
                }
                fs::rename(&temporary.0, path).map_err(|_| LocalError::Storage)?;
            } else {
                fs::hard_link(&temporary.0, path).map_err(|_| LocalError::Storage)?;
            }
            #[cfg(unix)]
            fs::File::open(parent)
                .and_then(|p| p.sync_all())
                .map_err(|_| LocalError::Storage)?;
            Ok(())
        })
        .map_err(|_| LocalError::StaleIdentity)?
}
