use async_trait::async_trait;
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
        "../../../../docs/contracts/cli-json.schema.json"
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

#[async_trait]
impl RoutedCliBackend for FakeRoutedBackend {
    async fn ygdk_overview(&mut self) -> RoutedResult<YgdkOverview> {
        self.ygdk_overview_calls += 1;
        Ok(Routed {
            data: self.ygdk_overview.clone().unwrap_or_default(),
            resolution: direct_resolution(),
        })
    }

    async fn ygdk_records(&mut self, _page: i32, _size: i32) -> RoutedResult<YgdkRecordsPage> {
        self.ygdk_records_calls += 1;
        Ok(Routed {
            data: self.ygdk_records.clone().unwrap_or_default(),
            resolution: direct_resolution(),
        })
    }

    async fn ygdk_submit(
        &mut self,
        request: YgdkClockinSubmitRequest,
    ) -> RoutedResult<YgdkClockinSubmitResult> {
        self.ygdk_submit_calls += 1;
        self.ygdk_last_submit_request = Some(request);
        match self.ygdk_submit_result {
            YgdkSubmitFixtureResult::Success => Ok(Routed {
                data: YgdkClockinSubmitResult {
                    success: true,
                    message: "RAW-UPSTREAM photo=PRIVATE token=PRIVATE".into(),
                    record_id: Some(77),
                },
                resolution: direct_resolution(),
            }),
            YgdkSubmitFixtureResult::SuccessWithInvalidRecordId => Ok(Routed {
                data: YgdkClockinSubmitResult {
                    success: true,
                    message: "RAW-UPSTREAM photo=PRIVATE token=PRIVATE".into(),
                    record_id: Some(0),
                },
                resolution: direct_resolution(),
            }),
            YgdkSubmitFixtureResult::UnsafeFalse => Ok(Routed {
                data: YgdkClockinSubmitResult {
                    success: false,
                    message: "RAW-UPSTREAM photo=PRIVATE token=PRIVATE".into(),
                    record_id: None,
                },
                resolution: direct_resolution(),
            }),
            YgdkSubmitFixtureResult::OutcomeUnknown => Err(RoutedError {
                error: UbaaError::new(
                    ErrorCode::OutcomeUnknown,
                    ErrorKind::Upstream,
                    false,
                    "RAW-UPSTREAM photo=PRIVATE token=PRIVATE\nSet-Cookie=PRIVATE",
                ),
                resolution: Some(direct_resolution()),
            }),
            YgdkSubmitFixtureResult::PreSendChanged => Err(RoutedError {
                error: UbaaError::new(
                    ErrorCode::UpstreamChanged,
                    ErrorKind::Upstream,
                    false,
                    "RAW-UPSTREAM photo=PRIVATE token=PRIVATE",
                ),
                resolution: Some(direct_resolution()),
            }),
        }
    }

    async fn ygdk_overview_on_route(&mut self, route: ConnectionMode) -> Result<YgdkOverview> {
        self.ygdk_readback_overview_calls += 1;
        self.ygdk_readback_overview_routes.push(route);
        if self.ygdk_readback_overview_fails {
            Err(ygdk_readback_error())
        } else {
            Ok(YgdkOverview::default())
        }
    }

    async fn ygdk_records_on_route(
        &mut self,
        route: ConnectionMode,
        page: i32,
        size: i32,
    ) -> Result<YgdkRecordsPage> {
        self.ygdk_readback_records_calls += 1;
        self.ygdk_readback_records_requests
            .push((route, page, size));
        if self.ygdk_readback_records_fails {
            Err(ygdk_readback_error())
        } else {
            Ok(YgdkRecordsPage::default())
        }
    }

    async fn signin_today(&mut self) -> RoutedResult<Vec<SigninClass>> {
        self.signin_today_calls += 1;
        Ok(Routed {
            data: vec![
                signin_class("schedule-allowed", Some(0), ActionEligibility::Allowed),
                signin_class("schedule-denied", Some(1), ActionEligibility::Denied),
                signin_class("schedule-missing", None, ActionEligibility::Unknown),
                signin_class("schedule-other", Some(2), ActionEligibility::Unknown),
            ],
            resolution: direct_resolution(),
        })
    }

