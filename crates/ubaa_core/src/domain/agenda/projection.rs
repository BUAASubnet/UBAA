//! 学校公开读结果的日程投影；类型中没有学校写操作或资格。
use super::{AgendaOccurrence, AgendaTime, SchoolAgendaKey};
use crate::domain::{JudgeSubmissionStatus, ReadonlyFeature, SpocSubmissionStatus};
use chrono::{Duration, NaiveDate};

/// 不完整时段保留已知端点；日期已知而时刻未知的考试使用全天占位。
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum AgendaTiming {
    Period {
        start: Option<AgendaTime>,
        end: Option<AgendaTime>,
    },
    Deadline(AgendaTime),
    AllDay {
        from: NaiveDate,
        to: NaiveDate,
    },
    Undated,
}
impl AgendaTiming {
    #[must_use]
    pub fn sort_time(&self) -> Option<AgendaTime> {
        match self {
            Self::Period { start, end } => start.or(*end),
            Self::Deadline(due) => Some(*due),
            Self::AllDay { from, .. } => Some(super::campus_midnight(*from)),
            Self::Undated => None,
        }
    }
    /// 沿首页规则：截止或开始严格晚于现在，且剩余不超过 48 小时。
    #[must_use]
    pub fn is_soon_at(&self, now: AgendaTime) -> bool {
        let time = match self {
            Self::Period { start, .. } => *start,
            Self::Deadline(due) => Some(*due),
            _ => None,
        };
        time.is_some_and(|t| {
            let remaining = t.datetime - now.datetime;
            remaining > Duration::zero() && remaining <= Duration::hours(48)
        })
    }
    pub(crate) fn intersects(&self, from: NaiveDate, to: NaiveDate) -> bool {
        let point = |t: AgendaTime| from <= t.datetime.date_naive() && t.datetime.date_naive() < to;
        match self {
            Self::Period {
                start: Some(start),
                end: Some(end),
            } if end > start => {
                start.datetime < super::campus_midnight(to).datetime
                    && end.datetime > super::campus_midnight(from).datetime
            }
            Self::Period { start, end } => start.or(*end).is_some_and(point),
            Self::Deadline(due) => point(*due),
            Self::AllDay {
                from: start,
                to: end,
            } => *start < to && *end > from,
            Self::Undated => true,
        }
    }
}

/// 上游原始公开状态与本地完成分开保留。未知状态不推断为完成。
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum SchoolAgendaStatus {
    Schedule {
        begin_time: Option<String>,
        end_time: Option<String>,
    },
    Exam {
        status: Option<i32>,
    },
    Bykc {
        checkin: Option<i32>,
        pass: Option<i32>,
    },
    Spoc {
        status: SpocSubmissionStatus,
        text: String,
    },
    Judge {
        status: JudgeSubmissionStatus,
        text: String,
    },
    Cgyy {
        order_status: Option<i32>,
        check_status: Option<i32>,
    },
    Signin {
        sign_status: Option<i32>,
    },
    Ygdk {
        week_count: Option<i32>,
        term_count: i32,
    },
}
impl SchoolAgendaStatus {
    #[must_use]
    pub fn completed(&self) -> bool {
        match self {
            Self::Spoc { status, .. } => *status == SpocSubmissionStatus::Submitted,
            Self::Judge { status, .. } => *status == JudgeSubmissionStatus::Submitted,
            Self::Bykc { checkin, .. } => matches!(checkin, Some(1)),
            Self::Signin { sign_status } => *sign_status == Some(1),
            _ => false,
        }
    }
}

/// 宿主按 feature 打开原功能，再用这些公开标识定位详情。
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum AgendaNavigation {
    Schedule {
        term: String,
        week: i32,
        course_code: String,
        serial: Option<String>,
        day: i32,
        section: i32,
    },
    Exam {
        term: String,
        task_id: Option<String>,
        course_no: Option<String>,
        course_name: String,
        date: NaiveDate,
        start_time: Option<String>,
    },
    Bykc {
        course_id: i64,
    },
    Spoc {
        assignment_id: String,
    },
    Judge {
        course_id: String,
        assignment_id: String,
    },
    Cgyy {
        order_id: i32,
    },
    Signin {
        course_id: String,
        date: NaiveDate,
    },
    Ygdk,
}
impl AgendaNavigation {
    #[must_use]
    pub fn feature(&self) -> ReadonlyFeature {
        match self {
            Self::Schedule { .. } => ReadonlyFeature::Schedule,
            Self::Exam { .. } => ReadonlyFeature::Exam,
            Self::Bykc { .. } => ReadonlyFeature::Bykc,
            Self::Spoc { .. } => ReadonlyFeature::Spoc,
            Self::Judge { .. } => ReadonlyFeature::Judge,
            Self::Cgyy { .. } => ReadonlyFeature::Cgyy,
            Self::Signin { .. } => ReadonlyFeature::Signin,
            Self::Ygdk => ReadonlyFeature::Ygdk,
        }
    }
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SchoolAgendaItem {
    pub key: SchoolAgendaKey,
    pub timing: AgendaTiming,
    /// 来源的排序时刻，可与已知端点不同；不补写未知的学校开始时间。
    pub sort_time: Option<AgendaTime>,
    pub title: String,
    pub subtitle: String,
    pub location: Option<String>,
    pub status_label: String,
    pub upstream_status: SchoolAgendaStatus,
    pub navigation: AgendaNavigation,
    /// 完整日程保留已完成和历史条目；此标记严格沿用 Dart 首页过滤。
    pub home_todo: bool,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum AgendaEntryItem {
    Local(AgendaOccurrence),
    School(SchoolAgendaItem),
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AgendaEntry {
    pub item: AgendaEntryItem,
    pub completed: bool,
    pub hidden: bool,
    pub note: Option<String>,
}
impl AgendaEntry {
    #[must_use]
    pub fn sort_time(&self) -> Option<AgendaTime> {
        match &self.item {
            AgendaEntryItem::School(v) => v.sort_time,
            AgendaEntryItem::Local(_) => self.timing().sort_time(),
        }
    }
    #[must_use]
    pub fn title(&self) -> &str {
        match &self.item {
            AgendaEntryItem::Local(v) => &v.content.title,
            AgendaEntryItem::School(v) => &v.title,
        }
    }
    #[must_use]
    pub fn timing(&self) -> AgendaTiming {
        match &self.item {
            AgendaEntryItem::School(v) => v.timing.clone(),
            AgendaEntryItem::Local(v) => {
                let c = &v.content;
                if c.all_day
                    && let Some((start, end)) = c.start.zip(c.end)
                {
                    AgendaTiming::AllDay {
                        from: start.datetime.date_naive(),
                        to: end.datetime.date_naive(),
                    }
                } else if c.start.is_some() {
                    AgendaTiming::Period {
                        start: c.start,
                        end: c.end,
                    }
                } else {
                    c.due.map_or(AgendaTiming::Undated, AgendaTiming::Deadline)
                }
            }
        }
    }
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct YgdkAgendaSettings {
    pub enabled: bool,
    pub week_done: bool,
    pub term_done: bool,
}
impl Default for YgdkAgendaSettings {
    fn default() -> Self {
        Self {
            enabled: true,
            week_done: false,
            term_done: false,
        }
    }
}
