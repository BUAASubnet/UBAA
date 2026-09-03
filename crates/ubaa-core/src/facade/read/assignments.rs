//! 签到、SPOC 与希冀作业只读入口。

use crate::domain::{
    JudgeAssignmentDetail, JudgeAssignmentKey, JudgeAssignmentSummary, JudgeAssignmentsDiagnostics,
    ReadonlyFeature, SigninClass, SpocAssignmentDetail, SpocAssignments,
    SpocAssignmentsDiagnostics,
};

use super::super::client::UbaaClient;
use super::super::types::{Operation, RoutedResult};

impl UbaaClient {
    /// 通过签到功能路由查询今日课堂签到状态。
    ///
    /// # Errors
    ///
    /// 路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn signin_today(&mut self) -> RoutedResult<Vec<SigninClass>> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Signin))?;
        let result = crate::features::signin::get_today(self.runtime_for(resolution.mode)).await;
        self.finish_routed(resolution, result)
    }

    /// 通过 SPOC 路线策略读取当前作业列表。
    ///
    /// # Errors
    ///
    /// 路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn spoc_assignments(&mut self) -> RoutedResult<SpocAssignments> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Spoc))?;
        let result =
            crate::features::spoc::get_assignments(self.runtime_for(resolution.mode)).await;
        self.finish_routed(resolution, result)
    }

    /// 读取当前 SPOC 列表，并返回安全的全局页面完成证据。
    ///
    /// # Errors
    ///
    /// 路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn spoc_assignments_diagnostics(
        &mut self,
    ) -> RoutedResult<SpocAssignmentsDiagnostics> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Spoc))?;
        let result =
            crate::features::spoc::get_assignments_diagnostics(self.runtime_for(resolution.mode))
                .await;
        self.finish_routed(resolution, result)
    }

    /// 通过 SPOC 路线策略读取一项作业详情。
    ///
    /// # Errors
    ///
    /// 路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn spoc_assignment(
        &mut self,
        assignment_id: &str,
    ) -> RoutedResult<SpocAssignmentDetail> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Spoc))?;
        let result = crate::features::spoc::get_assignment_detail(
            self.runtime_for(resolution.mode),
            assignment_id,
        )
        .await;
        self.finish_routed(resolution, result)
    }

    /// 通过希冀路线策略读取作业。
    ///
    /// # Errors
    ///
    /// 路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn judge_assignments(
        &mut self,
        include_expired: bool,
    ) -> RoutedResult<Vec<JudgeAssignmentSummary>> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Judge))?;
        let result = crate::features::judge::get_assignments(
            self.runtime_for(resolution.mode),
            include_expired,
        )
        .await;
        self.finish_routed(resolution, result)
    }

    /// 通过希冀路线策略读取作业，并返回安全解析计数。
    ///
    /// # Errors
    ///
    /// 路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn judge_assignments_diagnostics(
        &mut self,
        include_expired: bool,
    ) -> RoutedResult<JudgeAssignmentsDiagnostics> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Judge))?;
        let result = crate::features::judge::get_assignments_diagnostics(
            self.runtime_for(resolution.mode),
            include_expired,
        )
        .await;
        self.finish_routed(resolution, result)
    }

    /// 通过希冀路线策略读取一项作业详情。
    ///
    /// # Errors
    ///
    /// 路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn judge_assignment(
        &mut self,
        course_id: &str,
        assignment_id: &str,
    ) -> RoutedResult<JudgeAssignmentDetail> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Judge))?;
        let result = crate::features::judge::get_assignment_detail(
            self.runtime_for(resolution.mode),
            course_id,
            assignment_id,
        )
        .await;
        self.finish_routed(resolution, result)
    }

    /// 通过一次希冀路线策略决策读取多项作业详情。
    ///
    /// # Errors
    ///
    /// 路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn judge_assignment_details(
        &mut self,
        keys: &[JudgeAssignmentKey],
    ) -> RoutedResult<Vec<JudgeAssignmentDetail>> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Judge))?;
        let result =
            crate::features::judge::get_assignment_details(self.runtime_for(resolution.mode), keys)
                .await;
        self.finish_routed(resolution, result)
    }
}
