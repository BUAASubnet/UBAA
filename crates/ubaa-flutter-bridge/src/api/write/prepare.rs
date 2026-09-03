//! 写入意图的准备、路线解析与一次性保存。

use super::support::{
    cgyy_canonical, digest, ensure_bykc_course_target, ensure_bykc_deselect_allowed,
    ensure_bykc_select_allowed, invalid_input, now_seconds, random_id, validate_cgyy_request,
    validate_id, validate_id_i32, validate_text, validate_ygdk_request, ygdk_canonical,
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
use ubaa_core::facade::ReadonlyFeature;

impl BridgeClient {
    async fn store_write_intent(
        &self,
        operation: BridgeWriteOperation,
        canonical: String,
        target_summary: String,
        warnings: Vec<String>,
        pending: PendingWrite,
        resolved_route: BridgeConnectionMode,
    ) -> BridgeWriteIntent {
        let intent_id = random_id();
        let request_digest = digest(&canonical);
        let expires_at = now_seconds().saturating_add(120);
        self.write_intents.lock().await.insert(
            intent_id.clone(),
            PendingEntry {
                request: pending,
                expires_at,
                resolved_route,
            },
        );
        BridgeWriteIntent {
            intent_id,
            operation,
            target_summary,
            resolved_route,
            warnings,
            expires_at,
            request_digest,
        }
    }

    async fn prepare_write(
        &self,
        feature: ReadonlyFeature,
        operation: BridgeWriteOperation,
        canonical: String,
        target_summary: String,
        warnings: Vec<String>,
        pending: PendingWrite,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let resolution = client
                .resolve_route_for_feature(feature)
                .map_err(|error| BridgeError::from_core(error, None))?;
            Ok(self
                .store_write_intent(
                    operation,
                    canonical,
                    target_summary,
                    warnings,
                    pending,
                    resolution.mode.into(),
                )
                .await)
        })
        .await
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
            Ok(self
                .store_write_intent(
                    BridgeWriteOperation::BykcSelectCourse,
                    format!("course_id={}", request.course_id),
                    "选择一门博雅课程".to_owned(),
                    vec!["提交后请刷新已选课程确认结果".to_owned()],
                    PendingWrite::BykcSelect(request),
                    current.resolution.mode.into(),
                )
                .await)
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
            Ok(self
                .store_write_intent(
                    BridgeWriteOperation::BykcDeselectCourse,
                    format!("course_id={}", request.course_id),
                    "退选一门博雅课程".to_owned(),
                    vec!["请确认课程与退选截止时间".to_owned()],
                    PendingWrite::BykcDeselect(request),
                    current.resolution.mode.into(),
                )
                .await)
        })
        .await
    }
    pub async fn prepare_bykc_sign_course(
        &self,
        request: BridgeBykcSignCourseRequest,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        validate_id(request.course_id)?;
        self.prepare_write(
            ReadonlyFeature::Bykc,
            BridgeWriteOperation::BykcSignCourse,
            format!(
                "course_id={};lat={:?};lng={:?};sign_type={}",
                request.course_id, request.lat, request.lng, request.sign_type
            ),
            "提交博雅课程签到".to_owned(),
            vec!["位置只在本次请求中使用".to_owned()],
            PendingWrite::BykcSign(request),
        )
        .await
    }
    pub async fn prepare_signin_perform(
        &self,
        request: BridgeSigninPerformRequest,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        validate_text(&request.course_id)?;
        self.prepare_write(
            ReadonlyFeature::Signin,
            BridgeWriteOperation::SigninPerform,
            format!("course_id={}", request.course_id),
            "提交课堂签到".to_owned(),
            vec!["请确认课程和当前签到窗口".to_owned()],
            PendingWrite::Signin(request),
        )
        .await
    }
    pub async fn prepare_libbook_reserve(
        &self,
        request: BridgeLibbookReserveRequest,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        validate_text(&request.area_id)?;
        validate_text(&request.seat_id)?;
        validate_text(&request.day)?;
        let canonical = format!(
            "area={};seat={};day={};segment={};start={};end={}",
            request.area_id,
            request.seat_id,
            request.day,
            request.segment,
            request.start_time,
            request.end_time
        );
        self.prepare_write(
            ReadonlyFeature::LibBook,
            BridgeWriteOperation::LibbookReserve,
            canonical,
            "预约图书馆座位".to_owned(),
            vec!["提交后将通过预约记录核对状态".to_owned()],
            PendingWrite::LibbookReserve(request),
        )
        .await
    }
    pub async fn prepare_libbook_cancel_booking(
        &self,
        request: BridgeLibbookCancelBookingRequest,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        validate_text(&request.id)?;
        self.prepare_write(
            ReadonlyFeature::LibBook,
            BridgeWriteOperation::LibbookCancelBooking,
            format!("id={}", request.id),
            "取消一条图书馆预约".to_owned(),
            vec!["取消操作可能不可恢复".to_owned()],
            PendingWrite::LibbookCancel(request),
        )
        .await
    }
    pub async fn prepare_ygdk_submit(
        &self,
        request: BridgeYgdkSubmitRequest,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        validate_ygdk_request(&request)?;
        let canonical = ygdk_canonical(&request);
        self.prepare_write(
            ReadonlyFeature::Ygdk,
            BridgeWriteOperation::YgdkSubmit,
            canonical,
            "提交一条阳光打卡记录".to_owned(),
            vec!["照片仅在本次操作内存中保留".to_owned()],
            PendingWrite::Ygdk(request),
        )
        .await
    }
    pub async fn prepare_cgyy_submit_reservation(
        &self,
        request: BridgeCgyySubmitReservationRequest,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        validate_cgyy_request(&request)?;
        let canonical = cgyy_canonical(&request);
        self.prepare_write(
            ReadonlyFeature::Cgyy,
            BridgeWriteOperation::CgyySubmitReservation,
            canonical,
            "提交场馆预约申请".to_owned(),
            vec![
                "如需验证码，材料只在本次操作内存中使用".to_owned(),
                "提交后必须查询订单核对结果".to_owned(),
            ],
            PendingWrite::CgyyReserve(request),
        )
        .await
    }
    pub async fn prepare_cgyy_cancel_order(
        &self,
        request: BridgeCgyyCancelOrderRequest,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        validate_id_i32(request.id)?;
        self.prepare_write(
            ReadonlyFeature::Cgyy,
            BridgeWriteOperation::CgyyCancelOrder,
            format!("id={}", request.id),
            "取消一笔场馆预约订单".to_owned(),
            vec!["取消操作可能不可恢复".to_owned()],
            PendingWrite::CgyyCancel(request),
        )
        .await
    }
    pub async fn prepare_evaluation_submit_courses(
        &self,
        request: BridgeEvaluationSubmitCoursesRequest,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        if request.courses.is_empty() {
            return Err(invalid_input("至少选择一门待评课程"));
        }
        let canonical = request
            .courses
            .iter()
            .map(|c| format!("{}:{}:{}", c.id, c.rwid, c.wjid))
            .collect::<Vec<_>>()
            .join("|");
        self.prepare_write(
            ReadonlyFeature::Evaluation,
            BridgeWriteOperation::EvaluationSubmitCourses,
            canonical,
            format!("提交 {} 门课程的教学评教", request.courses.len()),
            vec!["评教提交后不可撤销，请确认课程数量".to_owned()],
            PendingWrite::Evaluation(request),
        )
        .await
    }
}