    async fn signin_perform(&mut self, _course_id: &str) -> RoutedResult<SigninActionResult> {
        self.signin_perform_calls += 1;
        match self.signin_result {
            SigninFixtureResult::Success => Ok(Routed {
                data: SigninActionResult {
                    code: 200,
                    success: true,
                    message: "签到成功".into(),
                },
                resolution: direct_resolution(),
            }),
            SigninFixtureResult::BusinessFalse => Ok(Routed {
                data: SigninActionResult {
                    code: 400,
                    success: false,
                    message: "签到未完成".into(),
                },
                resolution: direct_resolution(),
            }),
            SigninFixtureResult::OutcomeUnknown => Err(RoutedError {
                error: UbaaError::new(
                    ErrorCode::OutcomeUnknown,
                    ErrorKind::Upstream,
                    false,
                    "fixture outcome unknown",
                ),
                resolution: Some(direct_resolution()),
            }),
            SigninFixtureResult::PreSendTimeout => Err(RoutedError {
                error: UbaaError::new(
                    ErrorCode::Timeout,
                    ErrorKind::Network,
                    true,
                    "fixture pre-send timeout",
                ),
                resolution: Some(direct_resolution()),
            }),
        }
    }

    async fn libbook_reserve(
        &mut self,
        request: LibBookReserveRequest,
    ) -> RoutedResult<LibBookReserveResult> {
        self.libbook_reserve_calls += 1;
        self.libbook_last_request = Some(request);
        match self.libbook_result {
            LibBookFixtureResult::Success => Ok(Routed {
                data: LibBookReserveResult {
                    success: true,
                    message: "预约成功".into(),
                    booking: None,
                },
                resolution: direct_resolution(),
            }),
            LibBookFixtureResult::BusinessFalse => Ok(Routed {
                data: LibBookReserveResult {
                    success: false,
                    message: "座位不可预约".into(),
                    booking: None,
                },
                resolution: direct_resolution(),
            }),
            LibBookFixtureResult::OutcomeUnknown => Err(RoutedError {
                error: UbaaError::new(
                    ErrorCode::OutcomeUnknown,
                    ErrorKind::Upstream,
                    false,
                    "fixture outcome unknown",
                ),
                resolution: Some(direct_resolution()),
            }),
            LibBookFixtureResult::PreSendTimeout => Err(RoutedError {
                error: UbaaError::new(
                    ErrorCode::Timeout,
                    ErrorKind::Network,
                    true,
                    "fixture pre-send timeout",
                ),
                resolution: Some(direct_resolution()),
            }),
        }
    }

    async fn libbook_seats(
        &mut self,
        _area_id: &str,
        _day: &str,
        _start_time: &str,
        _end_time: &str,
    ) -> RoutedResult<Vec<LibBookSeat>> {
        self.libbook_seats_calls += 1;
        Ok(Routed {
            data: vec![
                libbook_seat("seat-allowed", Some(1), ActionEligibility::Allowed, true),
                libbook_seat("seat-denied", Some(2), ActionEligibility::Denied, true),
                libbook_seat("seat-occupied", Some(3), ActionEligibility::Denied, true),
                libbook_seat("seat-unknown", None, ActionEligibility::Unknown, false),
            ],
            resolution: direct_resolution(),
        })
    }

    async fn libbook_bookings(
        &mut self,
        page: i32,
        limit: i32,
    ) -> RoutedResult<LibBookBookingsPage> {
        self.libbook_bookings_calls += 1;
        Ok(Routed {
            data: LibBookBookingsPage {
                bookings: vec![
                    libbook_booking("booking-allowed", Some(1), ActionEligibility::Allowed, true),
                    libbook_booking(
                        "booking-cancelled",
                        Some(6),
                        ActionEligibility::Denied,
                        true,
                    ),
                    libbook_booking("booking-ended", Some(8), ActionEligibility::Denied, true),
                    libbook_booking("booking-unknown", None, ActionEligibility::Unknown, false),
                ],
                page,
                limit,
                total: 4,
            },
            resolution: direct_resolution(),
        })
    }

