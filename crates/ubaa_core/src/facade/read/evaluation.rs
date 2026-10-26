//! 评教安全课程投影与调用方固定路线读取入口。

use crate::domain::{ConnectionMode, EvaluationCoursesResponse, ReadonlyFeature};

use super::super::client::UbaaClient;
use super::super::types::{CallerPinned, Operation, RoutedResult};

impl UbaaClient {
    /// 通过当前评教路线策略查询安全课程投影。
    ///
    /// # Errors
    ///
    /// 路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn evaluation_all(&mut self) -> RoutedResult<EvaluationCoursesResponse> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Evaluation))?;
        let result = crate::features::evaluation::get_all(self.runtime_for(resolution.mode)).await;
        self.finish_routed(resolution, result)
    }

    /// 在调用方固定的已认证路线查询安全课程投影，不执行策略解析或 Auto 回退。
    ///
    /// # Errors
    ///
    /// 会话所有权失效、指定路线未认证或上游读取失败时返回错误。
    pub async fn evaluation_all_on_route(
        &mut self,
        route: ConnectionMode,
    ) -> crate::error::Result<CallerPinned<EvaluationCoursesResponse>> {
        self.guard_caller_pinned_route(route)?;
        let result = crate::features::evaluation::get_all(self.runtime_for(route)).await;
        self.finish_caller_pinned(route, result)
    }
}
