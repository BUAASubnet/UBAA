use super::super::cache;
use super::{
    BridgeBykcCourseRequest, BridgeBykcSignCourseRequest, BridgeCgyyCancelOrderRequest,
    BridgeEvaluationSubmitCoursesRequest, BridgeEvaluationSubmitTarget,
    BridgeLibbookCancelBookingRequest, BridgeLibbookReserveRequest, BridgePhotoUpload,
    BridgeSigninPerformRequest, BridgeYgdkSubmitRequest, BridgeYgdkSubmitTarget, BykcActionResult,
    BykcChosenCourse, BykcCourse, BykcCoursePage, BykcSignRequest, BykcStatistics, BykcUserProfile,
    CampusMetrics, CgyyCancelOrderRequest, CgyyCancelOrderResult, CgyyDayInfo, CgyyLockCode,
    CgyyOrder, CgyyOrdersPage, CgyyPurposeType, CgyyReservationResult,
    CgyyReservationSubmitRequest, CgyyVenueSite, ClassroomQuery, CommandBackend, ConnectionMode,
    EvaluationBatchResult, EvaluationCoursesResponse, EvaluationSubmitCoursesRequest,
    ExamArrangement, GradeData, IhomeAppeal, IhomeConfig, IhomeNotice, IhomePage, IhomeQuery,
    JudgeAssignmentDetail, JudgeAssignmentKey, JudgeAssignmentSummary, JudgeAssignmentsDiagnostics,
    LibBookArea, LibBookAreaDetail, LibBookBookingsPage, LibBookCancelRequest, LibBookCancelResult,
    LibBookLibrary, LibBookReserveRequest, LibBookReserveResult, LibBookSeat, NetworkUsage,
    PortalProfile, Result, RoutedCliBackend, RoutedResult, SigninActionResult, SigninClass,
    SpocAssignmentDetail, SpocAssignments, SpocAssignmentsDiagnostics, Term, TodayClass,
    UbaaClient, UserProfile, Week, WeeklySchedule, WriteReceipt, YgdkClockinSubmitRequest,
    YgdkClockinSubmitResult, YgdkOverview, YgdkRecordsPage, async_trait, core, disposed_error,
    internal_error, project, routed_bridge_error,
};