    async fn libbook_cancel_booking(
        &mut self,
        request: LibBookCancelRequest,
    ) -> RoutedResult<LibBookCancelResult> {
        self.libbook_cancel_calls += 1;
        self.libbook_last_cancel_request = Some(request);
        if let Some(error) = self.libbook_cancel_error.take() {
            return Err(RoutedError {
                error,
                resolution: Some(direct_resolution()),
            });
        }
        Ok(Routed {
            data: LibBookCancelResult {
                success: true,
                message: "取消成功".into(),
            },
            resolution: direct_resolution(),
        })
    }

    async fn bykc_select_course(&mut self, _course_id: i64) -> RoutedResult<BykcActionResult> {
        Ok(bykc_action("fixture select"))
    }

    async fn bykc_deselect_course(&mut self, _course_id: i64) -> RoutedResult<BykcActionResult> {
        Ok(bykc_action("fixture deselect"))
    }

    async fn bykc_sign_course(
        &mut self,
        _request: BykcSignRequest,
    ) -> RoutedResult<BykcActionResult> {
        Ok(bykc_action("fixture sign"))
    }

    async fn cgyy_cancel_order(
        &mut self,
        request: CgyyCancelOrderRequest,
    ) -> RoutedResult<CgyyCancelOrderResult> {
        self.cgyy_cancel_calls += 1;
        self.cgyy_last_cancel_request = Some(request);
        match self.cgyy_cancel_result {
            CgyyCancelFixtureResult::Success => Ok(Routed {
                data: CgyyCancelOrderResult {
                    success: true,
                    message: "RAW-UPSTREAM phone=PRIVATE token=PRIVATE".into(),
                },
                resolution: direct_resolution(),
            }),
            CgyyCancelFixtureResult::OutcomeUnknown => Err(RoutedError {
                error: UbaaError::new(
                    ErrorCode::OutcomeUnknown,
                    ErrorKind::Upstream,
                    false,
                    "RAW-UPSTREAM phone=PRIVATE token=PRIVATE\nSet-Cookie=PRIVATE",
                ),
                resolution: Some(direct_resolution()),
            }),
            CgyyCancelFixtureResult::PreSendChanged => Err(RoutedError {
                error: UbaaError::new(
                    ErrorCode::UpstreamChanged,
                    ErrorKind::Upstream,
                    false,
                    "RAW-UPSTREAM phone=PRIVATE token=PRIVATE",
                ),
                resolution: Some(direct_resolution()),
            }),
        }
    }

    async fn get_user_info(&mut self) -> RoutedResult<UserProfile> {
        Ok(Routed {
            data: profile(),
            resolution: route_resolution(
                RoutePolicy::WebVpn,
                NetworkState::Unknown,
                ConnectionMode::WebVpn,
            ),
        })
    }

    async fn schedule_terms(&mut self) -> RoutedResult<Vec<Term>> {
        let resolution = route_resolution(
            RoutePolicy::Direct,
            NetworkState::Unknown,
            ConnectionMode::Direct,
        );
        if self.fail_schedule {
            Err(RoutedError {
                error: UbaaError::new(
                    ErrorCode::AuthenticationRequired,
                    ErrorKind::Authentication,
                    false,
                    "fixture schedule authentication required",
                ),
                resolution: Some(resolution),
            })
        } else {
            Ok(Routed {
                data: Vec::new(),
                resolution,
            })
        }
    }

    async fn judge_assignments_diagnostics(
        &mut self,
        _include_expired: bool,
    ) -> RoutedResult<JudgeAssignmentsDiagnostics> {
        Ok(Routed {
            data: JudgeAssignmentsDiagnostics {
                course_count: 3,
                raw_anchor_count: 7,
                filtered_unique_count: 2,
                summaries: Vec::new(),
            },
            resolution: route_resolution(
                RoutePolicy::Direct,
                NetworkState::Unknown,
                ConnectionMode::Direct,
            ),
        })
    }

