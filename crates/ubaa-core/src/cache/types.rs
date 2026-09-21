//! 缓存持久合同只包含可再次阅读的数据，不包含写入资格。
use crate::domain::{
    Assignment, ConnectionMode, Course, JudgeAssignmentDetail, JudgeAssignmentSummary, TodayClass,
    WeeklySchedule,
};
use serde::{Deserialize, Serialize};

/// 独立于 Session 和 Bridge 的业务缓存版本。
pub const CACHE_SCHEMA_VERSION: u32 = 1;

/// 精确业务查询；日期使用既有校园日期，不在读取时替换成今天。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum CacheQuery {
    ScheduleToday {
        date: String,
    },
    ScheduleWeek {
        term: String,
        week: i32,
    },
    JudgeCourses,
    JudgeCourseReview {
        course_id: String,
    },
    JudgeAssignments {
        course_id: String,
    },
    JudgeSummaries {
        include_expired: bool,
    },
    JudgeDetail {
        course_id: String,
        assignment_id: String,
    },
}

/// 一个账号库内的实际来源和精确查询，不使用 Auto 作为数据来源。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct CacheScope {
    pub route: ConnectionMode,
    pub query: CacheQuery,
}

/// 仅白名单领域值可写入，禁止任意 JSON、原始响应或 action 投影。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum CachePayload {
    Today(Vec<TodayClass>),
    Week(WeeklySchedule),
    JudgeCourses(Vec<Course>),
    JudgeCourseReview(JudgeCourseReview),
    JudgeAssignments(Vec<Assignment>),
    JudgeSummaries(Vec<JudgeAssignmentSummary>),
    JudgeDetail(Box<JudgeAssignmentDetail>),
}

/// 部分结果不能宣称本次完整，也不能清空旧的完整集合。
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum CacheCompleteness {
    Complete,
    Partial,
}

/// 一个缓存范围的不可写读取记录。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct CacheRecord {
    pub scope: CacheScope,
    pub payload: CachePayload,
    pub fetched_at: i64,
    pub last_attempt_at: i64,
    pub last_verified_at: i64,
    pub last_attempt_succeeded: bool,
    pub revision: i64,
    pub completeness: CacheCompleteness,
}
impl CacheRecord {
    /// 时钟倒退或上次尝试失败时不能把旧数据称为新鲜。
    #[must_use]
    pub fn is_fresh(&self, now: i64, ttl_seconds: i64) -> bool {
        self.last_attempt_succeeded
            && self.completeness == CacheCompleteness::Complete
            && self.last_attempt_at == self.last_verified_at
            && ttl_seconds >= 0
            && now
                .checked_sub(self.last_verified_at)
                .is_some_and(|age| age >= 0 && age <= ttl_seconds)
    }
}

/// 账号内密文业务载荷限额；数据库页开销独立受 `SQLite` 页数约束。
#[derive(Clone, Copy, Debug)]
pub struct CacheLimits {
    pub soft_bytes: u64,
    pub hard_bytes: u64,
}
impl Default for CacheLimits {
    fn default() -> Self {
        Self {
            soft_bytes: 50 * 1024 * 1024,
            hard_bytes: 100 * 1024 * 1024,
        }
    }
}

/// 成功保存或因部分更新保留原完整结果。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CachePublication {
    Stored,
    Preserved,
}

/// 只含稳定类别，不携带 SQL、路径、账号或正文。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CacheError {
    Unavailable,
    InvalidInput,
    Corrupt,
    UnsupportedVersion,
    Inactive,
    Superseded,
    Capacity,
}
impl std::fmt::Display for CacheError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Self::Unavailable => "本地缓存暂不可用",
            Self::InvalidInput => "缓存范围无效",
            Self::Corrupt => "缓存或密钥无法校验",
            Self::UnsupportedVersion => "缓存版本暂不支持",
            Self::Inactive => "本机账号已退出",
            Self::Superseded => "缓存任务已失效",
            Self::Capacity => "本地缓存容量不足",
        })
    }
}
impl std::error::Error for CacheError {}
pub type CacheResult<T> = Result<T, CacheError>;

/// 只有仓库能创建的读取凭据；不是学校写入意图，也不包含认证材料。
#[derive(Clone)]
pub struct CacheReadTicket {
    pub(super) account: String,
    pub(super) scope: CacheScope,
    pub(super) epoch: u64,
    pub(super) revision: i64,
}

impl CacheScope {
    pub(super) fn validate(&self) -> CacheResult<()> {
        let id = |s: &str| !s.trim().is_empty() && s.len() <= 1024;
        let valid = match &self.query {
            CacheQuery::ScheduleToday { date } => {
                chrono::NaiveDate::parse_from_str(date, "%Y-%m-%d")
                    .is_ok_and(|value| value.format("%Y-%m-%d").to_string() == *date)
            }
            CacheQuery::ScheduleWeek { term, week } => id(term) && *week > 0,
            CacheQuery::JudgeAssignments { course_id }
            | CacheQuery::JudgeCourseReview { course_id } => id(course_id),
            CacheQuery::JudgeDetail {
                course_id,
                assignment_id,
            } => id(course_id) && id(assignment_id),
            _ => true,
        };
        if valid {
            Ok(())
        } else {
            Err(CacheError::InvalidInput)
        }
    }
    pub(super) fn priority(&self) -> i64 {
        match self.query {
            CacheQuery::ScheduleToday { .. } | CacheQuery::ScheduleWeek { .. } => 1,
            _ => 0,
        }
    }
}
impl CachePayload {
    pub(super) fn matches(&self, query: &CacheQuery) -> bool {
        match (self, query) {
            (Self::Today(_), CacheQuery::ScheduleToday { .. })
            | (Self::Week(_), CacheQuery::ScheduleWeek { .. })
            | (Self::JudgeCourses(_), CacheQuery::JudgeCourses)
            | (Self::JudgeSummaries(_), CacheQuery::JudgeSummaries { .. }) => true,
            (Self::JudgeCourseReview(review), CacheQuery::JudgeCourseReview { course_id }) => {
                review
                    .summaries
                    .iter()
                    .all(|item| &item.course_id == course_id)
            }
            (Self::JudgeAssignments(items), CacheQuery::JudgeAssignments { course_id }) => {
                items.iter().all(|v| &v.course_id == course_id)
            }
            (
                Self::JudgeDetail(item),
                CacheQuery::JudgeDetail {
                    course_id,
                    assignment_id,
                },
            ) => &item.course_id == course_id && &item.assignment_id == assignment_id,
            _ => false,
        }
    }
}

/// 本次尝试时间与数据原始来源时间分别保存，复用缓存不伪装网络新鲜度。
#[derive(Clone, Copy)]
pub struct CacheObservation {
    pub source_at: i64,
    pub attempted_at: i64,
}

/// 历史低频判断与对应索引修订绑定，不是永久课程黑名单。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct JudgeCourseReview {
    pub index_revision: i64,
    pub index_checked_at: i64,
    pub next_index_check_at: i64,
    pub all_items_historical: bool,
    /// 紧凑课程摘要只用于排序和复查依据，不替代逐项详情的新鲜度判断。
    #[serde(default)]
    pub summaries: Vec<JudgeAssignmentSummary>,
}
impl CacheReadTicket {
    pub(crate) const fn revision(&self) -> i64 {
        self.revision
    }
}
