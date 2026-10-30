use async_trait::async_trait;
mod campus;
pub(crate) use campus::{campus_metrics, campus_network, campus_profile};
use ubaa_cli::{CliBackend, RoutedCliBackend};
use ubaa_core::facade::*;
use ubaa_core::facade::{
    ActionEligibility, AuthStatus, BykcActionResult, BykcSignRequest, CgyyCancelOrderRequest,
    CgyyCancelOrderResult, ConnectionMode, ErrorCode, ErrorKind, FeatureResult,
    JudgeAssignmentsDiagnostics, LibBookBooking, LibBookBookingsPage, LibBookCancelRequest,
    LibBookCancelResult, LibBookReserveRequest, LibBookReserveResult, LibBookSeat, LoginInput,
    NetworkState, Result, RouteDiagnostic, RoutePolicy, RouteResolution, Routed, RoutedError,
    RoutedResult, SigninActionResult, SigninClass, SpocAssignments, SpocAssignmentsDiagnostics,
    Term, UbaaError, UserProfile, YgdkClockinSubmitRequest, YgdkClockinSubmitResult, YgdkOverview,
    YgdkRecordsPage,
};

pub(crate) fn assert_cli_schema(value: &serde_json::Value) {
    let schema: serde_json::Value = serde_json::from_str(include_str!(
        "../../../../../docs/contracts/cli-json.schema.json"
    ))
    .unwrap();
    let validator = jsonschema::validator_for(&schema).unwrap();
    assert!(validator.is_valid(value), "invalid CLI envelope: {value}");
}

#[derive(Default)]
pub(crate) struct FakeBackend {
    pub(crate) login_calls: usize,
    pub(crate) schedule_success: bool,
    pub(crate) signin_perform_calls: usize,
    pub(crate) libbook_reserve_calls: usize,
    pub(crate) libbook_cancel_calls: usize,
    pub(crate) libbook_last_cancel_request: Option<LibBookCancelRequest>,
    pub(crate) libbook_cancel_error: Option<UbaaError>,
    pub(crate) cgyy_cancel_calls: usize,
    pub(crate) cgyy_last_cancel_request: Option<CgyyCancelOrderRequest>,
    pub(crate) cgyy_cancel_result: CgyyCancelFixtureResult,
    pub(crate) ygdk_submit_calls: usize,
    pub(crate) ygdk_last_submit_request: Option<YgdkClockinSubmitRequest>,
    pub(crate) ygdk_submit_result: YgdkSubmitFixtureResult,
    pub(crate) ygdk_readback_overview_calls: usize,
    pub(crate) ygdk_readback_overview_routes: Vec<ConnectionMode>,
    pub(crate) ygdk_readback_overview_fails: bool,
    pub(crate) ygdk_readback_records_calls: usize,
    pub(crate) ygdk_readback_records_requests: Vec<(ConnectionMode, i32, i32)>,
    pub(crate) ygdk_readback_records_fails: bool,
}

#[derive(Clone, Copy, Default)]
pub(crate) enum SigninFixtureResult {
    #[default]
    Success,
    BusinessFalse,
    OutcomeUnknown,
    PreSendTimeout,
}

#[derive(Clone, Copy, Default)]
pub(crate) enum LibBookFixtureResult {
    #[default]
    Success,
    BusinessFalse,
    OutcomeUnknown,
    PreSendTimeout,
}

#[derive(Clone, Copy, Default)]
pub(crate) enum CgyyCancelFixtureResult {
    #[default]
    Success,
    OutcomeUnknown,
    PreSendChanged,
}

#[derive(Clone, Copy, Default)]
pub(crate) enum YgdkSubmitFixtureResult {
    #[default]
    Success,
    SuccessWithInvalidRecordId,
    UnsafeFalse,
    OutcomeUnknown,
    PreSendChanged,
}

