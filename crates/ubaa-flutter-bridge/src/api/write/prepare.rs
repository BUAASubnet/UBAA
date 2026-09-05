//! 写入意图的准备、路线解析与一次性保存。

use super::support::{
    bykc_sign_canonical, cgyy_canonical, digest, ensure_bykc_course_target,
    ensure_bykc_deselect_allowed, ensure_bykc_select_allowed, map_bykc_sign_preflight_error,
    map_cgyy_cancel_preflight_error, map_cgyy_preflight_error, map_cgyy_request,
    map_evaluation_preflight_error, map_evaluation_request, map_libbook_cancel_preflight_error,
    map_libbook_preflight_error, map_ygdk_preflight_error, map_ygdk_request, now_seconds,
    random_id, safe_summary_label, validate_bykc_sign_request, validate_cgyy_request, validate_id,
    validate_id_i32, validate_text, validate_ygdk_request, ygdk_canonical,
};
use super::{
    BridgeBykcCourseRequest, BridgeBykcSignCourseRequest, BridgeCgyyCancelOrderRequest,
    BridgeCgyySubmitReservationRequest, BridgeEvaluationSubmitCoursesRequest,
    BridgeLibbookCancelBookingRequest, BridgeLibbookReserveRequest, BridgeSigninPerformRequest,
    BridgeWriteIntent, BridgeWriteOperation, BridgeYgdkSubmitRequest, PendingEntry, PendingWrite,
};
use crate::api::client::{
    BridgeClient, BridgeConnectionMode, BridgeError, catch_panic, disposed_error,
};
use ubaa_core::facade as domain;

impl BridgeClient {
    async fn store_write_intent(
        &self,
        operation: BridgeWriteOperation,
        canonical: String,
        target_summary: String,
        warnings: Vec<String>,
        pending: PendingWrite,
        resolved_route: BridgeConnectionMode,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        let intent_id = random_id();
        let request_digest = digest(&canonical);
        let now = now_seconds();
        let expires_at = now.saturating_add(120);
        let mut intents = self.write_intents.lock().await;
        intents.retain(|_, entry| entry.expires_at > now);
        let conflict_key = pending.conflict_key();
        if intents.values().any(|entry| {
            pending.conflicts_with(&entry.request) || conflict_key == entry.conflict_key
        }) {
            return Err(BridgeError::local(
                crate::api::client::BridgeErrorCode::OperationConflict,
                crate::api::client::BridgeErrorKind::Input,
                true,
                "an equivalent write is already awaiting confirmation",
            ));
        }
        intents.insert(
            intent_id.clone(),
            PendingEntry {
                request: pending,
                expires_at,
                resolved_route,
                conflict_key,
            },
        );
        Ok(BridgeWriteIntent {
            intent_id,
            operation,
            target_summary,
            resolved_route,
            warnings,
            expires_at,
            request_digest,
        })
    }