    async fn spoc_assignments_diagnostics(&mut self) -> RoutedResult<SpocAssignmentsDiagnostics> {
        Ok(Routed {
            data: SpocAssignmentsDiagnostics {
                global_page_count: 2,
                result: SpocAssignments {
                    term_code: "2025-2026-2".into(),
                    term_name: Some("Spring".into()),
                    assignments: Vec::new(),
                },
            },
            resolution: route_resolution(
                RoutePolicy::Direct,
                NetworkState::Unknown,
                ConnectionMode::Direct,
            ),
        })
    }

    async fn ihome_page(&mut self, _query: IhomeQuery) -> RoutedResult<IhomePage> {
        Err(test_routed_unavailable())
    }

    async fn ihome_detail(&mut self, _id: i64, _mine: bool) -> RoutedResult<IhomeAppeal> {
        Err(test_routed_unavailable())
    }

    async fn ihome_config(&mut self) -> RoutedResult<IhomeConfig> {
        Err(test_routed_unavailable())
    }

    async fn ihome_notices(&mut self) -> RoutedResult<Vec<IhomeNotice>> {
        Err(test_routed_unavailable())
    }

    async fn ihome_notice(&mut self, _id: i64) -> RoutedResult<IhomeNotice> {
        Err(test_routed_unavailable())
    }

    async fn evaluation_all(&mut self) -> RoutedResult<EvaluationCoursesResponse> {
        Err(test_routed_unavailable())
    }

    async fn evaluation_all_on_route(
        &mut self,
        _route: ConnectionMode,
    ) -> Result<EvaluationCoursesResponse> {
        Err(test_unavailable())
    }

    async fn evaluation_submit_courses_if_route_matches(
        &mut self,
        _request: EvaluationSubmitCoursesRequest,
        _expected_route: ConnectionMode,
    ) -> RoutedResult<EvaluationBatchResult> {
        Err(test_routed_unavailable())
    }

    async fn libbook_libraries(&mut self, _day: &str) -> RoutedResult<Vec<LibBookLibrary>> {
        Err(test_routed_unavailable())
    }

    async fn libbook_areas(
        &mut self,
        _premises_id: &str,
        _storey_id: Option<&str>,
        _day: &str,
    ) -> RoutedResult<Vec<LibBookArea>> {
        Err(test_routed_unavailable())
    }

    async fn libbook_area_detail(&mut self, _area_id: &str) -> RoutedResult<LibBookAreaDetail> {
        Err(test_routed_unavailable())
    }

    async fn bykc_profile(&mut self) -> RoutedResult<BykcUserProfile> {
        Err(test_routed_unavailable())
    }

    async fn bykc_courses(
        &mut self,
        _page: i32,
        _size: i32,
        _all: bool,
    ) -> RoutedResult<BykcCoursePage> {
        Err(test_routed_unavailable())
    }

    async fn bykc_course_detail(&mut self, _id: i64) -> RoutedResult<BykcCourse> {
        Err(test_routed_unavailable())
    }

    async fn bykc_chosen_courses(&mut self) -> RoutedResult<Vec<BykcChosenCourse>> {
        Err(test_routed_unavailable())
    }

    async fn bykc_statistics(&mut self) -> RoutedResult<BykcStatistics> {
        Err(test_routed_unavailable())
    }

    async fn cgyy_sites(&mut self) -> RoutedResult<Vec<CgyyVenueSite>> {
        Err(test_routed_unavailable())
    }

    async fn cgyy_lock_code(&mut self) -> RoutedResult<CgyyLockCode> {
        Err(test_routed_unavailable())
    }

    async fn cgyy_purposes(&mut self) -> RoutedResult<Vec<CgyyPurposeType>> {
        Err(test_routed_unavailable())
    }

    async fn cgyy_day(&mut self, _site_id: i32, _date: &str) -> RoutedResult<CgyyDayInfo> {
        Err(test_routed_unavailable())
    }

    async fn cgyy_orders(&mut self, _page: i32, _size: i32) -> RoutedResult<CgyyOrdersPage> {
        Err(test_routed_unavailable())
    }

