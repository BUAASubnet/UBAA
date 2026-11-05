use crate::domain::agenda::{
    AgendaContent, AgendaItem, AgendaTime, SchoolAgendaKey, SchoolAgendaOverlay,
};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use uuid::Uuid;

#[derive(Deserialize, Serialize)]
#[serde(remote = "AgendaItem")]
pub(super) struct ItemValue {
    id: Uuid,
    content: AgendaContent,
    rrule: Option<String>,
    exdates: BTreeSet<AgendaTime>,
    overrides: BTreeMap<String, AgendaContent>,
    completions: BTreeMap<String, Option<AgendaTime>>,
    created_at: AgendaTime,
    updated_at: AgendaTime,
    deleted_at: Option<AgendaTime>,
    #[serde(skip)]
    locally_modified: bool,
}
#[derive(Deserialize, Serialize)]
#[serde(remote = "SchoolAgendaOverlay")]
pub(super) struct OverlayValue {
    key: SchoolAgendaKey,
    completed_at: Option<AgendaTime>,
    completion_override: bool,
    hidden: bool,
    note: Option<String>,
    updated_at: AgendaTime,
    deleted_at: Option<AgendaTime>,
    #[serde(skip)]
    locally_modified: bool,
}
