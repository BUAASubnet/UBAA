//! 缓存持久合同只包含可再次阅读的数据，不包含写入资格。
use super::{
    CachedBykcChosen, CachedBykcCourse, CachedBykcCoursePage, CachedCgyyDayInfo, CachedCgyyOrder,
    CachedCgyyOrdersPage, CachedEvaluationCourses, CachedLibBookBookingsPage, CachedLibBookSeat,
    CachedSigninClass, CachedYgdkOverview,
};
use crate::domain::{
    Assignment, CgyyPurposeTypes, CgyyVenueSite, ClassroomQuery, ConnectionMode, Course,
    ExamArrangement, GradeData, JudgeAssignmentDetail, JudgeAssignmentSummary, LibBookArea,
    LibBookAreaDetail, LibBookLibrary, Term, TodayClass, Week, WeeklySchedule,
};
use crate::domain::{BykcStatistics, BykcUserProfile, SpocAssignmentDetail, SpocAssignments};
use serde::{Deserialize, Serialize};

/// 独立于 Session 和 Bridge 的业务缓存版本。
pub const CACHE_SCHEMA_VERSION: u32 = 1;

/// 精确业务查询；日期使用既有校园日期，不在读取时替换成今天。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum CacheQuery {
    /// 当前评教任务固定第1页/每页10；不代表历史或全部学期。
    EvaluationCurrent,
    LibBookLibraries {
        day: String,
    },
    LibBookAreas {
        premises_id: String,
        storey_id: Option<String>,
        day: String,
    },
    LibBookAreaDetail {
        area_id: String,
    },
    LibBookSeats {
        area_id: String,
        day: String,
        start_time: String,
        end_time: String,
    },
    LibBookBookings {
        page: i32,
        limit: i32,
    },
    ScheduleToday {
        date: String,
    },
    ScheduleWeek {
        term: String,
        week: i32,
    },
    CgyySites,
    CgyyPurposes,
    CgyyDay {
        site_id: i32,
        date: String,
    },
    CgyyOrders {
        page: i32,
        size: i32,
    },
    CgyyDetail {
        order_id: i32,
    },
    BykcProfile,
    BykcCourses {
        page: i32,
        size: i32,
        all: bool,
    },
    BykcDetail {
        course_id: i64,
    },
    BykcChosen,
    BykcStatistics,
    ScheduleTerms,
    ScheduleWeeks {
        term: String,
    },
    Exams {
        term: String,
    },
    Grades {
        term: String,
    },
    Classrooms {
        campus: i32,
        date: String,
    },
    SigninToday {
        date: String,
    },
    SpocAssignments,
    SpocDetail {
        assignment_id: String,
    },
    YgdkOverview,
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
#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
pub enum CachePayload {
    EvaluationCurrent(CachedEvaluationCourses),
    LibBookLibraries(Vec<LibBookLibrary>),
    LibBookAreas(Vec<LibBookArea>),
    LibBookAreaDetail(LibBookAreaDetail),
    LibBookSeats(Vec<CachedLibBookSeat>),
    LibBookBookings(CachedLibBookBookingsPage),
    CgyySites(Vec<CgyyVenueSite>),
    CgyyPurposes(CgyyPurposeTypes),
    CgyyDay(CachedCgyyDayInfo),
    CgyyOrders(CachedCgyyOrdersPage),
    CgyyDetail(CachedCgyyOrder),
    BykcProfile(BykcUserProfile),
    BykcCourses(CachedBykcCoursePage),
    BykcDetail(CachedBykcCourse),
    BykcChosen(CachedBykcChosen),
    BykcStatistics(BykcStatistics),
    Today(Vec<TodayClass>),
    SigninToday(Vec<CachedSigninClass>),
    SpocAssignments(SpocAssignments),
    SpocDetail(Box<SpocAssignmentDetail>),
    YgdkOverview(CachedYgdkOverview),
    Week(WeeklySchedule),
    Terms(Vec<Term>),
    Weeks(Vec<Week>),
    Exams(ExamArrangement),
    Grades(GradeData),
    Classrooms(ClassroomQuery),
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
#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
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
    pub(crate) fn validate(&self) -> CacheResult<()> {
        let id = |s: &str| !s.trim().is_empty() && s.len() <= 1024;
        let date = |s: &str| {
            chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d")
                .is_ok_and(|v| v.format("%Y-%m-%d").to_string() == s)
        };
        let valid = match &self.query {
            CacheQuery::LibBookLibraries { day } => date(day),
            CacheQuery::LibBookAreas {
                premises_id,
                storey_id,
                day,
            } => id(premises_id) && storey_id.as_deref().is_none_or(id) && date(day),
            CacheQuery::LibBookAreaDetail { area_id } => id(area_id),
            CacheQuery::LibBookSeats {
                area_id,
                day,
                start_time,
                end_time,
            } => id(area_id) && date(day) && start_time.len() <= 1024 && end_time.len() <= 1024,
            CacheQuery::LibBookBookings { page, limit } => *page > 0 && *limit > 0,
            CacheQuery::CgyyDay { site_id, date } => {
                *site_id > 0
                    && chrono::NaiveDate::parse_from_str(date, "%Y-%m-%d")
                        .is_ok_and(|value| value.format("%Y-%m-%d").to_string() == *date)
            }
            CacheQuery::CgyyOrders { page, size } => *page >= 0 && *size > 0,
            CacheQuery::CgyyDetail { order_id } => *order_id > 0,
            CacheQuery::BykcCourses { page, size, .. } => *page > 0 && *size > 0,
            CacheQuery::BykcDetail { course_id } => *course_id > 0,
            CacheQuery::SigninToday { date } => chrono::NaiveDate::parse_from_str(date, "%Y%m%d")
                .is_ok_and(|value| value.format("%Y%m%d").to_string() == *date),
            CacheQuery::SpocDetail { assignment_id } => id(assignment_id),
            CacheQuery::ScheduleToday { date } | CacheQuery::Classrooms { date, .. } => {
                chrono::NaiveDate::parse_from_str(date, "%Y-%m-%d")
                    .is_ok_and(|value| value.format("%Y-%m-%d").to_string() == *date)
            }
            CacheQuery::ScheduleWeeks { term } | CacheQuery::Exams { term } => id(term),
            CacheQuery::Grades { term } => {
                id(term) && crate::features::grades::parse_term_code(term).is_ok()
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
            (Self::LibBookAreaDetail(v), CacheQuery::LibBookAreaDetail { area_id }) => {
                &v.id == area_id
            }
            (Self::LibBookBookings(v), CacheQuery::LibBookBookings { page, limit }) => {
                v.page == *page && v.limit == *limit
            }
            (Self::CgyyDay(v), CacheQuery::CgyyDay { site_id, date }) => {
                v.venue_site_id == *site_id && v.reservation_date == *date
            }
            (Self::CgyyOrders(v), CacheQuery::CgyyOrders { page, size }) => {
                v.number == *page && v.size == *size
            }
            (Self::CgyyDetail(v), CacheQuery::CgyyDetail { order_id }) => v.id == *order_id,
            (Self::BykcDetail(v), CacheQuery::BykcDetail { course_id }) => v.id == *course_id,
            (Self::BykcChosen(v), CacheQuery::BykcChosen) => {
                !v.semester_start.trim().is_empty() && !v.semester_end.trim().is_empty()
            }
            (Self::EvaluationCurrent(_), CacheQuery::EvaluationCurrent)
            | (Self::LibBookLibraries(_), CacheQuery::LibBookLibraries { .. })
            | (Self::LibBookAreas(_), CacheQuery::LibBookAreas { .. })
            | (Self::LibBookSeats(_), CacheQuery::LibBookSeats { .. })
            | (Self::CgyySites(_), CacheQuery::CgyySites)
            | (Self::CgyyPurposes(_), CacheQuery::CgyyPurposes)
            | (Self::BykcProfile(_), CacheQuery::BykcProfile)
            | (Self::BykcStatistics(_), CacheQuery::BykcStatistics)
            | (Self::BykcCourses(_), CacheQuery::BykcCourses { .. })
            | (Self::SigninToday(_), CacheQuery::SigninToday { .. })
            | (Self::SpocAssignments(_), CacheQuery::SpocAssignments)
            | (Self::YgdkOverview(_), CacheQuery::YgdkOverview)
            | (Self::Terms(_), CacheQuery::ScheduleTerms)
            | (Self::Weeks(_), CacheQuery::ScheduleWeeks { .. })
            | (Self::Exams(_), CacheQuery::Exams { .. })
            | (Self::Today(_), CacheQuery::ScheduleToday { .. })
            | (Self::Week(_), CacheQuery::ScheduleWeek { .. })
            | (Self::JudgeCourses(_), CacheQuery::JudgeCourses)
            | (Self::JudgeSummaries(_), CacheQuery::JudgeSummaries { .. }) => true,
            (Self::SpocDetail(data), CacheQuery::SpocDetail { assignment_id }) => {
                &data.assignment_id == assignment_id
            }
            (Self::Grades(data), CacheQuery::Grades { term }) => {
                &data.term_code == term
                    && data.grades.iter().all(|grade| {
                        grade.credit.is_none_or(f64::is_finite)
                            && grade.term_code.as_ref().is_none_or(|value| value == term)
                    })
            }
            (Self::Classrooms(data), CacheQuery::Classrooms { .. }) => data.code == 0,
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