#[derive(Default)]
pub(crate) struct FakeRoutedBackend {
    pub(crate) fail_schedule: bool,
    pub(crate) cgyy_cancel_calls: usize,
    pub(crate) cgyy_last_cancel_request: Option<CgyyCancelOrderRequest>,
    pub(crate) cgyy_cancel_result: CgyyCancelFixtureResult,
    pub(crate) signin_today_calls: usize,
    pub(crate) signin_perform_calls: usize,
    pub(crate) signin_result: SigninFixtureResult,
    pub(crate) libbook_reserve_calls: usize,
    pub(crate) libbook_result: LibBookFixtureResult,
    pub(crate) libbook_last_request: Option<LibBookReserveRequest>,
    pub(crate) libbook_seats_calls: usize,
    pub(crate) libbook_bookings_calls: usize,
    pub(crate) libbook_cancel_calls: usize,
    pub(crate) libbook_last_cancel_request: Option<LibBookCancelRequest>,
    pub(crate) libbook_cancel_error: Option<UbaaError>,
    pub(crate) ygdk_overview_calls: usize,
    pub(crate) ygdk_overview: Option<YgdkOverview>,
    pub(crate) ygdk_records_calls: usize,
    pub(crate) ygdk_records: Option<YgdkRecordsPage>,
    pub(crate) ygdk_submit_calls: usize,
    pub(crate) ygdk_last_submit_request: Option<YgdkClockinSubmitRequest>,
    pub(crate) ygdk_submit_result: YgdkSubmitFixtureResult,
    pub(crate) ygdk_readback_overview_calls: usize,
    pub(crate) ygdk_readback_overview_routes: Vec<ConnectionMode>,
    pub(crate) ygdk_readback_overview_fails: bool,
    pub(crate) ygdk_readback_records_calls: usize,
    pub(crate) ygdk_readback_records_requests: Vec<(ConnectionMode, i32, i32)>,
    pub(crate) ygdk_readback_records_fails: bool,
}

include!("routed.rs");
include!("fixed.rs");

fn direct_resolution() -> RouteResolution {
    route_resolution(
        RoutePolicy::Direct,
        NetworkState::Unknown,
        ConnectionMode::Direct,
    )
}

fn ygdk_readback_error() -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamUnavailable,
        ErrorKind::Upstream,
        false,
        "fixture Ygdk readback unavailable",
    )
}

fn signin_class(
    course_id: &str,
    sign_status: Option<i32>,
    signin_eligibility: ActionEligibility,
) -> SigninClass {
    SigninClass {
        course_id: course_id.into(),
        course_name: "脱敏课堂".into(),
        class_begin_time: "08:00".into(),
        class_end_time: "09:40".into(),
        sign_status,
        signin_eligibility,
        signin_target: Some(course_id.into()),
    }
}

fn libbook_seat(
    id: &str,
    status: Option<i32>,
    reserve_eligibility: ActionEligibility,
    has_target: bool,
) -> LibBookSeat {
    LibBookSeat {
        id: id.into(),
        name: "脱敏座位".into(),
        no: "SAFE-001".into(),
        status,
        status_name: "脱敏状态".into(),
        reserve_eligibility,
        reserve_target: has_target.then(|| id.into()),
    }
}

fn libbook_booking(
    id: &str,
    status: Option<i32>,
    cancel_eligibility: ActionEligibility,
    has_target: bool,
) -> LibBookBooking {
    LibBookBooking {
        id: id.into(),
        name_merge: "脱敏图书馆预约".into(),
        area_name: "脱敏分区".into(),
        seat_no: "SAFE-001".into(),
        day: "2026-08-28".into(),
        begin_time: "08:00".into(),
        end_time: "10:00".into(),
        status,
        status_name: "脱敏状态".into(),
        cancel_eligibility,
        cancel_target: has_target.then(|| id.into()),
    }
}

fn bykc_action(message: &str) -> Routed<BykcActionResult> {
    Routed {
        data: BykcActionResult {
            message: message.into(),
        },
        resolution: route_resolution(
            RoutePolicy::Direct,
            NetworkState::Unknown,
            ConnectionMode::Direct,
        ),
    }
}

pub(crate) fn profile() -> UserProfile {
    UserProfile {
        name: Some("Fixture User".into()),
        school_id: Some("TEST-0001".into()),
        username: Some("fixture-user".into()),
        phone: Some("PHONE-FIXTURE-VALUE".into()),
        id_card_number: Some("TEST-ID-0001".into()),
        ..UserProfile::default()
    }
}

pub(crate) fn route_resolution(
    policy: RoutePolicy,
    network: NetworkState,
    route: ConnectionMode,
) -> RouteResolution {
    RouteResolution {
        mode: route,
        policy,
        diagnostic: RouteDiagnostic::new(network, route),
    }
}

pub(crate) fn test_unavailable() -> UbaaError {
    UbaaError::new(
        ErrorCode::InternalError,
        ErrorKind::Internal,
        false,
        "测试后端未实现此命令",
    )
}

pub(crate) fn test_routed_unavailable() -> RoutedError {
    RoutedError {
        error: UbaaError::new(
            ErrorCode::InternalError,
            ErrorKind::Internal,
            false,
            "测试后端未实现此命令",
        ),
        resolution: None,
    }
}