// 读取只在一次调用内借用当前 Core；固定路线回读沿用其原错误类型。
macro_rules! current_core {
    ($this:expr,$guard:ident,$client:ident) => {
        let mut $guard = $this.client.inner.lock().await;
        let $client = $guard
            .as_mut()
            .ok_or_else(|| routed_bridge_error(disposed_error()))?;
    };
    ($this:expr,$guard:ident,$client:ident,plain) => {
        let mut $guard = $this.client.inner.lock().await;
        let $client = $guard
            .as_mut()
            .ok_or_else(|| routed_bridge_error(disposed_error()).error)?;
    };
}
#[async_trait]
impl RoutedCliBackend for CommandBackend<'_> {
    async fn bhpan_execute(
        &mut self,
        args: &ubaa_command::BhpanArgs,
        input: &ubaa_command::bhpan::BhpanPreparedInput,
    ) -> RoutedResult<ubaa_command::bhpan::BhpanOutput> {
        super::bhpan::execute(self, args, input).await
    }

    async fn portal_profile(&mut self) -> RoutedResult<PortalProfile> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_campus(&cache.cache, core::CampusCacheQuery::Profile)
                    .await
                    .map(|v| v.result),
                cache::portal_profile,
            );
        }

        UbaaClient::portal_profile(client).await
    }
    async fn campus_metrics(&mut self) -> RoutedResult<CampusMetrics> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_campus(&cache.cache, core::CampusCacheQuery::Metrics)
                    .await
                    .map(|v| v.result),
                cache::campus_metrics,
            );
        }

        UbaaClient::campus_metrics(client).await
    }
    async fn finance_incomes(&mut self) -> RoutedResult<ubaa_core::facade::FinanceIncomes> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_finance(&cache.cache)
                    .await
                    .map(|v| v.result),
                Some,
            );
        }
        UbaaClient::finance_incomes(client).await
    }

    async fn network_usage(&mut self) -> RoutedResult<NetworkUsage> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_campus(&cache.cache, core::CampusCacheQuery::NetworkUsage)
                    .await
                    .map(|v| v.result),
                cache::network_usage,
            );
        }

        UbaaClient::network_usage(client).await
    }
    async fn ihome_notice(&mut self, id: i64) -> RoutedResult<IhomeNotice> {
        current_core!(self, guard, client);

        UbaaClient::ihome_notice(client, id).await
    }

    async fn ihome_notices(&mut self) -> RoutedResult<Vec<IhomeNotice>> {
        current_core!(self, guard, client);

        UbaaClient::ihome_notices(client).await
    }

    async fn ihome_config(&mut self) -> RoutedResult<IhomeConfig> {
        current_core!(self, guard, client);

        UbaaClient::ihome_config(client).await
    }

    async fn ihome_detail(&mut self, id: i64, mine: bool) -> RoutedResult<IhomeAppeal> {
        current_core!(self, guard, client);

        UbaaClient::ihome_detail(client, id, mine).await
    }

    async fn ihome_page(&mut self, query: IhomeQuery) -> RoutedResult<IhomePage> {
        current_core!(self, guard, client);

        UbaaClient::ihome_page(client, query).await
    }

    async fn evaluation_all(&mut self) -> RoutedResult<EvaluationCoursesResponse> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_evaluation(&cache.cache)
                    .await
                    .map(|v| v.result),
                Some,
            );
        }

        UbaaClient::evaluation_all(client).await
    }
    async fn evaluation_all_on_route(
        &mut self,
        route: ConnectionMode,
    ) -> Result<EvaluationCoursesResponse> {
        current_core!(self, guard, client, plain);

        let result = UbaaClient::evaluation_all_on_route(client, route).await?;
        if result.pinned_route != route {
            return Err(internal_error("评教课程回读偏离固定路线"));
        }
        Ok(result.data)
    }
    async fn evaluation_submit_courses_if_route_matches(
        &mut self,
        request: EvaluationSubmitCoursesRequest,
        expected_route: ConnectionMode,
    ) -> RoutedResult<EvaluationBatchResult> {
        let intent = self
            .client
            .prepare_evaluation_submit_courses_scoped(BridgeEvaluationSubmitCoursesRequest {
                targets: request
                    .targets
                    .into_iter()
                    .map(|v| BridgeEvaluationSubmitTarget {
                        rwid: v.rwid,
                        wjid: v.wjid,
                        kcdm: v.kcdm,
                        bpdm: v.bpdm,
                    })
                    .collect(),
            })
            .await;
        if let Ok(intent) = &intent
            && ubaa_core::facade::ConnectionMode::from(intent.resolved_route) != expected_route
        {
            let _ = self
                .client
                .discard_write_intent(intent.intent_id.clone())
                .await;
            return Err(ubaa_core::facade::RoutedError {
                error: internal_error("评教提交偏离已经确认的路线"),
                resolution: None,
            });
        }
        self.commit(intent, |v| {
            if let WriteReceipt::Evaluation(v) = v {
                Some(v)
            } else {
                None
            }
        })
        .await
    }
    async fn signin_today(&mut self) -> RoutedResult<Vec<SigninClass>> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_home(&cache.cache, core::HomeQuery::SigninToday)
                    .await
                    .map(|v| v.result),
                cache::signin_today,
            );
        }

        UbaaClient::signin_today(client).await
    }
    async fn signin_perform(&mut self, course_id: &str) -> RoutedResult<SigninActionResult> {
        let intent = self
            .client
            .prepare_signin_perform_scoped(BridgeSigninPerformRequest {
                course_id: course_id.to_owned(),
            })
            .await;
        self.commit(intent, |v| {
            if let WriteReceipt::Signin(v) = v {
                Some(v)
            } else {
                None
            }
        })
        .await
    }
    async fn libbook_libraries(&mut self, day: &str) -> RoutedResult<Vec<LibBookLibrary>> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_libbook(
                        &cache.cache,
                        core::LibBookCacheQuery::Libraries { day: day.into() },
                    )
                    .await
                    .map(|v| v.result),
                cache::libbook_libraries,
            );
        }

        UbaaClient::libbook_libraries(client, day).await
    }
    async fn libbook_areas(
        &mut self,
        premises_id: &str,
        storey_id: Option<&str>,
        day: &str,
    ) -> RoutedResult<Vec<LibBookArea>> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_libbook(
                        &cache.cache,
                        core::LibBookCacheQuery::Areas {
                            premises_id: premises_id.into(),
                            storey_id: storey_id.map(str::to_owned),
                            day: day.into(),
                        },
                    )
                    .await
                    .map(|v| v.result),
                cache::libbook_areas,
            );
        }

        UbaaClient::libbook_areas(client, premises_id, storey_id, day).await
    }
    async fn libbook_area_detail(&mut self, area_id: &str) -> RoutedResult<LibBookAreaDetail> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_libbook(
                        &cache.cache,
                        core::LibBookCacheQuery::AreaDetail {
                            area_id: area_id.into(),
                        },
                    )
                    .await
                    .map(|v| v.result),
                cache::libbook_area_detail,
            );
        }

        UbaaClient::libbook_area_detail(client, area_id).await
    }
    async fn libbook_seats(
        &mut self,
        area_id: &str,
        day: &str,
        start_time: &str,
        end_time: &str,
    ) -> RoutedResult<Vec<LibBookSeat>> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_libbook(
                        &cache.cache,
                        core::LibBookCacheQuery::Seats {
                            area_id: area_id.into(),
                            day: day.into(),
                            start_time: start_time.into(),
                            end_time: end_time.into(),
                        },
                    )
                    .await
                    .map(|v| v.result),
                cache::libbook_seats,
            );
        }

        UbaaClient::libbook_seats(client, area_id, day, start_time, end_time).await
    }
    async fn libbook_bookings(
        &mut self,
        page: i32,
        limit: i32,
    ) -> RoutedResult<LibBookBookingsPage> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_libbook(
                        &cache.cache,
                        core::LibBookCacheQuery::Bookings { page, limit },
                    )
                    .await
                    .map(|v| v.result),
                cache::libbook_bookings,
            );
        }

        UbaaClient::libbook_bookings(client, page, limit).await
    }
    async fn libbook_reserve(
        &mut self,
        request: LibBookReserveRequest,
    ) -> RoutedResult<LibBookReserveResult> {
        let intent = self
            .client
            .prepare_libbook_reserve_scoped(BridgeLibbookReserveRequest {
                area_id: request.area_id,
                seat_id: request.seat_id,
                day: request.day,
                segment: request.segment,
                start_time: request.start_time,
                end_time: request.end_time,
            })
            .await;
        self.commit(intent, |v| {
            if let WriteReceipt::LibbookReserve(v) = v {
                Some(v)
            } else {
                None
            }
        })
        .await
    }
    async fn libbook_cancel_booking(
        &mut self,
        request: LibBookCancelRequest,
    ) -> RoutedResult<LibBookCancelResult> {
        let intent = self
            .client
            .prepare_libbook_cancel_booking_scoped(BridgeLibbookCancelBookingRequest {
                id: request.booking_id,
                page: request.page,
                limit: request.limit,
            })
            .await;
        self.commit(intent, |v| {
            if let WriteReceipt::LibbookCancel(v) = v {
                Some(v)
            } else {
                None
            }
        })
        .await
    }
    async fn cgyy_sites(&mut self) -> RoutedResult<Vec<CgyyVenueSite>> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_cgyy(&cache.cache, core::CgyyCacheQuery::Sites)
                    .await
                    .map(|v| v.result),
                cache::cgyy_sites,
            );
        }

        UbaaClient::cgyy_sites(client).await
    }
    async fn cgyy_lock_code(&mut self) -> RoutedResult<CgyyLockCode> {
        current_core!(self, guard, client);

        UbaaClient::cgyy_lock_code(client).await
    }
    async fn cgyy_purposes(&mut self) -> RoutedResult<Vec<CgyyPurposeType>> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_cgyy(&cache.cache, core::CgyyCacheQuery::Purposes)
                    .await
                    .map(|v| v.result),
                cache::cgyy_purposes,
            );
        }

        UbaaClient::cgyy_purpose_types(client).await
    }
    async fn cgyy_day(&mut self, site_id: i32, date: &str) -> RoutedResult<CgyyDayInfo> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_cgyy(
                        &cache.cache,
                        core::CgyyCacheQuery::Day {
                            site_id,
                            date: date.into(),
                        },
                    )
                    .await
                    .map(|v| v.result),
                cache::cgyy_day,
            );
        }

        UbaaClient::cgyy_day_info(client, site_id, date).await
    }
    async fn cgyy_orders(&mut self, page: i32, size: i32) -> RoutedResult<CgyyOrdersPage> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_cgyy(&cache.cache, core::CgyyCacheQuery::Orders { page, size })
                    .await
                    .map(|v| v.result),
                cache::cgyy_orders,
            );
        }

        UbaaClient::cgyy_orders(client, page, size).await
    }
    async fn cgyy_order_detail(&mut self, id: i32) -> RoutedResult<CgyyOrder> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_cgyy(
                        &cache.cache,
                        core::CgyyCacheQuery::Detail { order_id: id },
                    )
                    .await
                    .map(|v| v.result),
                cache::cgyy_order_detail,
            );
        }

        UbaaClient::cgyy_order_detail(client, id).await
    }
    async fn cgyy_cancel_order(
        &mut self,
        request: CgyyCancelOrderRequest,
    ) -> RoutedResult<CgyyCancelOrderResult> {
        let intent = self
            .client
            .prepare_cgyy_cancel_order_scoped(BridgeCgyyCancelOrderRequest {
                order_id: request.order_id,
            })
            .await;
        self.commit(intent, |v| {
            if let WriteReceipt::CgyyCancel(v) = v {
                Some(v)
            } else {
                None
            }
        })
        .await
    }
    async fn cgyy_submit_reservation(
        &mut self,
        request: CgyyReservationSubmitRequest,
    ) -> RoutedResult<CgyyReservationResult> {
        let intent = self.client.prepare_cgyy_payload(request).await;
        self.commit(intent, |v| {
            if let WriteReceipt::CgyyReserve(v) = v {
                Some(v)
            } else {
                None
            }
        })
        .await
    }
    async fn bykc_profile(&mut self) -> RoutedResult<BykcUserProfile> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_bykc(&cache.cache, core::BykcCacheQuery::Profile)
                    .await,
                cache::bykc_profile,
            );
        }

        UbaaClient::bykc_profile(client).await
    }
    async fn bykc_courses(
        &mut self,
        page: i32,
        size: i32,
        all: bool,
    ) -> RoutedResult<BykcCoursePage> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_bykc(
                        &cache.cache,
                        core::BykcCacheQuery::Courses { page, size, all },
                    )
                    .await,
                cache::bykc_courses,
            );
        }

        UbaaClient::bykc_courses(client, page, size, all).await
    }
    async fn bykc_course_detail(&mut self, id: i64) -> RoutedResult<BykcCourse> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_bykc(
                        &cache.cache,
                        core::BykcCacheQuery::Detail { course_id: id },
                    )
                    .await,
                cache::bykc_course_detail,
            );
        }

        UbaaClient::bykc_course_detail(client, id).await
    }
    async fn bykc_chosen_courses(&mut self) -> RoutedResult<Vec<BykcChosenCourse>> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_bykc(&cache.cache, core::BykcCacheQuery::Chosen)
                    .await,
                cache::bykc_chosen_courses,
            );
        }

        UbaaClient::bykc_chosen_courses(client).await
    }
    async fn bykc_statistics(&mut self) -> RoutedResult<BykcStatistics> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_bykc(&cache.cache, core::BykcCacheQuery::Statistics)
                    .await,
                cache::bykc_statistics,
            );
        }

        UbaaClient::bykc_statistics(client).await
    }
    async fn bykc_select_course(&mut self, course_id: i64) -> RoutedResult<BykcActionResult> {
        let intent = self
            .client
            .prepare_bykc_select_course_scoped(BridgeBykcCourseRequest { course_id })
            .await;
        self.commit(intent, |v| {
            if let WriteReceipt::Bykc(v) = v {
                Some(v)
            } else {
                None
            }
        })
        .await
    }
    async fn bykc_deselect_course(&mut self, course_id: i64) -> RoutedResult<BykcActionResult> {
        let intent = self
            .client
            .prepare_bykc_deselect_course_scoped(BridgeBykcCourseRequest { course_id })
            .await;
        self.commit(intent, |v| {
            if let WriteReceipt::Bykc(v) = v {
                Some(v)
            } else {
                None
            }
        })
        .await
    }
    async fn bykc_sign_course(
        &mut self,
        request: BykcSignRequest,
    ) -> RoutedResult<BykcActionResult> {
        let intent = self
            .client
            .prepare_bykc_sign_course_scoped(BridgeBykcSignCourseRequest {
                course_id: request.course_id,
                lat: request.lat,
                lng: request.lng,
                sign_type: request.sign_type,
            })
            .await;
        self.commit(intent, |v| {
            if let WriteReceipt::BykcSign(v, _) = v {
                Some(v)
            } else {
                None
            }
        })
        .await
    }
    async fn ygdk_overview(&mut self) -> RoutedResult<YgdkOverview> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_home(&cache.cache, core::HomeQuery::YgdkOverview)
                    .await
                    .map(|v| v.result),
                cache::ygdk_overview,
            );
        }

        UbaaClient::ygdk_overview(client).await
    }
    async fn ygdk_records(&mut self, page: i32, size: i32) -> RoutedResult<YgdkRecordsPage> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_ygdk_records(&cache.cache, page, size)
                    .await
                    .map(|v| v.result),
                Some,
            );
        }

        UbaaClient::ygdk_records(client, page, size).await
    }
    async fn ygdk_submit(
        &mut self,
        request: YgdkClockinSubmitRequest,
    ) -> RoutedResult<YgdkClockinSubmitResult> {
        let intent = self
            .client
            .prepare_ygdk_submit_scoped(BridgeYgdkSubmitRequest {
                target: BridgeYgdkSubmitTarget {
                    classify_id: request.target.classify_id,
                    item_id: request.target.item_id,
                },
                start_time: request.start_time,
                end_time: request.end_time,
                place: request.place,
                share_to_square: request.share_to_square,
                photo: BridgePhotoUpload {
                    bytes: request.photo.bytes,
                    file_name: request.photo.file_name,
                    mime_type: request.photo.mime_type,
                },
            })
            .await;
        self.commit(intent, |v| {
            if let WriteReceipt::Ygdk(v) = v {
                Some(v)
            } else {
                None
            }
        })
        .await
    }
    async fn ygdk_overview_on_route(&mut self, route: ConnectionMode) -> Result<YgdkOverview> {
        current_core!(self, guard, client, plain);

        let result = UbaaClient::ygdk_overview_on_route(client, route).await?;
        if result.pinned_route != route {
            return Err(internal_error("阳光打卡概览回读偏离固定路线"));
        }
        Ok(result.data)
    }
    async fn ygdk_records_on_route(
        &mut self,
        route: ConnectionMode,
        page: i32,
        size: i32,
    ) -> Result<YgdkRecordsPage> {
        current_core!(self, guard, client, plain);

        let result = UbaaClient::ygdk_records_on_route(client, route, page, size).await?;
        if result.pinned_route != route {
            return Err(internal_error("阳光打卡记录回读偏离固定路线"));
        }
        Ok(result.data)
    }
    async fn get_user_info(&mut self) -> RoutedResult<UserProfile> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(client.refresh_cached_profile(&cache.cache).await, Some);
        }

        UbaaClient::get_user_info(client).await
    }

    async fn exam_terms(&mut self) -> RoutedResult<Vec<Term>> {
        current_core!(self, guard, client);
        UbaaClient::exam_terms(client).await
    }
    async fn grades_overview(&mut self) -> RoutedResult<core::GradeOverview> {
        current_core!(self, guard, client);
        UbaaClient::grades_overview(client).await
    }
    async fn schedule_terms(&mut self) -> RoutedResult<Vec<Term>> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_academic(&cache.cache, core::AcademicQuery::Terms)
                    .await,
                cache::schedule_terms,
            );
        }

        UbaaClient::schedule_terms(client).await
    }

    async fn schedule_weeks(&mut self, term: &str) -> RoutedResult<Vec<Week>> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_academic(
                        &cache.cache,
                        core::AcademicQuery::Weeks { term: term.into() },
                    )
                    .await,
                cache::schedule_weeks,
            );
        }

        UbaaClient::schedule_weeks(client, term).await
    }

    async fn schedule_week(&mut self, term: &str, week: i32) -> RoutedResult<WeeklySchedule> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_academic(
                        &cache.cache,
                        core::AcademicQuery::Week {
                            term: term.into(),
                            week,
                        },
                    )
                    .await,
                cache::schedule_week,
            );
        }

        UbaaClient::schedule_week(client, term, week).await
    }

    async fn schedule_today(&mut self) -> RoutedResult<Vec<TodayClass>> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(client.refresh_cached_today(&cache.cache).await, Some);
        }

        UbaaClient::schedule_today(client).await
    }

    async fn exam_arrangement(&mut self, term: &str) -> RoutedResult<ExamArrangement> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_academic(
                        &cache.cache,
                        core::AcademicQuery::Exams { term: term.into() },
                    )
                    .await,
                cache::exam_arrangement,
            );
        }

        UbaaClient::exam_arrangement(client, term).await
    }

    async fn grades(&mut self, term: &str) -> RoutedResult<GradeData> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_academic(
                        &cache.cache,
                        core::AcademicQuery::Grades { term: term.into() },
                    )
                    .await,
                cache::grades,
            );
        }

        UbaaClient::grades(client, term).await
    }

    async fn classroom_search(&mut self, campus: i32, date: &str) -> RoutedResult<ClassroomQuery> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_academic(
                        &cache.cache,
                        core::AcademicQuery::Classrooms {
                            campus,
                            date: date.into(),
                        },
                    )
                    .await,
                cache::classroom_search,
            );
        }

        UbaaClient::classroom_search(client, campus, date).await
    }

    async fn spoc_assignments(&mut self) -> RoutedResult<SpocAssignments> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_home(&cache.cache, core::HomeQuery::SpocAssignments)
                    .await
                    .map(|v| v.result),
                cache::spoc_assignments,
            );
        }

        UbaaClient::spoc_assignments(client).await
    }
    async fn spoc_assignments_diagnostics(&mut self) -> RoutedResult<SpocAssignmentsDiagnostics> {
        current_core!(self, guard, client);

        UbaaClient::spoc_assignments_diagnostics(client).await
    }

    async fn spoc_assignment(&mut self, id: &str) -> RoutedResult<SpocAssignmentDetail> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_home(
                        &cache.cache,
                        core::HomeQuery::SpocDetail {
                            assignment_id: id.into(),
                        },
                    )
                    .await
                    .map(|v| v.result),
                cache::spoc_assignment,
            );
        }

        UbaaClient::spoc_assignment(client, id).await
    }

    async fn judge_assignments(
        &mut self,
        include_expired: bool,
    ) -> RoutedResult<Vec<JudgeAssignmentSummary>> {
        current_core!(self, guard, client);
        if let Some(cache) = self.cache {
            return project(
                client
                    .refresh_cached_judge(&cache.cache, include_expired)
                    .await,
                Some,
            );
        }

        UbaaClient::judge_assignments(client, include_expired).await
    }
    async fn judge_assignments_diagnostics(
        &mut self,
        include_expired: bool,
    ) -> RoutedResult<JudgeAssignmentsDiagnostics> {
        current_core!(self, guard, client);

        UbaaClient::judge_assignments_diagnostics(client, include_expired).await
    }

    async fn judge_assignment(
        &mut self,
        course_id: &str,
        id: &str,
    ) -> RoutedResult<JudgeAssignmentDetail> {
        current_core!(self, guard, client);

        UbaaClient::judge_assignment(client, course_id, id).await
    }

    async fn judge_assignment_details(
        &mut self,
        keys: &[JudgeAssignmentKey],
    ) -> RoutedResult<Vec<JudgeAssignmentDetail>> {
        current_core!(self, guard, client);

        UbaaClient::judge_assignment_details(client, keys).await
    }
}