    async fn cgyy_order_detail(&mut self, _id: i32) -> RoutedResult<CgyyOrder> {
        Err(test_routed_unavailable())
    }

    async fn cgyy_submit_reservation(
        &mut self,
        _request: CgyyReservationSubmitRequest,
    ) -> RoutedResult<CgyyReservationResult> {
        Err(test_routed_unavailable())
    }

    async fn schedule_weeks(&mut self, _term: &str) -> RoutedResult<Vec<Week>> {
        Err(test_routed_unavailable())
    }

    async fn schedule_week(&mut self, _term: &str, _week: i32) -> RoutedResult<WeeklySchedule> {
        Err(test_routed_unavailable())
    }

    async fn schedule_today(&mut self) -> RoutedResult<Vec<TodayClass>> {
        Err(test_routed_unavailable())
    }

    async fn exam_arrangement(&mut self, _term: &str) -> RoutedResult<ExamArrangement> {
        Err(test_routed_unavailable())
    }

    async fn grades(&mut self, _term: &str) -> RoutedResult<GradeData> {
        Err(test_routed_unavailable())
    }

    async fn classroom_search(
        &mut self,
        _campus: i32,
        _date: &str,
    ) -> RoutedResult<ClassroomQuery> {
        Err(test_routed_unavailable())
    }

    async fn spoc_assignments(&mut self) -> RoutedResult<SpocAssignments> {
        Err(test_routed_unavailable())
    }

    async fn spoc_assignment(&mut self, _id: &str) -> RoutedResult<SpocAssignmentDetail> {
        Err(test_routed_unavailable())
    }

    async fn judge_assignments(
        &mut self,
        _include_expired: bool,
    ) -> RoutedResult<Vec<JudgeAssignmentSummary>> {
        Err(test_routed_unavailable())
    }

    async fn judge_assignment(
        &mut self,
        _course_id: &str,
        _id: &str,
    ) -> RoutedResult<JudgeAssignmentDetail> {
        Err(test_routed_unavailable())
    }

    async fn judge_assignment_details(
        &mut self,
        _keys: &[JudgeAssignmentKey],
    ) -> RoutedResult<Vec<JudgeAssignmentDetail>> {
        Err(test_routed_unavailable())
    }
}

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

#[async_trait]
impl CliBackend for FakeBackend {
    async fn evaluation_all(&mut self) -> Result<FeatureResult<EvaluationCoursesResponse>> {
        Err(test_unavailable())
    }

    fn mode(&self) -> ConnectionMode {
        ConnectionMode::Direct
    }

    async fn login(&mut self, _input: LoginInput) -> Result<UserProfile> {
        self.login_calls += 1;
        Ok(profile())
    }

    async fn auth_status(&mut self) -> Result<AuthStatus> {
        Ok(AuthStatus {
            user: profile(),
            authenticated_at: 100,
            last_activity: 101,
        })
    }

    async fn get_user_info(&mut self) -> Result<UserProfile> {
        Ok(profile())
    }

    async fn logout(&mut self) -> Result<()> {
        Ok(())
    }

    async fn schedule_terms(&mut self) -> Result<FeatureResult<Vec<Term>>> {
        if self.schedule_success {
            return Ok(FeatureResult {
                data: Vec::new(),
                resolved_route: ConnectionMode::Direct,
            });
        }
        Err(UbaaError::new(
            ErrorCode::AuthenticationRequired,
            ErrorKind::Authentication,
            false,
            "fixture schedule authentication required",
        ))
    }

    async fn signin_perform(
        &mut self,
        _course_id: &str,
    ) -> Result<FeatureResult<SigninActionResult>> {
        self.signin_perform_calls += 1;
        Ok(FeatureResult {
            data: SigninActionResult {
                code: 200,
                success: true,
                message: "签到成功".into(),
            },
            resolved_route: ConnectionMode::Direct,
        })
    }

