#[async_trait]
impl CliBackend for FakeBackend {
    async fn portal_profile(&mut self) -> Result<FeatureResult<PortalProfile>> { Ok(FeatureResult { data: campus_profile(), resolved_route: ConnectionMode::Direct }) }
    async fn campus_metrics(&mut self) -> Result<FeatureResult<CampusMetrics>> { Ok(FeatureResult { data: campus_metrics(), resolved_route: ConnectionMode::Direct }) }
    async fn network_usage(&mut self) -> Result<FeatureResult<NetworkUsage>> { Ok(FeatureResult { data: campus_network(), resolved_route: ConnectionMode::Direct }) }
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