    pub async fn prepare_bykc_select_course(
        &self,
        request: BridgeBykcCourseRequest,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        validate_id(request.course_id)?;
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let current = client
                .bykc_course_detail(request.course_id)
                .await
                .map_err(BridgeError::from_routed)?;
            ensure_bykc_course_target(request.course_id, current.data.id)?;
            ensure_bykc_select_allowed(current.data.select_eligibility)?;
            let target_summary = bykc_select_summary(&current.data);
            self.store_write_intent(
                BridgeWriteOperation::BykcSelectCourse,
                format!("course_id={}", request.course_id),
                target_summary,
                vec!["提交后请刷新已选课程确认结果".to_owned()],
                PendingWrite::BykcSelect(request),
                current.resolution.mode.into(),
            )
            .await
        })
        .await
    }
    pub async fn prepare_bykc_deselect_course(
        &self,
        request: BridgeBykcCourseRequest,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        validate_id(request.course_id)?;
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let current = client
                .bykc_course_detail(request.course_id)
                .await
                .map_err(BridgeError::from_routed)?;
            ensure_bykc_course_target(request.course_id, current.data.id)?;
            ensure_bykc_deselect_allowed(current.data.deselect_eligibility)?;
            let target_summary = bykc_deselect_summary(&current.data);
            self.store_write_intent(
                BridgeWriteOperation::BykcDeselectCourse,
                format!("course_id={}", request.course_id),
                target_summary,
                vec!["请确认课程与退选截止时间".to_owned()],
                PendingWrite::BykcDeselect(request),
                current.resolution.mode.into(),
            )
            .await
        })
        .await
    }
    pub async fn prepare_bykc_sign_course(
        &self,
        request: BridgeBykcSignCourseRequest,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        validate_bykc_sign_request(&request)?;
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let current = client
                .preflight_bykc_sign_course(&domain::BykcSignRequest {
                    course_id: request.course_id,
                    lat: request.lat,
                    lng: request.lng,
                    sign_type: request.sign_type,
                })
                .await
                .map_err(map_bykc_sign_preflight_error)?;
            let action = if request.sign_type == 1 {
                "签到"
            } else {
                "签退"
            };
            let course_name = safe_summary_label(&current.data.course_name, "博雅课程");
            let location_warning = match current.data.location_requirement {
                domain::BykcSignLocationRequirement::ConfiguredRange => {
                    "位置要求：由 Core 在已验证签到范围内生成本次坐标"
                }
                domain::BykcSignLocationRequirement::ProvidedCoordinates => {
                    "位置要求：本次已提供并校验经纬度；Core 将按完整签到点配置生成或回退"
                }
            };
            self.store_write_intent(
                BridgeWriteOperation::BykcSignCourse,
                bykc_sign_canonical(&request),
                format!(
                    "{course_name}（课程 {}）·{action}·{} 至 {}",
                    current.data.course_id, current.data.window_start, current.data.window_end,
                ),
                vec![
                    location_warning.to_owned(),
                    "提交前将再次复核当前学期、考勤状态与时间窗".to_owned(),
                ],
                PendingWrite::BykcSign(request),
                current.resolution.mode.into(),
            )
            .await
        })
        .await
    }
    pub async fn prepare_signin_perform(
        &self,
        mut request: BridgeSigninPerformRequest,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        request.course_id = request.course_id.trim().to_owned();
        validate_text(&request.course_id)?;
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let current = client
                .preflight_signin_perform(&request.course_id)
                .await
                .map_err(BridgeError::from_routed)?;
            let course_name = safe_summary_label(&current.data.course_name, "课堂签到课程");
            let schedule_id = safe_summary_label(&request.course_id, "未知安排");
            let begin = safe_summary_label(&current.data.class_begin_time, "时间未知");
            let end = safe_summary_label(&current.data.class_end_time, "时间未知");
            let target_summary =
                format!("{course_name}（安排 {schedule_id}）·{begin} 至 {end}·可签到");
            self.store_write_intent(
                BridgeWriteOperation::SigninPerform,
                format!("course_id={}", request.course_id),
                target_summary,
                vec!["提交后请刷新今日签到状态确认结果".to_owned()],
                PendingWrite::Signin(request),
                current.resolution.mode.into(),
            )
            .await
        })
        .await
    }
    pub async fn prepare_libbook_reserve(
        &self,
        mut request: BridgeLibbookReserveRequest,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        request.area_id = request.area_id.trim().to_owned();
        request.seat_id = request.seat_id.trim().to_owned();
        request.day = request.day.trim().to_owned();
        request.segment = request.segment.trim().to_owned();
        request.start_time = request.start_time.trim().to_owned();
        request.end_time = request.end_time.trim().to_owned();
        validate_text(&request.area_id)?;
        validate_text(&request.seat_id)?;
        validate_text(&request.day)?;
        validate_text(&request.segment)?;
        validate_text(&request.start_time)?;
        validate_text(&request.end_time)?;
        let canonical = format!(
            "area={};seat={};day={};segment={};start={};end={}",
            request.area_id,
            request.seat_id,
            request.day,
            request.segment,
            request.start_time,
            request.end_time
        );
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let current = client
                .preflight_libbook_reserve(&domain::LibBookReserveRequest {
                    area_id: request.area_id.clone(),
                    seat_id: request.seat_id.clone(),
                    day: request.day.clone(),
                    segment: request.segment.clone(),
                    start_time: request.start_time.clone(),
                    end_time: request.end_time.clone(),
                })
                .await
                .map_err(map_libbook_preflight_error)?;
            let seat_name = safe_summary_label(&current.data.seat_name, "图书馆座位");
            let seat_no = safe_summary_label(&current.data.seat_no, "座位号未知");
            let area_id = safe_summary_label(&request.area_id, "分区未知");
            let seat_id = safe_summary_label(&request.seat_id, "座位未知");
            let day = safe_summary_label(&request.day, "日期未知");
            let segment = safe_summary_label(&request.segment, "时段未知");
            let start_time = safe_summary_label(&request.start_time, "开始时间未知");
            let end_time = safe_summary_label(&request.end_time, "结束时间未知");
            self.store_write_intent(
                BridgeWriteOperation::LibbookReserve,
                canonical,
                format!(
                    "{seat_name}（座位号 {seat_no}）·分区 {area_id}·座位 {seat_id}·日期 {day}·时段 {segment}·{start_time} 至 {end_time}",
                ),
                vec!["提交后将通过预约记录核对状态".to_owned()],
                PendingWrite::LibbookReserve(request),
                current.resolution.mode.into(),
            )
            .await
        })
        .await
    }
    pub async fn prepare_libbook_cancel_booking(
        &self,
        mut request: BridgeLibbookCancelBookingRequest,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        request.id = request.id.trim().to_owned();
        validate_text(&request.id)?;
        validate_id_i32(request.page)?;
        validate_id_i32(request.limit)?;
        let canonical = format!(
            "id={};page={};limit={}",
            request.id, request.page, request.limit
        );
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let current = client
                .preflight_libbook_cancel(&domain::LibBookCancelRequest {
                    booking_id: request.id.clone(),
                    page: request.page,
                    limit: request.limit,
                })
                .await
                .map_err(map_libbook_cancel_preflight_error)?;
            if current.data.booking_id.trim() != request.id {
                return Err(BridgeError::local(
                    crate::api::client::BridgeErrorCode::UpstreamChanged,
                    crate::api::client::BridgeErrorKind::Upstream,
                    false,
                    "图书馆预约取消目标与请求不一致",
                ));
            }
            let booking_name = safe_summary_label(&current.data.booking_name, "图书馆预约");
            let area_name = safe_summary_label(&current.data.area_name, "分区未知");
            let seat_no = safe_summary_label(&current.data.seat_no, "座位号未知");
            let booking_id = safe_summary_label(&current.data.booking_id, "预约未知");
            let day = safe_summary_label(&current.data.day, "日期未知");
            let begin_time = safe_summary_label(&current.data.begin_time, "开始时间未知");
            let end_time = safe_summary_label(&current.data.end_time, "结束时间未知");
            self.store_write_intent(
                BridgeWriteOperation::LibbookCancelBooking,
                canonical,
                format!(
                    "{booking_name}（预约 {booking_id}）·{area_name}·座位 {seat_no}·日期 {day}·{begin_time} 至 {end_time}",
                ),
                vec![
                    "取消操作可能不可恢复".to_owned(),
                    "提交后请刷新预约记录确认结果".to_owned(),
                ],
                PendingWrite::LibbookCancel(request),
                current.resolution.mode.into(),
            )
            .await
        })
        .await
    }
    pub async fn prepare_ygdk_submit(
        &self,
        request: BridgeYgdkSubmitRequest,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        validate_ygdk_request(&request)?;
        let canonical = ygdk_canonical(&request);
        let domain_request = map_ygdk_request(request);
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let current = client
                .preflight_ygdk_submit(&domain_request)
                .await
                .map_err(map_ygdk_preflight_error)?;
            let target = current.data.request.target;
            let item_name = safe_summary_label(&current.data.item_name, "阳光打卡项目");
            self.store_write_intent(
                BridgeWriteOperation::YgdkSubmit,
                canonical,
                format!(
                    "{item_name}（分类 {} · 项目 {}）",
                    target.classify_id, target.item_id
                ),
                vec![
                    "照片仅在本次操作内存中保留".to_owned(),
                    "提交后将固定原路线刷新概览与记录，回读不替代结果确认".to_owned(),
                ],
                PendingWrite::Ygdk(current.data.request),
                current.resolution.mode.into(),
            )
            .await
        })
        .await
    }
    pub async fn prepare_cgyy_submit_reservation(
        &self,
        mut request: BridgeCgyySubmitReservationRequest,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        validate_cgyy_request(&request)?;
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let domain_request = map_cgyy_request(request.clone());
            let current = client
                .preflight_cgyy_reservation(&domain_request)
                .await
                .map_err(map_cgyy_preflight_error)?;
            request.selections = current
                .data
                .targets
                .iter()
                .map(|target| super::BridgeCgyyReservationSelection {
                    space_id: target.space_id,
                    time_id: target.time_id,
                    venue_space_group_id: target.venue_space_group_id,
                })
                .collect();
            request.venue_site_id = current.data.venue_site_id;
            request.reservation_date = current.data.reservation_date.clone();
            request.phone = request.phone.trim().to_owned();
            request.theme = request.theme.trim().to_owned();
            request.activity_content = request.activity_content.trim().to_owned();
            request.joiners = request.joiners.trim().to_owned();
            let times = current
                .data
                .targets
                .iter()
                .map(|target| target.time_id.to_string())
                .collect::<Vec<_>>()
                .join(",");
            let first = current.data.targets.first().ok_or_else(|| {
                BridgeError::local(
                    crate::api::client::BridgeErrorCode::UpstreamChanged,
                    crate::api::client::BridgeErrorKind::Upstream,
                    false,
                    "场馆预约资格缺少权威目标",
                )
            })?;
            let reservation_date = safe_summary_label(&current.data.reservation_date, "预约日期");
            let target_summary = format!(
                "场馆 {} · 日期 {} · 空间 {} · 时段 {}",
                current.data.venue_site_id, reservation_date, first.space_id, times,
            );
            let canonical = cgyy_canonical(&request);
            self.store_write_intent(
                BridgeWriteOperation::CgyySubmitReservation,
                canonical,
                target_summary,
                vec![
                    "如需验证码，材料只在本次操作内存中使用".to_owned(),
                    "提交后必须查询订单核对结果".to_owned(),
                ],
                PendingWrite::CgyyReserve(request),
                current.resolution.mode.into(),
            )
            .await
        })
        .await
    }
    pub async fn prepare_cgyy_cancel_order(
        &self,
        request: BridgeCgyyCancelOrderRequest,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        validate_id_i32(request.order_id)?;
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let current = client
                .preflight_cgyy_cancel(&domain::CgyyCancelOrderRequest {
                    order_id: request.order_id,
                })
                .await
                .map_err(map_cgyy_cancel_preflight_error)?;
            if current.data.target.order_id != request.order_id {
                return Err(BridgeError::local(
                    crate::api::client::BridgeErrorCode::UpstreamChanged,
                    crate::api::client::BridgeErrorKind::Upstream,
                    false,
                    "场馆订单取消目标与请求不一致",
                ));
            }
            let start = safe_optional_summary(current.data.reservation_start_date.as_deref());
            let end = safe_optional_summary(current.data.reservation_end_date.as_deref());
            self.store_write_intent(
                BridgeWriteOperation::CgyyCancelOrder,
                format!("order_id={}", request.order_id),
                format!(
                    "场馆订单 {} · 状态 {}/{} · 预约 {} 至 {}",
                    request.order_id,
                    current.data.order_status,
                    current.data.check_status,
                    start,
                    end,
                ),
                vec![
                    "取消操作可能不可恢复".to_owned(),
                    "提交后请刷新订单列表与详情核对结果".to_owned(),
                ],
                PendingWrite::CgyyCancel(request),
                current.resolution.mode.into(),
            )
            .await
        })
        .await
    }
    pub async fn prepare_evaluation_submit_courses(
        &self,
        request: BridgeEvaluationSubmitCoursesRequest,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        let request = map_evaluation_request(request)?;
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let routed = client
                .preflight_evaluation_submit_courses(&request)
                .await
                .map_err(|error| map_evaluation_preflight_error(&error))?;
            let route: BridgeConnectionMode = routed.resolution.mode.into();
            let preflight = routed.data;
            let courses_match = preflight.targets == request.targets
                && preflight.courses.len() == request.targets.len()
                && preflight
                    .courses
                    .iter()
                    .zip(&request.targets)
                    .all(|(course, target)| {
                        course.submit_eligibility == domain::ActionEligibility::Allowed
                            && course.submit_target.as_ref() == Some(target)
                            && !course.is_evaluated
                            && !course.kcmc.trim().is_empty()
                            && !course.bpmc.trim().is_empty()
                            && course.id
                                == format!(
                                    "{}_{}_{}_{}",
                                    target.rwid,
                                    target.wjid,
                                    target.kcdm,
                                    target.bpdm.as_deref().unwrap_or_default(),
                                )
                    });
            if !courses_match {
                return Err(BridgeError {
                    code: crate::api::client::BridgeErrorCode::UpstreamChanged,
                    kind: crate::api::client::BridgeErrorKind::Upstream,
                    retryable: false,
                    message: "教学评教资格核对响应无效".to_owned(),
                    resolved_route: Some(route),
                });
            }
            let count = preflight.targets.len();
            let pending = PendingWrite::Evaluation(domain::EvaluationSubmitCoursesRequest {
                targets: preflight.targets,
            });
            let canonical = pending.conflict_key();
            self.store_write_intent(
                BridgeWriteOperation::EvaluationSubmitCourses,
                canonical,
                format!("提交 {count} 门课程的教学评教"),
                vec!["评教提交后不可撤销，请确认课程数量".to_owned()],
                pending,
                route,
            )
            .await
        })
        .await
    }
}

fn bykc_select_summary(course: &domain::BykcCourse) -> String {
    let name = safe_summary_label(&course.course_name, "博雅课程");
    let select_start = safe_optional_summary(course.course_select_start_date.as_deref());
    let select_end = safe_optional_summary(course.course_select_end_date.as_deref());
    let current = course
        .course_current_count
        .map_or_else(|| "未知".to_owned(), |value| value.to_string());
    let maximum = course
        .course_max_count
        .map_or_else(|| "未知".to_owned(), |value| value.to_string());
    format!(
        "{name}（课程 {}）·选课期 {select_start} 至 {select_end}·容量 {current}/{maximum}",
        course.id
    )
}

fn bykc_deselect_summary(course: &domain::BykcCourse) -> String {
    let name = safe_summary_label(&course.course_name, "博雅课程");
    let cancel_end = safe_optional_summary(course.course_cancel_end_date.as_deref());
    format!("{name}（课程 {}）·退选截止 {cancel_end}", course.id)
}

fn safe_optional_summary(value: Option<&str>) -> String {
    value.map_or_else(
        || "未知".to_owned(),
        |value| safe_summary_label(value, "未知"),
    )
}
