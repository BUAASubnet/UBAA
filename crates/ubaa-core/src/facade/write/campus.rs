//! 评教、博雅、签到与阳光打卡写入口。

use crate::domain::{
    BykcActionResult, BykcSignRequest, ConnectionMode, EvaluationCourse, EvaluationResult,
    ReadonlyFeature, SigninActionResult, YgdkClockinSubmitRequest, YgdkClockinSubmitResult,
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
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::evaluation::submit_payload(
                    &mut self.direct_runtime,
                    pjjglist.clone(),
                )
                .await
            }
            ConnectionMode::WebVpn => {
                crate::features::evaluation::submit_payload(&mut self.webvpn_runtime, pjjglist)
                    .await
            }
        };
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
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::evaluation::submit_courses(
                    &mut self.direct_runtime,
                    courses.clone(),
                )
                .await
            }
            ConnectionMode::WebVpn => {
                crate::features::evaluation::submit_courses(&mut self.webvpn_runtime, courses).await
            }
        };
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
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::bykc::select_course(&mut self.direct_runtime, course_id).await
            }
            ConnectionMode::WebVpn => {
                crate::features::bykc::select_course(&mut self.webvpn_runtime, course_id).await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 退选一门博雅课程。
    ///
    /// # Errors
    ///
    /// 会话所有权失效、博雅路线不可用或退选失败时返回带路线信息的错误。
    pub async fn bykc_deselect_course(&mut self, course_id: i64) -> RoutedResult<BykcActionResult> {
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Bykc))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::bykc::deselect_course(&mut self.direct_runtime, course_id).await
            }
            ConnectionMode::WebVpn => {
                crate::features::bykc::deselect_course(&mut self.webvpn_runtime, course_id).await
            }
        };
        self.finish_routed(resolution, result)
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
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::bykc::sign_course(&mut self.direct_runtime, request.clone()).await
            }
            ConnectionMode::WebVpn => {
                crate::features::bykc::sign_course(&mut self.webvpn_runtime, request).await
            }
        };
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
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::signin::perform_signin(&mut self.direct_runtime, course_id).await
            }
            ConnectionMode::WebVpn => {
                crate::features::signin::perform_signin(&mut self.webvpn_runtime, course_id).await
            }
        };
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
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::ygdk::submit_clockin(&mut self.direct_runtime, request.clone())
                    .await
            }
            ConnectionMode::WebVpn => {
                crate::features::ygdk::submit_clockin(&mut self.webvpn_runtime, request).await
            }
        };
        self.finish_routed(resolution, result)
    }
}
