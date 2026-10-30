#[async_trait]
impl RoutedCliBackend for FakeRoutedBackend {
    async fn portal_profile(&mut self) -> RoutedResult<PortalProfile> { Ok(Routed { data: campus_profile(), resolution: direct_resolution() }) }
    async fn campus_metrics(&mut self) -> RoutedResult<CampusMetrics> { Ok(Routed { data: campus_metrics(), resolution: direct_resolution() }) }
    async fn network_usage(&mut self) -> RoutedResult<NetworkUsage> { Ok(Routed { data: campus_network(), resolution: direct_resolution() }) }
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