    async fn libbook_reserve(
        &mut self,
        _request: LibBookReserveRequest,
    ) -> Result<FeatureResult<LibBookReserveResult>> {
        self.libbook_reserve_calls += 1;
        Ok(FeatureResult {
            data: LibBookReserveResult {
                success: true,
                message: "预约成功".into(),
                booking: None,
            },
            resolved_route: ConnectionMode::Direct,
        })
    }

    async fn libbook_cancel_booking(
        &mut self,
        request: LibBookCancelRequest,
    ) -> Result<FeatureResult<LibBookCancelResult>> {
        self.libbook_cancel_calls += 1;
        self.libbook_last_cancel_request = Some(request);
        if let Some(error) = self.libbook_cancel_error.take() {
            return Err(error);
        }
        Ok(FeatureResult {
            data: LibBookCancelResult {
                success: true,
                message: "取消成功".into(),
            },
            resolved_route: ConnectionMode::Direct,
        })
    }

    async fn cgyy_cancel_order(
        &mut self,
        request: CgyyCancelOrderRequest,
    ) -> Result<FeatureResult<CgyyCancelOrderResult>> {
        self.cgyy_cancel_calls += 1;
        self.cgyy_last_cancel_request = Some(request);
        match self.cgyy_cancel_result {
            CgyyCancelFixtureResult::Success => Ok(FeatureResult {
                data: CgyyCancelOrderResult {
                    success: true,
                    message: "RAW-UPSTREAM phone=PRIVATE token=PRIVATE".into(),
                },
                resolved_route: ConnectionMode::Direct,
            }),
            CgyyCancelFixtureResult::OutcomeUnknown => Err(UbaaError::new(
                ErrorCode::OutcomeUnknown,
                ErrorKind::Upstream,
                false,
                "RAW-UPSTREAM phone=PRIVATE token=PRIVATE\nSet-Cookie=PRIVATE",
            )),
            CgyyCancelFixtureResult::PreSendChanged => Err(UbaaError::new(
                ErrorCode::UpstreamChanged,
                ErrorKind::Upstream,
                false,
                "RAW-UPSTREAM phone=PRIVATE token=PRIVATE",
            )),
        }
    }

    async fn ygdk_submit(
        &mut self,
        request: YgdkClockinSubmitRequest,
    ) -> Result<FeatureResult<YgdkClockinSubmitResult>> {
        self.ygdk_submit_calls += 1;
        self.ygdk_last_submit_request = Some(request);
        match self.ygdk_submit_result {
            YgdkSubmitFixtureResult::Success => Ok(FeatureResult {
                data: YgdkClockinSubmitResult {
                    success: true,
                    message: "RAW-UPSTREAM photo=PRIVATE token=PRIVATE".into(),
                    record_id: Some(77),
                },
                resolved_route: ConnectionMode::Direct,
            }),
            YgdkSubmitFixtureResult::SuccessWithInvalidRecordId => Ok(FeatureResult {
                data: YgdkClockinSubmitResult {
                    success: true,
                    message: "RAW-UPSTREAM photo=PRIVATE token=PRIVATE".into(),
                    record_id: Some(0),
                },
                resolved_route: ConnectionMode::Direct,
            }),
            YgdkSubmitFixtureResult::UnsafeFalse => Ok(FeatureResult {
                data: YgdkClockinSubmitResult {
                    success: false,
                    message: "RAW-UPSTREAM photo=PRIVATE token=PRIVATE".into(),
                    record_id: None,
                },
                resolved_route: ConnectionMode::Direct,
            }),
            YgdkSubmitFixtureResult::OutcomeUnknown => Err(UbaaError::new(
                ErrorCode::OutcomeUnknown,
                ErrorKind::Upstream,
                false,
                "RAW-UPSTREAM photo=PRIVATE token=PRIVATE\nSet-Cookie=PRIVATE",
            )),
            YgdkSubmitFixtureResult::PreSendChanged => Err(UbaaError::new(
                ErrorCode::UpstreamChanged,
                ErrorKind::Upstream,
                false,
                "RAW-UPSTREAM photo=PRIVATE token=PRIVATE",
            )),
        }
    }

