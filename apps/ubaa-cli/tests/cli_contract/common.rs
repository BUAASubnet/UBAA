use async_trait::async_trait;
use ubaa_cli::{CliBackend, RoutedCliBackend};
use ubaa_core::facade::{
    ActionEligibility, AuthStatus, BykcActionResult, BykcSignRequest, CgyyActionResult,
    ConnectionMode, ErrorCode, ErrorKind, FeatureResult, JudgeAssignmentsDiagnostics,
    LibBookReserveRequest, LibBookReserveResult, LibBookSeat, LoginInput, NetworkState, Result,
    RouteDiagnostic, RoutePolicy, RouteResolution, Routed, RoutedError, RoutedResult,
    SigninActionResult, SigninClass, SpocAssignments, SpocAssignmentsDiagnostics, Term, UbaaError,
    UserProfile,
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

#[derive(Default)]
pub(crate) struct FakeRoutedBackend {
    pub(crate) fail_schedule: bool,
    pub(crate) cgyy_cancel_calls: usize,
    pub(crate) signin_today_calls: usize,
    pub(crate) signin_perform_calls: usize,
    pub(crate) signin_result: SigninFixtureResult,
    pub(crate) libbook_reserve_calls: usize,
    pub(crate) libbook_result: LibBookFixtureResult,
    pub(crate) libbook_last_request: Option<LibBookReserveRequest>,
    pub(crate) libbook_seats_calls: usize,
}

#[async_trait]
impl RoutedCliBackend for FakeRoutedBackend {
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

    async fn cgyy_cancel_order(&mut self, _id: i32) -> RoutedResult<CgyyActionResult> {
        self.cgyy_cancel_calls += 1;
        Ok(Routed {
            data: CgyyActionResult {
                message: "fixture cancellation".into(),
                order: None,
            },
            resolution: route_resolution(
                RoutePolicy::Direct,
                NetworkState::Unknown,
                ConnectionMode::Direct,
            ),
        })
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
}

fn direct_resolution() -> RouteResolution {
    route_resolution(
        RoutePolicy::Direct,
        NetworkState::Unknown,
        ConnectionMode::Direct,
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
