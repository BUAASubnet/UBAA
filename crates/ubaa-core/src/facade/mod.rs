//! CLI 与未来绑定层使用的稳定 facade。
mod auth;
mod client;
mod diagnostic;
mod judge_refresh;
mod judge_scan;
pub use judge_refresh::{JudgeRefresh, JudgeRefreshBatch, JudgeRefreshOptions};
mod academic_cache;
mod bykc_cache;
mod cgyy_cache;
pub use bykc_cache::{BykcCacheQuery, BykcReadData};
pub use cgyy_cache::{CgyyCacheQuery, CgyyReadData, CgyyRefresh};
mod home_cache;
mod offline;
pub use academic_cache::AcademicQuery;
pub use home_cache::{HomeQuery, HomeReadData, HomeRefresh};
pub use judge_scan::{JudgeScan, JudgeScanBatch, JudgeScanCancellation, JudgeScanKind};
pub use offline::{OfflineCache, OfflineReadError, OfflineRefresh};
mod read;
mod routing;
#[cfg(feature = "test-contract")]
#[doc(hidden)]
pub mod testing;
mod types;
mod write;

pub use client::UbaaClient;
pub use diagnostic::RouteClient;
pub use types::{CallerPinned, Routed, RoutedError, RoutedResult};

// 逐项列出宿主稳定合同，避免新增领域实现时被通配重导出意外纳入公共 API。
pub use crate::domain::{
    ActionEligibility, Assignment, AuthStatus, BykcActionResult, BykcChosenCourse, BykcCourse,
    BykcCourseCategory, BykcCoursePage, BykcCourseStatus, BykcCourseSubCategory, BykcSignConfig,
    BykcSignLocationRequirement, BykcSignPoint, BykcSignPreflight, BykcSignRequest, BykcStatistic,
    BykcStatistics, BykcUserProfile, CgyyCancelOrderPreflight, CgyyCancelOrderRequest,
    CgyyCancelOrderResult, CgyyCancelOrderTarget, CgyyDayInfo, CgyyLockCode, CgyyOrder,
    CgyyOrdersPage, CgyyPurposeSource, CgyyPurposeType, CgyyPurposeTypes, CgyyReservationPreflight,
    CgyyReservationReceipt, CgyyReservationResult, CgyyReservationSelection,
    CgyyReservationSubmitRequest, CgyyReservationTarget, CgyySlotStatus, CgyySpaceAvailability,
    CgyyTimeSlot, CgyyVenueSite, ClassroomInfo, ClassroomQuery, ConnectionMode, Course,
    CourseClass, DualLoginInput, DualLoginPreparation, EvaluationBatchResult, EvaluationCourse,
    EvaluationCourseOutcome, EvaluationCourseResult, EvaluationCoursesResponse, EvaluationProgress,
    EvaluationSubmitCoursesRequest, EvaluationSubmitPreflight, EvaluationSubmitTarget, Exam,
    ExamArrangement, FeatureResult, Grade, GradeData, JudgeAssignmentDetail, JudgeAssignmentKey,
    JudgeAssignmentSummary, JudgeAssignmentsDiagnostics, JudgeProblem, JudgeSubmissionStatus,
    LibBookArea, LibBookAreaDetail, LibBookBooking, LibBookBookingsPage, LibBookCancelPreflight,
    LibBookCancelRequest, LibBookCancelResult, LibBookLibrary, LibBookReservePreflight,
    LibBookReserveRequest, LibBookReserveResult, LibBookSeat, LibBookStorey, LibBookTimeSlot,
    LoginInput, LoginOutcome, LoginReadiness, ReadonlyFeature, RouteLoginResult, RouteLoginState,
    RoutePolicy, SafeError, SecretValue, SigninActionResult, SigninClass, SpocAssignmentDetail,
    SpocAssignmentSummary, SpocAssignments, SpocAssignmentsDiagnostics, SpocSubmissionStatus, Term,
    TodayClass, UserInfoResponse, UserProfile, Week, WeeklySchedule, YgdkClockinSubmitRequest,
    YgdkClockinSubmitResult, YgdkItem, YgdkOverview, YgdkPhotoUpload, YgdkRecord, YgdkRecordsPage,
    YgdkSubmitPreflight, YgdkSubmitTarget, YgdkTermSummary,
};
pub use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

// 这些类型是宿主可见的安全路线诊断投影；其余 connection 实现仍属于 Core 内部。
pub use crate::connection::{NetworkState, RouteDiagnostic, RouteResolution};

// 独立本地仓库不获取 UbaaClient 网络锁；载荷白名单不包含学校写入资格。
pub use crate::cache::{
    CACHE_SCHEMA_VERSION, CacheCompleteness, CacheError, CacheKey, CacheLimits, CacheObservation,
    CachePayload, CachePublication, CacheQuery, CacheReadTicket, CacheRecord, CacheResult,
    CacheScope, CachedBykcChosen, CachedBykcChosenCourse, CachedBykcCourse, CachedBykcCoursePage,
    CachedBykcSignWindow, CachedCgyyDayInfo, CachedCgyyOrder, CachedCgyyOrdersPage,
    CachedCgyySlotStatus, CachedCgyySpaceAvailability, CachedEvaluationCourse,
    CachedEvaluationCourses, CachedLibBookBooking, CachedLibBookBookingsPage, CachedLibBookSeat,
    CachedMaskedProfile, CachedSigninClass, CachedYgdkItem, CachedYgdkOverview, CachedYgdkRecord,
    CachedYgdkRecordsPage, CachedYgdkRecordsSelection, JudgeCourseReview, OfflineRepository,
};

mod libbook_cache;
pub use libbook_cache::{LibBookCacheQuery, LibBookReadData, LibBookRefresh};

mod evaluation_cache;
pub use evaluation_cache::EvaluationRefresh;

mod ygdk_cache;
pub use ygdk_cache::YgdkRecordsRefresh;

mod profile_cache;
