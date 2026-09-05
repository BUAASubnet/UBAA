//! `BridgeClient` 读取 API 的路线执行与公开方法。

use std::future::Future;
use std::pin::Pin;

use ubaa_core::facade as domain;
use ubaa_core::facade::{RoutedResult, UbaaClient};

use super::evaluation::map_evaluation;
use super::mappers::{
    map_bykc_chosen_courses, map_bykc_course, map_bykc_course_page, map_bykc_profile,
    map_bykc_statistics, map_cgyy_day_info, map_cgyy_lock_code, map_cgyy_order, map_cgyy_orders,
    map_cgyy_purpose_types, map_cgyy_sites, map_classroom_query, map_exam_arrangement,
    map_grade_data, map_judge_detail, map_judge_details, map_judge_summaries,
    map_libbook_area_detail, map_libbook_areas, map_libbook_bookings, map_libbook_libraries,
    map_libbook_seats, map_signin_classes, map_spoc_assignments, map_spoc_detail, map_terms,
    map_today_classes, map_weekly_schedule, map_weeks, map_ygdk_overview, map_ygdk_records,
};
use super::{
    BridgeCallerPinnedCgyyOrder, BridgeCallerPinnedCgyyOrders, BridgeCallerPinnedEvaluation,
    BridgeCallerPinnedYgdkOverview, BridgeCallerPinnedYgdkRecords, BridgeJudgeAssignmentKey,
    BridgeRoutedBykcChosenCourses, BridgeRoutedBykcCourse, BridgeRoutedBykcCourses,
    BridgeRoutedBykcProfile, BridgeRoutedBykcStatistics, BridgeRoutedCgyyDayInfo,
    BridgeRoutedCgyyLockCode, BridgeRoutedCgyyOrder, BridgeRoutedCgyyOrders,
    BridgeRoutedCgyyPurposeTypes, BridgeRoutedCgyySites, BridgeRoutedClassroomQuery,
    BridgeRoutedEvaluation, BridgeRoutedExamArrangement, BridgeRoutedGrades,
    BridgeRoutedJudgeAssignmentDetail, BridgeRoutedJudgeAssignmentDetails,
    BridgeRoutedJudgeSummaries, BridgeRoutedLibBookAreaDetail, BridgeRoutedLibBookAreas,
    BridgeRoutedLibBookBookings, BridgeRoutedLibBookLibraries, BridgeRoutedLibBookSeats,
    BridgeRoutedSigninClasses, BridgeRoutedSpocAssignmentDetail, BridgeRoutedSpocAssignments,
    BridgeRoutedTerms, BridgeRoutedTodayClasses, BridgeRoutedWeeklySchedule, BridgeRoutedWeeks,
    BridgeRoutedYgdkOverview, BridgeRoutedYgdkRecords,
};
use crate::api::client::{
    BridgeClient, BridgeConnectionMode, BridgeError, BridgeRouteDecision, catch_panic,
    disposed_error, map_route,
};

