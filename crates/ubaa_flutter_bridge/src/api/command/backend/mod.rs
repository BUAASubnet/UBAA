//! 命令读取当前 Core，学校写入消费 GUI 共用的一次性准备意图。

use super::cache::project;
use async_trait::async_trait;
use ubaa_core::facade as core;
use ubaa_core::facade::{
    BykcActionResult, BykcChosenCourse, BykcCourse, BykcCoursePage, BykcSignRequest,
    BykcStatistics, BykcUserProfile, CgyyCancelOrderRequest, CgyyCancelOrderResult, CgyyDayInfo,
    CgyyLockCode, CgyyOrder, CgyyOrdersPage, CgyyPurposeType, CgyyReservationResult,
    CgyyReservationSubmitRequest, CgyyVenueSite, ClassroomQuery, ConnectionMode,
    EvaluationBatchResult, EvaluationCoursesResponse, EvaluationSubmitCoursesRequest,
    ExamArrangement, GradeData, JudgeAssignmentDetail, JudgeAssignmentKey, JudgeAssignmentSummary,
    JudgeAssignmentsDiagnostics, LibBookArea, LibBookAreaDetail, LibBookBookingsPage,
    LibBookCancelRequest, LibBookCancelResult, LibBookLibrary, LibBookReserveRequest,
    LibBookReserveResult, LibBookSeat, SigninActionResult, SigninClass, SpocAssignmentDetail,
    SpocAssignments, SpocAssignmentsDiagnostics, Term, TodayClass, UserProfile, Week,
    WeeklySchedule, YgdkClockinSubmitRequest, YgdkClockinSubmitResult, YgdkOverview,
    YgdkRecordsPage,
};
use ubaa_core::facade::{CampusMetrics, NetworkUsage, PortalProfile};
use ubaa_core::facade::{IhomeAppeal, IhomeConfig, IhomeNotice, IhomePage, IhomeQuery};
use ubaa_core::facade::{Result, RoutedResult, UbaaClient};

use crate::api::{
    client::{BridgeClient, disposed_error},
    offline::BridgeOfflineCache,
    read::{BridgeEvaluationSubmitTarget, BridgeYgdkSubmitTarget},
    write::{
        BridgeBykcCourseRequest, BridgeBykcSignCourseRequest, BridgeCgyyCancelOrderRequest,
        BridgeEvaluationSubmitCoursesRequest, BridgeLibbookCancelBookingRequest,
        BridgeLibbookReserveRequest, BridgePhotoUpload, BridgeSigninPerformRequest,
        BridgeWriteIntent, BridgeYgdkSubmitRequest,
        command::CommandHint,
        dispatch::WriteReceipt,
        preparation_error::{PreparationError, routed_bridge_error},
    },
};
use ubaa_command::RoutedCliBackend;
fn internal_error(message: &str) -> ubaa_core::facade::UbaaError {
    ubaa_core::facade::UbaaError::new(
        ubaa_core::facade::ErrorCode::InternalError,
        ubaa_core::facade::ErrorKind::Internal,
        false,
        message,
    )
}

pub(crate) struct CommandBackend<'a> {
    pub(crate) command: Option<&'a super::BridgeCommand>,
    pub(crate) client: &'a BridgeClient,
    pub(crate) cache: Option<&'a BridgeOfflineCache>,
    pub(crate) hints: Vec<CommandHint>,
}
impl CommandBackend<'_> {
    async fn commit<T>(
        &mut self,
        intent: std::result::Result<BridgeWriteIntent, PreparationError>,
        extract: impl FnOnce(WriteReceipt) -> Option<T> + Send,
    ) -> RoutedResult<T> {
        let intent = intent.map_err(PreparationError::into_routed)?;
        let committed = self
            .client
            .commit_command_write(self.cache, &intent.intent_id, self.command)
            .await
            .map_err(|error| ubaa_core::facade::RoutedError {
                error,
                resolution: None,
            })?;
        if let Some(hint) = committed.hint {
            self.hints.push(hint);
        }
        let result = committed.result?;
        let data = extract(result.data).ok_or_else(|| ubaa_core::facade::RoutedError {
            error: internal_error("学校写入回执类型不匹配"),
            resolution: Some(result.resolution),
        })?;
        Ok(ubaa_core::facade::Routed {
            data,
            resolution: result.resolution,
        })
    }
}

mod routed;
