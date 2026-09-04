//! 场馆与图书馆预约写入口。

use crate::domain::{
    CgyyActionResult, CgyyReservationResult, CgyyReservationSubmitRequest, LibBookCancelResult,
    LibBookReservePreflight, LibBookReserveRequest, LibBookReserveResult, ReadonlyFeature,
};

use super::super::client::UbaaClient;
use super::super::routing::{invalid_input, routed_error};
use super::super::types::{Operation, RoutedResult};

impl UbaaClient {
    /// 取消场馆预约订单。
    ///
    /// # Errors
    ///
    /// 会话所有权失效、订单标识无效、场馆路线不可用或取消失败时返回带路线信息的错误。
    pub async fn cgyy_cancel_order(&mut self, id: i32) -> RoutedResult<CgyyActionResult> {
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Cgyy))?;
        self.log_cgyy_route(resolution, "orders.cancel");
        if id <= 0 {
            return Err(routed_error(
                invalid_input("订单标识必须为正数"),
                resolution,
            ));
        }
        let result =
            crate::features::cgyy::cancel_order(self.runtime_for(resolution.mode), id).await;
        self.finish_routed(resolution, result)
    }

    /// 提交场馆预约；验证码材料可由调用方提供或由 Core 自动获取并校验。
    ///
    /// # Errors
    ///
    /// 会话所有权失效、场馆路线不可用或预约提交失败时返回带路线信息的错误。
    pub async fn cgyy_submit_reservation(
        &mut self,
        request: CgyyReservationSubmitRequest,
    ) -> RoutedResult<CgyyReservationResult> {
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Cgyy))?;
        self.log_cgyy_route(resolution, "reservation.submit");
        let result =
            crate::features::cgyy::submit_reservation(self.runtime_for(resolution.mode), request)
                .await;
        self.finish_routed(resolution, result)
    }

    /// 只读复核图书馆预约的当前日期、时段和唯一座位资格。
    ///
    /// # Errors
    ///
    /// 会话所有权失效、图书馆路线不可用、目标不唯一或资格不足时返回带路线信息的错误。
    pub async fn preflight_libbook_reserve(
        &mut self,
        request: &LibBookReserveRequest,
    ) -> RoutedResult<LibBookReservePreflight> {
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::LibBook))?;
        let result =
            crate::features::libbook::preflight_reserve(self.runtime_for(resolution.mode), request)
                .await;
        self.finish_routed(resolution, result)
    }

    /// 提交一笔图书馆座位预约。
    ///
    /// # Errors
    ///
    /// 会话所有权失效、图书馆路线不可用或预约失败时返回带路线信息的错误。
    pub async fn libbook_reserve(
        &mut self,
        request: LibBookReserveRequest,
    ) -> RoutedResult<LibBookReserveResult> {
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::LibBook))?;
        let result = {
            let runtime = self.runtime_for(resolution.mode);
            runtime.begin_non_idempotent_operation();
            crate::features::libbook::reserve(runtime, request).await
        };
        self.finish_routed_write(resolution, result)
    }

    /// 取消一笔图书馆座位预约。
    ///
    /// # Errors
    ///
    /// 会话所有权失效、图书馆路线不可用或取消失败时返回带路线信息的错误。
    pub async fn libbook_cancel_booking(&mut self, id: &str) -> RoutedResult<LibBookCancelResult> {
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::LibBook))?;
        let result =
            crate::features::libbook::cancel_booking(self.runtime_for(resolution.mode), id).await;
        self.finish_routed(resolution, result)
    }
}
