//! 评教、博雅、签到与阳光打卡写入口。

use crate::connection::RouteResolution;
use crate::domain::{
    BykcActionResult, BykcSignRequest, ConnectionMode, ReadonlyFeature, SigninActionResult,
    YgdkClockinSubmitRequest, YgdkClockinSubmitResult, YgdkSubmitPreflight,
};

use super::super::client::UbaaClient;
use super::super::routing::{invalid_input, routed_error};
use super::super::types::{Operation, RoutedError, RoutedResult};

impl UbaaClient {
    /// 选择一门博雅课程。
    ///
    /// # Errors
    ///
    /// 会话所有权失效、博雅路线不可用或选课失败时返回带路线信息的错误。
    pub async fn bykc_select_course(&mut self, course_id: i64) -> RoutedResult<BykcActionResult> {
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Bykc))?;
        let result = {
            let runtime = self.runtime_for(resolution.mode);
            runtime.begin_non_idempotent_operation();
            crate::features::bykc::select_course(runtime, course_id).await
        };
        self.finish_routed_write(resolution, result)
    }

    /// 退选一门博雅课程。
    ///
    /// # Errors
    ///
    /// 会话所有权失效、博雅路线不可用或退选失败时返回带路线信息的错误。
    pub async fn bykc_deselect_course(&mut self, course_id: i64) -> RoutedResult<BykcActionResult> {
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Bykc))?;
        let result = {
            let runtime = self.runtime_for(resolution.mode);
            runtime.begin_non_idempotent_operation();
            crate::features::bykc::deselect_course(runtime, course_id).await
        };
        self.finish_routed_write(resolution, result)
    }

    /// 执行博雅课程签到或签退。
    ///
    /// # Errors
    ///
    /// 会话所有权失效、博雅路线不可用或签到操作失败时返回带路线信息的错误。
    pub async fn bykc_sign_course(
        &mut self,
        request: BykcSignRequest,
    ) -> RoutedResult<BykcActionResult> {
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Bykc))?;
        let result = {
            let runtime = self.runtime_for(resolution.mode);
            runtime.begin_non_idempotent_operation();
            crate::features::bykc::sign_course(runtime, request).await
        };
        self.finish_routed_write(resolution, result)
    }

    /// 只读复核博雅签到或签退资格，不发送写请求。
    ///
    /// # Errors
    ///
    /// 会话所有权失效、路线不可用、资格不足或输入无效时返回带路线信息的错误。
    pub async fn preflight_bykc_sign_course(
        &mut self,
        request: &BykcSignRequest,
    ) -> RoutedResult<crate::domain::BykcSignPreflight> {
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Bykc))?;
        let result = crate::features::bykc::preflight_sign_course(
            self.runtime_for(resolution.mode),
            request,
        )
        .await
        .map(|(preflight, _)| preflight);
        self.finish_routed(resolution, result)
    }

    /// 执行指定课程的课堂签到。
    ///
    /// # Errors
    ///
    /// 会话所有权失效、课堂签到路线不可用或签到失败时返回带路线信息的错误。
    pub async fn signin_perform(&mut self, course_id: &str) -> RoutedResult<SigninActionResult> {
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Signin))?;
        let result = {
            let runtime = self.runtime_for(resolution.mode);
            runtime.begin_non_idempotent_operation();
            crate::features::signin::perform_signin(runtime, course_id).await
        };
        self.finish_routed_write(resolution, result)
    }

    /// 只读复核指定课堂签到目标的当前资格。
    ///
    /// # Errors
    ///
    /// 会话所有权失效、路线不可用、目标不唯一或资格不足时返回带路线信息的错误。
    pub async fn preflight_signin_perform(
        &mut self,
        course_id: &str,
    ) -> RoutedResult<crate::domain::SigninClass> {
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Signin))?;
        let result =
            crate::features::signin::preflight_signin(self.runtime_for(resolution.mode), course_id)
                .await;
        self.finish_routed(resolution, result)
    }

    /// 提交一条阳光打卡记录。
    ///
    /// # Errors
    ///
    /// 会话所有权失效、阳光打卡路线不可用或提交失败时返回带路线信息的错误。
    pub async fn ygdk_submit(
        &mut self,
        request: YgdkClockinSubmitRequest,
    ) -> RoutedResult<YgdkClockinSubmitResult> {
        validate_ygdk_submit_pre_route(&request)?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Ygdk))?;
        self.ygdk_submit_resolved(request, resolution).await
    }

    /// fresh 复核阳光打卡 typed 目标并返回规范化请求，不上传照片或发送最终写。
    ///
    /// # Errors
    ///
    /// 输入无效、会话所有权失效、路线不可用或目标无法唯一证明时返回带路线信息的错误。
    pub async fn preflight_ygdk_submit(
        &mut self,
        request: &YgdkClockinSubmitRequest,
    ) -> RoutedResult<YgdkSubmitPreflight> {
        validate_ygdk_submit_pre_route(request)?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Ygdk))?;
        let result =
            crate::features::ygdk::preflight_submit(self.runtime_for(resolution.mode), request)
                .await;
        self.finish_routed(resolution, result)
    }

    /// 仅当本次唯一权威路线仍与调用方预期一致时提交阳光打卡。
    ///
    /// # Errors
    ///
    /// 输入无效、路线变化、fresh 资格不足、上传失败或最终结果未知时返回带路线信息的错误。
    pub async fn ygdk_submit_if_route_matches(
        &mut self,
        request: YgdkClockinSubmitRequest,
        expected_route: ConnectionMode,
    ) -> RoutedResult<YgdkClockinSubmitResult> {
        validate_ygdk_submit_pre_route(&request)?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Ygdk))?;
        if resolution.mode != expected_route {
            return Err(routed_error(
                invalid_input("阳光打卡提交路线已变化，请重新确认"),
                resolution,
            ));
        }
        self.ygdk_submit_resolved(request, resolution).await
    }

    async fn ygdk_submit_resolved(
        &mut self,
        request: YgdkClockinSubmitRequest,
        resolution: RouteResolution,
    ) -> RoutedResult<YgdkClockinSubmitResult> {
        let result = {
            let runtime = self.runtime_for(resolution.mode);
            runtime.begin_non_idempotent_operation();
            crate::features::ygdk::submit_clockin(runtime, request).await
        };
        self.finish_routed_write(resolution, result)
    }
}

fn validate_ygdk_submit_pre_route(
    request: &YgdkClockinSubmitRequest,
) -> std::result::Result<(), RoutedError> {
    crate::features::ygdk::validate_submit_request(request).map_err(|error| RoutedError {
        error,
        resolution: None,
    })
}