    async fn ygdk_overview_on_route(&mut self, route: ConnectionMode) -> Result<YgdkOverview> {
        self.ygdk_readback_overview_calls += 1;
        self.ygdk_readback_overview_routes.push(route);
        if self.ygdk_readback_overview_fails {
            Err(ygdk_readback_error())
        } else {
            Ok(YgdkOverview::default())
        }
    }

    async fn ygdk_records_on_route(
        &mut self,
        route: ConnectionMode,
        page: i32,
        size: i32,
    ) -> Result<YgdkRecordsPage> {
        self.ygdk_readback_records_calls += 1;
        self.ygdk_readback_records_requests
            .push((route, page, size));
        if self.ygdk_readback_records_fails {
            Err(ygdk_readback_error())
        } else {
            Ok(YgdkRecordsPage::default())
        }
    }

    async fn ihome_page(&mut self, _query: IhomeQuery) -> Result<FeatureResult<IhomePage>> {
        Err(test_unavailable())
    }

    async fn ihome_detail(&mut self, _id: i64, _mine: bool) -> Result<FeatureResult<IhomeAppeal>> {
        Err(test_unavailable())
    }

    async fn ihome_config(&mut self) -> Result<FeatureResult<IhomeConfig>> {
        Err(test_unavailable())
    }

    async fn ihome_notices(&mut self) -> Result<FeatureResult<Vec<IhomeNotice>>> {
        Err(test_unavailable())
    }

    async fn ihome_notice(&mut self, _id: i64) -> Result<FeatureResult<IhomeNotice>> {
        Err(test_unavailable())
    }

    async fn signin_today(&mut self) -> Result<FeatureResult<Vec<SigninClass>>> {
        Err(test_unavailable())
    }

    async fn libbook_libraries(
        &mut self,
        _day: &str,
    ) -> Result<FeatureResult<Vec<LibBookLibrary>>> {
        Err(test_unavailable())
    }

    async fn libbook_areas(
        &mut self,
        _premises_id: &str,
        _storey_id: Option<&str>,
        _day: &str,
    ) -> Result<FeatureResult<Vec<LibBookArea>>> {
        Err(test_unavailable())
    }

    async fn libbook_area_detail(
        &mut self,
        _area_id: &str,
    ) -> Result<FeatureResult<LibBookAreaDetail>> {
        Err(test_unavailable())
    }

    async fn libbook_seats(
        &mut self,
        _area_id: &str,
        _day: &str,
        _start_time: &str,
        _end_time: &str,
    ) -> Result<FeatureResult<Vec<LibBookSeat>>> {
        Err(test_unavailable())
    }

    async fn libbook_bookings(
        &mut self,
        _page: i32,
        _limit: i32,
    ) -> Result<FeatureResult<LibBookBookingsPage>> {
        Err(test_unavailable())
    }

    async fn bykc_profile(&mut self) -> Result<FeatureResult<BykcUserProfile>> {
        Err(test_unavailable())
    }

    async fn bykc_courses(
        &mut self,
        _page: i32,
        _size: i32,
        _all: bool,
    ) -> Result<FeatureResult<BykcCoursePage>> {
        Err(test_unavailable())
    }

    async fn bykc_course_detail(&mut self, _id: i64) -> Result<FeatureResult<BykcCourse>> {
        Err(test_unavailable())
    }

    async fn bykc_chosen_courses(&mut self) -> Result<FeatureResult<Vec<BykcChosenCourse>>> {
        Err(test_unavailable())
    }

    async fn bykc_statistics(&mut self) -> Result<FeatureResult<BykcStatistics>> {
        Err(test_unavailable())
    }

    async fn bykc_select_course(
        &mut self,
        _course_id: i64,
    ) -> Result<FeatureResult<BykcActionResult>> {
        Err(test_unavailable())
    }

    async fn bykc_deselect_course(
        &mut self,
        _course_id: i64,
    ) -> Result<FeatureResult<BykcActionResult>> {
        Err(test_unavailable())
    }

    async fn bykc_sign_course(
        &mut self,
        _request: BykcSignRequest,
    ) -> Result<FeatureResult<BykcActionResult>> {
        Err(test_unavailable())
    }

