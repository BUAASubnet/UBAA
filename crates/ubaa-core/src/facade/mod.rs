//! CLI 与未来绑定层使用的稳定 facade。
mod auth;
mod client;
mod diagnostic;
mod read;
mod routing;
#[cfg(feature = "test-contract")]
#[doc(hidden)]
pub mod testing;
mod types;
mod write;

pub use client::UbaaClient;
pub use diagnostic::RouteClient;
pub use types::{Routed, RoutedError, RoutedResult};

// 逐项列出宿主稳定合同，避免新增领域实现时被通配重导出意外纳入公共 API。
pub use crate::domain::{
    ActionEligibility, Assignment, AuthStatus, BykcActionResult, BykcChosenCourse, BykcCourse,
    BykcCourseCategory, BykcCoursePage, BykcCourseStatus, BykcCourseSubCategory, BykcSignConfig,
    BykcSignLocationRequirement, BykcSignPoint, BykcSignPreflight, BykcSignRequest, BykcStatistic,
    BykcStatistics, BykcUserProfile, CgyyActionResult, CgyyDayInfo, CgyyLockCode, CgyyOrder,
    CgyyOrdersPage, CgyyPurposeSource, CgyyPurposeType, CgyyPurposeTypes, CgyyReservationResult,
    CgyyReservationSelection, CgyyReservationSubmitRequest, CgyySlotStatus, CgyySpaceAvailability,
    CgyyTimeSlot, CgyyVenueSite, ClassroomInfo, ClassroomQuery, ConnectionMode, Course,
    CourseClass, DualLoginInput, DualLoginPreparation, EvaluationCourse, EvaluationCoursesResponse,
    EvaluationProgress, EvaluationQuestionnaire, EvaluationResult, EvaluationTask, Exam,
    ExamArrangement, FeatureResult, Grade, GradeData, JudgeAssignmentDetail, JudgeAssignmentKey,
    JudgeAssignmentSummary, JudgeAssignmentsDiagnostics, JudgeProblem, JudgeSubmissionStatus,
    LibBookArea, LibBookAreaDetail, LibBookBooking, LibBookBookingsPage, LibBookCancelResult,
    LibBookLibrary, LibBookReservePreflight, LibBookReserveRequest, LibBookReserveResult,
    LibBookSeat, LibBookStorey, LibBookTimeSlot, LoginInput, LoginOutcome, LoginReadiness,
    ReadonlyFeature, RouteLoginResult, RouteLoginState, RoutePolicy, SafeError, SecretValue,
    SigninActionResult, SigninClass, SpocAssignmentDetail, SpocAssignmentSummary, SpocAssignments,
    SpocAssignmentsDiagnostics, SpocSubmissionStatus, Term, TodayClass, UserInfoResponse,
    UserProfile, Week, WeeklySchedule, YgdkClockinSubmitRequest, YgdkClockinSubmitResult, YgdkItem,
    YgdkOverview, YgdkPhotoUpload, YgdkRecord, YgdkRecordsPage, YgdkTermSummary,
};
pub use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

// 这些类型是宿主可见的安全路线诊断投影；其余 connection 实现仍属于 Core 内部。
pub use crate::connection::{NetworkState, RouteDiagnostic, RouteResolution};
