//! 评教 typed preflight 与路线原子提交入口。

use crate::connection::RouteResolution;
use crate::domain::{
    ConnectionMode, EvaluationBatchResult, EvaluationSubmitCoursesRequest,
    EvaluationSubmitPreflight, ReadonlyFeature,
};

use super::super::client::UbaaClient;
use super::super::routing::{invalid_input, routed_error};
use super::super::types::{Operation, RoutedError, RoutedResult};

impl UbaaClient {
    /// fresh 读取完整 Core authority 并复核全部 typed 目标，不发送写请求。
    ///
    /// # Errors
    ///
    /// 输入无效、会话所有权失效、路线不可用，或任一目标当前不唯一且不可提交时返回错误。
    pub async fn preflight_evaluation_submit_courses(
        &mut self,
        request: &EvaluationSubmitCoursesRequest,
    ) -> RoutedResult<EvaluationSubmitPreflight> {
        validate_request(request)?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Evaluation))?;
        let result = crate::features::evaluation::preflight_submit_courses(
            self.runtime_for(resolution.mode),
            request,
        )
        .await;
        self.finish_routed(resolution, result)
    }

    /// 在本次唯一解析出的路线重新 fresh 复核 authority，再按请求顺序提交。
    ///
    /// # Errors
    ///
    /// 输入无效、会话所有权失效、路线不可用或 fresh authority 链失败时返回错误。
    pub async fn evaluation_submit_courses(
        &mut self,
        request: EvaluationSubmitCoursesRequest,
    ) -> RoutedResult<EvaluationBatchResult> {
        validate_request(&request)?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Evaluation))?;
        self.evaluation_submit_courses_resolved(request, resolution)
            .await
    }

    /// 仅当唯一权威路线解析与调用方预期一致时执行 fresh commit。
    ///
    /// 路线不一致会在 authority 读取和最终写请求之前拒绝。
    ///
    /// # Errors
    ///
    /// 输入无效、解析路线变化、会话所有权失效、路线不可用或 fresh authority 链失败时返回错误。
    pub async fn evaluation_submit_courses_if_route_matches(
        &mut self,
        request: EvaluationSubmitCoursesRequest,
        expected_route: ConnectionMode,
    ) -> RoutedResult<EvaluationBatchResult> {
        validate_request(&request)?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Evaluation))?;
        if resolution.mode != expected_route {
            return Err(routed_error(
                invalid_input("评教提交路线已变化，请重新确认"),
                resolution,
            ));
        }
        self.evaluation_submit_courses_resolved(request, resolution)
            .await
    }

    async fn evaluation_submit_courses_resolved(
        &mut self,
        request: EvaluationSubmitCoursesRequest,
        resolution: RouteResolution,
    ) -> RoutedResult<EvaluationBatchResult> {
        let result = {
            let runtime = self.runtime_for(resolution.mode);
            runtime.begin_non_idempotent_operation();
            crate::features::evaluation::submit_courses(runtime, request).await
        };
        self.finish_routed_write(resolution, result)
    }
}

fn validate_request(
    request: &EvaluationSubmitCoursesRequest,
) -> std::result::Result<(), RoutedError> {
    crate::features::evaluation::validate_submit_courses_request(request).map_err(|error| {
        RoutedError {
            error,
            resolution: None,
        }
    })
}
