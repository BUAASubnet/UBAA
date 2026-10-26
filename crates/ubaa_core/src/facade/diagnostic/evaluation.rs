//! 单路线评教 typed 诊断入口。

use crate::domain::{
    EvaluationBatchResult, EvaluationCoursesResponse, EvaluationSubmitCoursesRequest,
    EvaluationSubmitPreflight, FeatureResult,
};
use crate::error::Result;

use super::RouteClient;

impl RouteClient {
    /// 查询全部评教课程的安全投影。
    ///
    /// # Errors
    ///
    /// 会话校验、网络请求或上游响应处理失败时返回错误。
    pub async fn evaluation_all(&mut self) -> Result<FeatureResult<EvaluationCoursesResponse>> {
        self.guard_session_ownership()?;
        let result = crate::features::evaluation::get_all(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// fresh 读取完整 Core authority 并复核全部 typed 目标，不发送写请求。
    ///
    /// # Errors
    ///
    /// 输入无效、会话所有权失效或任一目标当前不可唯一提交时返回错误。
    pub async fn preflight_evaluation_submit_courses(
        &mut self,
        request: &EvaluationSubmitCoursesRequest,
    ) -> Result<FeatureResult<EvaluationSubmitPreflight>> {
        crate::features::evaluation::validate_submit_courses_request(request)?;
        self.guard_latest_session_ownership()?;
        let result =
            crate::features::evaluation::preflight_submit_courses(&mut self.runtime, request).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// fresh 重建完整 Core authority 后提交 typed 目标列表。
    ///
    /// # Errors
    ///
    /// 输入无效、会话所有权失效或 fresh authority 链失败时返回错误。
    pub async fn evaluation_submit_courses(
        &mut self,
        request: EvaluationSubmitCoursesRequest,
    ) -> Result<FeatureResult<EvaluationBatchResult>> {
        crate::features::evaluation::validate_submit_courses_request(&request)?;
        self.guard_latest_session_ownership()?;
        self.runtime.begin_non_idempotent_operation();
        let result = crate::features::evaluation::submit_courses(&mut self.runtime, request).await;
        let data = self.finish_write_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }
}
