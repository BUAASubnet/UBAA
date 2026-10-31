//! 独立日程通道的显式值类型；字符串只承载有格式约定的标识和时间。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeAgendaFailure {
    Unavailable,
    InvalidInput,
    Corrupt,
    UnsupportedVersion,
    Inactive,
    Superseded,
    Capacity,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BridgeAgendaError {
    pub failure: BridgeAgendaFailure,
}
impl std::fmt::Display for BridgeAgendaError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("本机日程操作失败")
    }
}
impl std::error::Error for BridgeAgendaError {}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BridgeAgendaTime {
    pub rfc3339: String,
    pub timezone: String,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeAgendaKind {
    Event,
    Task,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BridgeAgendaContent {
    pub kind: BridgeAgendaKind,
    pub title: String,
    pub location: Option<String>,
    pub notes: Option<String>,
    pub color: Option<String>,
    pub start: Option<BridgeAgendaTime>,
    pub end: Option<BridgeAgendaTime>,
    pub all_day: bool,
    pub due: Option<BridgeAgendaTime>,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BridgeAgendaDraft {
    pub content: BridgeAgendaContent,
    pub rrule: Option<String>,
    pub exdates: Vec<BridgeAgendaTime>,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BridgeAgendaOverride {
    pub recurrence_id: String,
    pub content: BridgeAgendaContent,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BridgeAgendaCompletion {
    pub recurrence_id: String,
    pub completed_at: Option<BridgeAgendaTime>,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BridgeAgendaItem {
    pub id: String,
    pub content: BridgeAgendaContent,
    pub rrule: Option<String>,
    pub exdates: Vec<BridgeAgendaTime>,
    pub overrides: Vec<BridgeAgendaOverride>,
    pub completions: Vec<BridgeAgendaCompletion>,
    pub created_at: BridgeAgendaTime,
    pub updated_at: BridgeAgendaTime,
    pub deleted_at: Option<BridgeAgendaTime>,
    pub locally_modified: bool,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BridgeAgendaOccurrence {
    pub item_id: String,
    pub recurrence_id: String,
    pub content: BridgeAgendaContent,
    pub completed_at: Option<BridgeAgendaTime>,
    pub overridden: bool,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeAgendaEditScope {
    This,
    ThisAndFuture,
    All,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BridgeSchoolAgendaKey {
    pub source: String,
    pub upstream_id: String,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BridgeAgendaOverlayDraft {
    pub key: BridgeSchoolAgendaKey,
    pub completed_at: Option<BridgeAgendaTime>,
    pub completion_override: bool,
    pub hidden: bool,
    pub note: Option<String>,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BridgeAgendaOverlay {
    pub value: BridgeAgendaOverlayDraft,
    pub updated_at: BridgeAgendaTime,
    pub deleted_at: Option<BridgeAgendaTime>,
    pub locally_modified: bool,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeTeachingWeekPattern {
    Every,
    Odd,
    Even,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BridgeTeachingWeekInput {
    pub monday: String,
    pub first: u32,
    pub last: u32,
    pub pattern: BridgeTeachingWeekPattern,
    /// 1 为星期一，7 为星期日。
    pub weekday: u32,
    pub hour: u32,
    pub minute: u32,
    pub second: u32,
    pub skips: Vec<String>,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BridgeTeachingWeekRule {
    pub start: BridgeAgendaTime,
    pub rrule: String,
    pub exdates: Vec<BridgeAgendaTime>,
}