impl BridgeClient {
    async fn execute_read<T, O, F>(
        &self,
        call: F,
        mapper: fn(T) -> O,
    ) -> Result<(O, BridgeRouteDecision), BridgeError>
    where
        F: for<'a> FnOnce(
            &'a mut UbaaClient,
        ) -> Pin<Box<dyn Future<Output = RoutedResult<T>> + Send + 'a>>,
    {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let routed = call(client).await.map_err(BridgeError::from_routed)?;
            Ok((mapper(routed.data), map_route(routed.resolution)))
        })
        .await
    }

    async fn execute_caller_pinned_read<T, O, F>(
        &self,
        call: F,
        mapper: fn(T) -> O,
    ) -> Result<(O, BridgeConnectionMode), BridgeError>
    where
        F: for<'a> FnOnce(
            &'a mut UbaaClient,
        ) -> Pin<
            Box<dyn Future<Output = domain::Result<domain::CallerPinned<T>>> + Send + 'a>,
        >,
    {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let pinned = call(client)
                .await
                .map_err(|error| BridgeError::from_core(error, None))?;
            Ok((mapper(pinned.data), pinned.pinned_route.into()))
        })
        .await
    }

    pub async fn schedule_terms(&self) -> Result<BridgeRoutedTerms, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.schedule_terms().await }),
                map_terms,
            )
            .await?;
        Ok(BridgeRoutedTerms { data, route })
    }
    pub async fn schedule_weeks(&self, term: String) -> Result<BridgeRoutedWeeks, BridgeError> {
        let (data, route) = self
            .execute_read(
                move |client| Box::pin(async move { client.schedule_weeks(&term).await }),
                map_weeks,
            )
            .await?;
        Ok(BridgeRoutedWeeks { data, route })
    }
    pub async fn schedule_week(
        &self,
        term: String,
        week: i32,
    ) -> Result<BridgeRoutedWeeklySchedule, BridgeError> {
        let (data, route) = self
            .execute_read(
                move |client| Box::pin(async move { client.schedule_week(&term, week).await }),
                map_weekly_schedule,
            )
            .await?;
        Ok(BridgeRoutedWeeklySchedule { data, route })
    }
    pub async fn schedule_today(&self) -> Result<BridgeRoutedTodayClasses, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.schedule_today().await }),
                map_today_classes,
            )
            .await?;
        Ok(BridgeRoutedTodayClasses { data, route })
    }
    pub async fn exam_arrangement(
        &self,
        term: String,
    ) -> Result<BridgeRoutedExamArrangement, BridgeError> {
        let (data, route) = self
            .execute_read(
                move |client| Box::pin(async move { client.exam_arrangement(&term).await }),
                map_exam_arrangement,
            )
            .await?;
        Ok(BridgeRoutedExamArrangement { data, route })
    }
    pub async fn grades(&self, term: String) -> Result<BridgeRoutedGrades, BridgeError> {
        let (data, route) = self
            .execute_read(
                move |client| Box::pin(async move { client.grades(&term).await }),
                map_grade_data,
            )
            .await?;
        Ok(BridgeRoutedGrades { data, route })
    }
    pub async fn classroom_search(
        &self,
        campus: i32,
        date: String,
    ) -> Result<BridgeRoutedClassroomQuery, BridgeError> {
        let (data, route) = self
            .execute_read(
                move |client| Box::pin(async move { client.classroom_search(campus, &date).await }),
                map_classroom_query,
            )
            .await?;
        Ok(BridgeRoutedClassroomQuery { data, route })
    }
    pub async fn signin_today(&self) -> Result<BridgeRoutedSigninClasses, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.signin_today().await }),
                map_signin_classes,
            )
            .await?;
        Ok(BridgeRoutedSigninClasses { data, route })
    }
    pub async fn spoc_assignments(&self) -> Result<BridgeRoutedSpocAssignments, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.spoc_assignments().await }),
                map_spoc_assignments,
            )
            .await?;
        Ok(BridgeRoutedSpocAssignments { data, route })
    }
    pub async fn spoc_assignment(
        &self,
        assignment_id: String,
    ) -> Result<BridgeRoutedSpocAssignmentDetail, BridgeError> {
        let (data, route) = self
            .execute_read(
                move |client| Box::pin(async move { client.spoc_assignment(&assignment_id).await }),
                map_spoc_detail,
            )
            .await?;
        Ok(BridgeRoutedSpocAssignmentDetail { data, route })
    }
    pub async fn judge_assignments(
        &self,
        include_expired: bool,
    ) -> Result<BridgeRoutedJudgeSummaries, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.judge_assignments(include_expired).await }),
                map_judge_summaries,
            )
            .await?;
        Ok(BridgeRoutedJudgeSummaries { data, route })
    }
    pub async fn judge_assignment(
        &self,
        course_id: String,
        assignment_id: String,
    ) -> Result<BridgeRoutedJudgeAssignmentDetail, BridgeError> {
        let (data, route) = self
            .execute_read(
                move |client| {
                    Box::pin(
                        async move { client.judge_assignment(&course_id, &assignment_id).await },
                    )
                },
                map_judge_detail,
            )
            .await?;
        Ok(BridgeRoutedJudgeAssignmentDetail { data, route })
    }
    pub async fn judge_assignment_details(
        &self,
        keys: Vec<BridgeJudgeAssignmentKey>,
    ) -> Result<BridgeRoutedJudgeAssignmentDetails, BridgeError> {
        let keys = keys
            .into_iter()
            .map(|key| domain::JudgeAssignmentKey {
                course_id: key.course_id,
                assignment_id: key.assignment_id,
            })
            .collect::<Vec<_>>();
        let (data, route) = self
            .execute_read(
                move |client| Box::pin(async move { client.judge_assignment_details(&keys).await }),
                map_judge_details,
            )
            .await?;
        Ok(BridgeRoutedJudgeAssignmentDetails { data, route })
    }
    pub async fn bykc_profile(&self) -> Result<BridgeRoutedBykcProfile, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.bykc_profile().await }),
                map_bykc_profile,
            )
            .await?;
        Ok(BridgeRoutedBykcProfile { data, route })
    }
    pub async fn bykc_courses(
        &self,
        page: i32,
        size: i32,
        all: bool,
    ) -> Result<BridgeRoutedBykcCourses, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.bykc_courses(page, size, all).await }),
                map_bykc_course_page,
            )
            .await?;
        Ok(BridgeRoutedBykcCourses { data, route })
    }
    pub async fn bykc_course_detail(&self, id: i64) -> Result<BridgeRoutedBykcCourse, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.bykc_course_detail(id).await }),
                map_bykc_course,
            )
            .await?;
        Ok(BridgeRoutedBykcCourse { data, route })
    }
    pub async fn bykc_chosen_courses(&self) -> Result<BridgeRoutedBykcChosenCourses, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.bykc_chosen_courses().await }),
                map_bykc_chosen_courses,
            )
            .await?;
        Ok(BridgeRoutedBykcChosenCourses { data, route })
    }
    pub async fn bykc_statistics(&self) -> Result<BridgeRoutedBykcStatistics, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.bykc_statistics().await }),
                map_bykc_statistics,
            )
            .await?;
        Ok(BridgeRoutedBykcStatistics { data, route })
    }
    pub async fn libbook_libraries(
        &self,
        day: String,
    ) -> Result<BridgeRoutedLibBookLibraries, BridgeError> {
        let (data, route) = self
            .execute_read(
                move |client| Box::pin(async move { client.libbook_libraries(&day).await }),
                map_libbook_libraries,
            )
            .await?;
        Ok(BridgeRoutedLibBookLibraries { data, route })
    }
    pub async fn libbook_areas(
        &self,
        premises_id: String,
        storey_id: Option<String>,
        day: String,
    ) -> Result<BridgeRoutedLibBookAreas, BridgeError> {
        let (data, route) = self
            .execute_read(
                move |client| {
                    Box::pin(async move {
                        client
                            .libbook_areas(&premises_id, storey_id.as_deref(), &day)
                            .await
                    })
                },
                map_libbook_areas,
            )
            .await?;
        Ok(BridgeRoutedLibBookAreas { data, route })
    }
    pub async fn libbook_area_detail(
        &self,
        area_id: String,
    ) -> Result<BridgeRoutedLibBookAreaDetail, BridgeError> {
        let (data, route) = self
            .execute_read(
                move |client| Box::pin(async move { client.libbook_area_detail(&area_id).await }),
                map_libbook_area_detail,
            )
            .await?;
        Ok(BridgeRoutedLibBookAreaDetail { data, route })
    }
    pub async fn libbook_seats(
        &self,
        area_id: String,
        day: String,
        start_time: String,
        end_time: String,
    ) -> Result<BridgeRoutedLibBookSeats, BridgeError> {
        let (data, route) = self
            .execute_read(
                move |client| {
                    Box::pin(async move {
                        client
                            .libbook_seats(&area_id, &day, &start_time, &end_time)
                            .await
                    })
                },
                map_libbook_seats,
            )
            .await?;
        Ok(BridgeRoutedLibBookSeats { data, route })
    }
    pub async fn libbook_bookings(
        &self,
        page: i32,
        limit: i32,
    ) -> Result<BridgeRoutedLibBookBookings, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.libbook_bookings(page, limit).await }),
                map_libbook_bookings,
            )
            .await?;
        Ok(BridgeRoutedLibBookBookings { data, route })
    }
    pub async fn ygdk_overview(&self) -> Result<BridgeRoutedYgdkOverview, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.ygdk_overview().await }),
                map_ygdk_overview,
            )
            .await?;
        Ok(BridgeRoutedYgdkOverview { data, route })
    }
    /// 在调用方指定的已认证路线读取阳光打卡概览，不执行 Auto 探测或回退。
    pub async fn ygdk_overview_on_route(
        &self,
        route: BridgeConnectionMode,
    ) -> Result<BridgeCallerPinnedYgdkOverview, BridgeError> {
        let (data, pinned_route) = self
            .execute_caller_pinned_read(
                move |client| {
                    Box::pin(async move { client.ygdk_overview_on_route(route.into()).await })
                },
                map_ygdk_overview,
            )
            .await?;
        Ok(BridgeCallerPinnedYgdkOverview { data, pinned_route })
    }
    pub async fn ygdk_records(
        &self,
        page: i32,
        size: i32,
    ) -> Result<BridgeRoutedYgdkRecords, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.ygdk_records(page, size).await }),
                map_ygdk_records,
            )
            .await?;
        Ok(BridgeRoutedYgdkRecords { data, route })
    }
    /// 在调用方指定的已认证路线读取阳光打卡记录，不执行 Auto 探测或回退。
    pub async fn ygdk_records_on_route(
        &self,
        route: BridgeConnectionMode,
        page: i32,
        size: i32,
    ) -> Result<BridgeCallerPinnedYgdkRecords, BridgeError> {
        let (data, pinned_route) = self
            .execute_caller_pinned_read(
                move |client| {
                    Box::pin(
                        async move { client.ygdk_records_on_route(route.into(), page, size).await },
                    )
                },
                map_ygdk_records,
            )
            .await?;
        Ok(BridgeCallerPinnedYgdkRecords { data, pinned_route })
    }
    pub async fn cgyy_sites(&self) -> Result<BridgeRoutedCgyySites, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.cgyy_sites().await }),
                map_cgyy_sites,
            )
            .await?;
        Ok(BridgeRoutedCgyySites { data, route })
    }
    pub async fn cgyy_purpose_types(&self) -> Result<BridgeRoutedCgyyPurposeTypes, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.cgyy_purpose_types_diagnostics().await }),
                map_cgyy_purpose_types,
            )
            .await?;
        Ok(BridgeRoutedCgyyPurposeTypes { data, route })
    }
    pub async fn cgyy_day_info(
        &self,
        site_id: i32,
        date: String,
    ) -> Result<BridgeRoutedCgyyDayInfo, BridgeError> {
        let (data, route) = self
            .execute_read(
                move |client| Box::pin(async move { client.cgyy_day_info(site_id, &date).await }),
                map_cgyy_day_info,
            )
            .await?;
        Ok(BridgeRoutedCgyyDayInfo { data, route })
    }
    pub async fn cgyy_orders(
        &self,
        page: i32,
        size: i32,
    ) -> Result<BridgeRoutedCgyyOrders, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.cgyy_orders(page, size).await }),
                map_cgyy_orders,
            )
            .await?;
        Ok(BridgeRoutedCgyyOrders { data, route })
    }
    /// 在调用方指定的已认证路线读取场馆订单，不执行 Auto 探测或回退。
    pub async fn cgyy_orders_on_route(
        &self,
        route: BridgeConnectionMode,
        page: i32,
        size: i32,
    ) -> Result<BridgeCallerPinnedCgyyOrders, BridgeError> {
        let (data, pinned_route) = self
            .execute_caller_pinned_read(
                move |client| {
                    Box::pin(
                        async move { client.cgyy_orders_on_route(route.into(), page, size).await },
                    )
                },
                map_cgyy_orders,
            )
            .await?;
        Ok(BridgeCallerPinnedCgyyOrders { data, pinned_route })
    }
    pub async fn cgyy_order_detail(&self, id: i32) -> Result<BridgeRoutedCgyyOrder, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.cgyy_order_detail(id).await }),
                map_cgyy_order,
            )
            .await?;
        Ok(BridgeRoutedCgyyOrder { data, route })
    }
    /// 在调用方指定的已认证路线读取场馆订单详情，不执行 Auto 探测或回退。
    pub async fn cgyy_order_detail_on_route(
        &self,
        route: BridgeConnectionMode,
        id: i32,
    ) -> Result<BridgeCallerPinnedCgyyOrder, BridgeError> {
        let (data, pinned_route) = self
            .execute_caller_pinned_read(
                move |client| {
                    Box::pin(
                        async move { client.cgyy_order_detail_on_route(route.into(), id).await },
                    )
                },
                map_cgyy_order,
            )
            .await?;
        Ok(BridgeCallerPinnedCgyyOrder { data, pinned_route })
    }
    pub async fn cgyy_lock_code(&self) -> Result<BridgeRoutedCgyyLockCode, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.cgyy_lock_code().await }),
                map_cgyy_lock_code,
            )
            .await?;
        Ok(BridgeRoutedCgyyLockCode { data, route })
    }
    pub async fn evaluation_all(&self) -> Result<BridgeRoutedEvaluation, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.evaluation_all().await }),
                map_evaluation,
            )
            .await?;
        Ok(BridgeRoutedEvaluation { data, route })
    }
    /// 在调用方指定的已认证路线读取评教课程，不执行 Auto 探测或回退。
    pub async fn evaluation_all_on_route(
        &self,
        route: BridgeConnectionMode,
    ) -> Result<BridgeCallerPinnedEvaluation, BridgeError> {
        let (data, pinned_route) = self
            .execute_caller_pinned_read(
                move |client| {
                    Box::pin(async move { client.evaluation_all_on_route(route.into()).await })
                },
                map_evaluation,
            )
            .await?;
        ensure_caller_pinned_route(route, pinned_route)?;
        Ok(BridgeCallerPinnedEvaluation { data, pinned_route })
    }
}

pub(super) fn ensure_caller_pinned_route(
    expected: BridgeConnectionMode,
    actual: BridgeConnectionMode,
) -> Result<(), BridgeError> {
    if expected == actual {
        return Ok(());
    }
    Err(BridgeError {
        code: crate::api::client::BridgeErrorCode::OperationConflict,
        kind: crate::api::client::BridgeErrorKind::Input,
        retryable: false,
        message: "调用方固定路线与 Core 返回路线不一致".to_owned(),
        resolved_route: Some(actual),
    })
}
