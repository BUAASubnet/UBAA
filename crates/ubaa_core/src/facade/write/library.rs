//! 图书馆当前借阅的续借写入口。

use crate::connection::RouteResolution;
use crate::domain::{
    ConnectionMode, LibraryLoanRenewRequest, LibraryLoanRenewResult, ReadonlyFeature,
};

use super::super::client::UbaaClient;
use super::super::types::RoutedResult;

impl UbaaClient {
    /// 续借一条当前借阅。
    ///
    /// # Errors
    /// 路线、会话、目标或学校写结果失败时返回带路线信息的安全错误。
    pub async fn library_loan_renew(
        &mut self,
        request: LibraryLoanRenewRequest,
    ) -> RoutedResult<LibraryLoanRenewResult> {
        let resolution = self.resolve_write_route(ReadonlyFeature::Library, None)?;
        self.library_loan_renew_resolved(request, resolution).await
    }

    /// 仅在本次权威路由解析仍匹配确认路线时执行单次续借。
    ///
    /// # Errors
    /// 路线、会话、目标或学校写结果失败时返回带路线信息的安全错误。
    pub async fn library_loan_renew_if_route_matches(
        &mut self,
        request: LibraryLoanRenewRequest,
        expected_route: ConnectionMode,
    ) -> RoutedResult<LibraryLoanRenewResult> {
        let resolution =
            self.resolve_write_route(ReadonlyFeature::Library, Some(expected_route))?;
        self.library_loan_renew_resolved(request, resolution).await
    }

    async fn library_loan_renew_resolved(
        &mut self,
        request: LibraryLoanRenewRequest,
        resolution: RouteResolution,
    ) -> RoutedResult<LibraryLoanRenewResult> {
        let result = {
            let runtime = self.runtime_for(resolution.mode);
            runtime.begin_non_idempotent_operation();
            crate::features::campus::renew(runtime, request).await
        };
        self.finish_routed_write(resolution, result)
    }
}