    async fn cgyy_sites(&mut self) -> Result<FeatureResult<Vec<CgyyVenueSite>>> {
        Err(test_unavailable())
    }

    async fn cgyy_lock_code(&mut self) -> Result<FeatureResult<CgyyLockCode>> {
        Err(test_unavailable())
    }

    async fn cgyy_purposes(&mut self) -> Result<FeatureResult<Vec<CgyyPurposeType>>> {
        Err(test_unavailable())
    }

    async fn cgyy_day(&mut self, _site_id: i32, _date: &str) -> Result<FeatureResult<CgyyDayInfo>> {
        Err(test_unavailable())
    }

    async fn cgyy_orders(
        &mut self,
        _page: i32,
        _size: i32,
    ) -> Result<FeatureResult<CgyyOrdersPage>> {
        Err(test_unavailable())
    }

    async fn cgyy_order_detail(&mut self, _id: i32) -> Result<FeatureResult<CgyyOrder>> {
        Err(test_unavailable())
    }

    async fn cgyy_submit_reservation(
        &mut self,
        _request: CgyyReservationSubmitRequest,
    ) -> Result<FeatureResult<CgyyReservationResult>> {
        Err(test_unavailable())
    }

    async fn ygdk_overview(&mut self) -> Result<FeatureResult<YgdkOverview>> {
        Err(test_unavailable())
    }

    async fn ygdk_records(
        &mut self,
        _page: i32,
        _size: i32,
    ) -> Result<FeatureResult<YgdkRecordsPage>> {
        Err(test_unavailable())
    }

    async fn evaluation_submit_courses(
        &mut self,
        _request: EvaluationSubmitCoursesRequest,
    ) -> Result<FeatureResult<EvaluationBatchResult>> {
        Err(test_unavailable())
    }

    async fn schedule_weeks(&mut self, _term: &str) -> Result<FeatureResult<Vec<Week>>> {
        Err(test_unavailable())
    }

    async fn schedule_week(
        &mut self,
        _term: &str,
        _week: i32,
    ) -> Result<FeatureResult<WeeklySchedule>> {
        Err(test_unavailable())
    }

    async fn schedule_today(&mut self) -> Result<FeatureResult<Vec<TodayClass>>> {
        Err(test_unavailable())
    }

    async fn exam_arrangement(&mut self, _term: &str) -> Result<FeatureResult<ExamArrangement>> {
        Err(test_unavailable())
    }

    async fn grades(&mut self, _term: &str) -> Result<FeatureResult<GradeData>> {
        Err(test_unavailable())
    }

    async fn classroom_search(
        &mut self,
        _campus: i32,
        _date: &str,
    ) -> Result<FeatureResult<ClassroomQuery>> {
        Err(test_unavailable())
    }

    async fn spoc_assignments(&mut self) -> Result<FeatureResult<SpocAssignments>> {
        Err(test_unavailable())
    }

    async fn spoc_assignments_diagnostics(
        &mut self,
    ) -> Result<FeatureResult<SpocAssignmentsDiagnostics>> {
        Err(test_unavailable())
    }

    async fn spoc_assignment(&mut self, _id: &str) -> Result<FeatureResult<SpocAssignmentDetail>> {
        Err(test_unavailable())
    }

    async fn judge_assignments(
        &mut self,
        _include_expired: bool,
    ) -> Result<FeatureResult<Vec<JudgeAssignmentSummary>>> {
        Err(test_unavailable())
    }

    async fn judge_assignments_diagnostics(
        &mut self,
        _include_expired: bool,
    ) -> Result<FeatureResult<JudgeAssignmentsDiagnostics>> {
        Err(test_unavailable())
    }

    async fn judge_assignment(
        &mut self,
        _course_id: &str,
        _id: &str,
    ) -> Result<FeatureResult<JudgeAssignmentDetail>> {
        Err(test_unavailable())
    }

    async fn judge_assignment_details(
        &mut self,
        _keys: &[JudgeAssignmentKey],
    ) -> Result<FeatureResult<Vec<JudgeAssignmentDetail>>> {
        Err(test_unavailable())
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
