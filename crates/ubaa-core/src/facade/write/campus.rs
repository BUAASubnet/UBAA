//! 评教、博雅、签到与阳光打卡写入口。

use crate::domain::{
    BykcActionResult, BykcSignRequest, EvaluationCourse, EvaluationResult, ReadonlyFeature,
    SigninActionResult, YgdkClockinSubmitRequest, YgdkClockinSubmitResult,
};

use super::super::client::UbaaClient;
use super::super::types::{Operation, RoutedResult};

impl UbaaClient {
    /// 提交由宿主构造的评教结果列表。
    ///
    /// # Errors
    ///
    /// 会话所有权失效、评教路线不可用或提交失败时返回带路线信息的错误。
    pub async fn evaluation_submit(
        &mut self,
        pjjglist: Vec<serde_json::Value>,
    ) -> RoutedResult<Vec<EvaluationResult>> {
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Evaluation))?;
        let result = crate::features::evaluation::submit_payload(
            self.runtime_for(resolution.mode),
            pjjglist,
        )
        .await;
        self.finish_routed(resolution, result)
    }

    /// 按冻结问卷链自动构造并提交课程评教。
    ///
    /// # Errors
    ///
    /// 会话所有权失效、评教路线不可用或问卷提交失败时返回带路线信息的错误。
    pub async fn evaluation_submit_courses(
        &mut self,
        courses: Vec<EvaluationCourse>,
    ) -> RoutedResult<Vec<EvaluationResult>> {
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Evaluation))?;
        let result =
            crate::features::evaluation::submit_courses(self.runtime_for(resolution.mode), courses)
                .await;
        self.finish_routed(resolution, result)
    }

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
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Ygdk))?;
        let result =
            crate::features::ygdk::submit_clockin(self.runtime_for(resolution.mode), request).await;
        self.finish_routed(resolution, result)
    }
}
