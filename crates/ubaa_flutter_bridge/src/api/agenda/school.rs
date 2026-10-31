//! 学校投影只携带公开读取状态、跳转标识和缓存证据。
use super::models::{BridgeAgendaOccurrence, BridgeAgendaTime, BridgeSchoolAgendaKey};
use crate::api::{client::BridgeConnectionMode, offline::BridgeCacheFailure};
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeAgendaFeature {
    Bykc,
    Spoc,
    Judge,
    Cgyy,
    Signin,
    Exam,
    Ygdk,
    Schedule,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeAgendaTimingKind {
    Period,
    Deadline,
    AllDay,
    Undated,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BridgeAgendaTiming {
    pub kind: BridgeAgendaTimingKind,
    pub start: Option<BridgeAgendaTime>,
    pub end: Option<BridgeAgendaTime>,
    pub due: Option<BridgeAgendaTime>,
    pub from: Option<String>,
    pub to: Option<String>,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeAgendaSubmission {
    Submitted,
    Partial,
    Unsubmitted,
    Unknown,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BridgeAgendaUpstreamStatus {
    pub feature: BridgeAgendaFeature,
    pub completed: bool,
    pub begin_time: Option<String>,
    pub end_time: Option<String>,
    pub exam_status: Option<i32>,
    pub checkin: Option<i32>,
    pub pass: Option<i32>,
    pub submission: Option<BridgeAgendaSubmission>,
    pub text: Option<String>,
    pub order_status: Option<i32>,
    pub check_status: Option<i32>,
    pub sign_status: Option<i32>,
    pub week_count: Option<i32>,
    pub term_count: Option<i32>,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BridgeAgendaNavigation {
    pub feature: BridgeAgendaFeature,
    pub term: Option<String>,
    pub week: Option<i32>,
    pub course_code: Option<String>,
    pub serial: Option<String>,
    pub day: Option<i32>,
    pub section: Option<i32>,
    pub course_id: Option<String>,
    pub bykc_course_id: Option<i64>,
    pub assignment_id: Option<String>,
    pub order_id: Option<i32>,
    pub task_id: Option<String>,
    pub course_no: Option<String>,
    pub course_name: Option<String>,
    pub date: Option<String>,
    pub start_time: Option<String>,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BridgeSchoolAgendaItem {
    pub key: BridgeSchoolAgendaKey,
    pub timing: BridgeAgendaTiming,
    pub sort_time: Option<BridgeAgendaTime>,
    pub title: String,
    pub subtitle: String,
    pub location: Option<String>,
    pub status_label: String,
    pub upstream_status: BridgeAgendaUpstreamStatus,
    pub navigation: BridgeAgendaNavigation,
    pub home_todo: bool,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BridgeAgendaEntry {
    pub local: Option<BridgeAgendaOccurrence>,
    pub school: Option<BridgeSchoolAgendaItem>,
    pub timing: BridgeAgendaTiming,
    pub sort_time: Option<BridgeAgendaTime>,
    pub soon: bool,
    pub completed: bool,
    pub hidden: bool,
    pub note: Option<String>,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeAgendaCacheKind {
    BykcChosen,
    SpocSelection,
    SpocTerm,
    JudgeSummaries,
    CgyyOrders,
    SigninToday,
    Exams,
    YgdkOverviewSelection,
    YgdkOverviewPeriod,
    ScheduleWeeks,
    ScheduleWeek,
    ImportedSchedules,
    Unknown,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BridgeAgendaCacheScope {
    pub route: BridgeConnectionMode,
    pub kind: BridgeAgendaCacheKind,
    pub term: Option<String>,
    pub week: Option<i32>,
    pub date: Option<String>,
    pub page: Option<i32>,
    pub size: Option<i32>,
    pub include_expired: Option<bool>,
    pub classify_id: Option<i32>,
    pub term_id: Option<i32>,
    pub week_start: Option<String>,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeAgendaCompleteness {
    Complete,
    Partial,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BridgeAgendaObservation {
    pub scope: BridgeAgendaCacheScope,
    pub fetched_at: i64,
    pub last_verified_at: i64,
    pub last_attempt_at: i64,
    pub last_attempt_succeeded: bool,
    pub completeness: BridgeAgendaCompleteness,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BridgeAgendaSource {
    pub feature: BridgeAgendaFeature,
    pub observations: Vec<BridgeAgendaObservation>,
    pub missing_scopes: Vec<BridgeAgendaCacheScope>,
    pub semester_imported: Option<bool>,
    pub unprojectable_count: u32,
}
/// 四个独立筛选开关，保持宿主的阳光提醒状态。
#[allow(clippy::struct_excessive_bools)]
#[derive(Clone, Debug)]
pub struct BridgeAgendaQuery {
    pub route: BridgeConnectionMode,
    pub term: String,
    pub from: String,
    pub to: String,
    pub now: BridgeAgendaTime,
    pub include_hidden: bool,
    pub ygdk_enabled: bool,
    pub ygdk_week_done: bool,
    pub ygdk_term_done: bool,
}
#[derive(Clone, Debug)]
pub struct BridgeAgendaQueryResult {
    pub entries: Vec<BridgeAgendaEntry>,
    pub sources: Vec<BridgeAgendaSource>,
    /// 学校缓存不可读时仍返回本机事项；日程故障单独通过 `BridgeAgendaError` 返回。
    pub school_cache_failure: Option<BridgeCacheFailure>,
}
