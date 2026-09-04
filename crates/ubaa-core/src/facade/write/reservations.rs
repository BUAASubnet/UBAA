//! 场馆与图书馆预约写入口。

use crate::connection::RouteResolution;
use crate::domain::{
    CgyyCancelOrderPreflight, CgyyCancelOrderRequest, CgyyCancelOrderResult,
    CgyyReservationPreflight, CgyyReservationResult, CgyyReservationSubmitRequest, ConnectionMode,
    LibBookCancelPreflight, LibBookCancelRequest, LibBookCancelResult, LibBookReservePreflight,
    LibBookReserveRequest, LibBookReserveResult, ReadonlyFeature,
};

use super::super::client::UbaaClient;
use super::super::routing::{invalid_input, routed_error};
use super::super::types::{Operation, RoutedError, RoutedResult};

impl UbaaClient {
    /// 只读复核场馆预约订单的 typed 取消资格。
    ///
    /// # Errors
    ///
    /// 会话所有权失效、订单标识无效、场馆路线不可用或资格不足时返回带路线信息的错误。
    pub async fn preflight_cgyy_cancel(
        &mut self,
        request: &CgyyCancelOrderRequest,
    ) -> RoutedResult<CgyyCancelOrderPreflight> {
        validate_cgyy_cancel_order_id(request.order_id)?;
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Cgyy))?;
        self.log_cgyy_route(resolution, "orders.cancel.preflight");
        let result = crate::features::cgyy::preflight_cancel_order(
            self.runtime_for(resolution.mode),
            request,
        )
        .await;
        self.finish_routed(resolution, result)
    }

    /// 取消场馆预约订单。
    ///
    /// # Errors
    ///
    /// 会话所有权失效、订单标识无效、场馆路线不可用或取消失败时返回带路线信息的错误。
    pub async fn cgyy_cancel_order(
        &mut self,
        request: CgyyCancelOrderRequest,
    ) -> RoutedResult<CgyyCancelOrderResult> {
        validate_cgyy_cancel_order_id(request.order_id)?;
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Cgyy))?;
        self.cgyy_cancel_order_resolved(request, resolution).await
    }

    /// 仅当本次唯一权威路线解析仍与调用方预期一致时取消场馆预约订单。
    ///
    /// 路线不一致会在读取订单详情或发送取消请求之前拒绝，并在错误中携带本次实际解析结果。
    ///
    /// # Errors
    ///
    /// 会话所有权失效、解析路线与预期不一致、场馆路线不可用或取消失败时返回带路线信息的错误。
    pub async fn cgyy_cancel_order_if_route_matches(
        &mut self,
        request: CgyyCancelOrderRequest,
        expected_route: ConnectionMode,
    ) -> RoutedResult<CgyyCancelOrderResult> {
        validate_cgyy_cancel_order_id(request.order_id)?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Cgyy))?;
        if resolution.mode != expected_route {
            return Err(routed_error(
                invalid_input("场馆订单取消路线已变化，请重新确认"),
                resolution,
            ));
        }
        self.cgyy_cancel_order_resolved(request, resolution).await
    }

    async fn cgyy_cancel_order_resolved(
        &mut self,
        request: CgyyCancelOrderRequest,
        resolution: RouteResolution,
    ) -> RoutedResult<CgyyCancelOrderResult> {
        self.log_cgyy_route(resolution, "orders.cancel");
        let result = {
            let runtime = self.runtime_for(resolution.mode);
            runtime.begin_non_idempotent_operation();
            crate::features::cgyy::cancel_order(runtime, request).await
        };
        self.finish_routed_write(resolution, result)
    }

    /// 只读复核场馆预约的当前日期和唯一 typed 槽位目标。
    ///
    /// # Errors
    ///
    /// 会话所有权失效、目标不唯一、资格不足或上游结构变化时返回带路线信息的错误。
    pub async fn preflight_cgyy_reservation(
        &mut self,
        request: &CgyyReservationSubmitRequest,
    ) -> RoutedResult<CgyyReservationPreflight> {
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Cgyy))?;
        self.log_cgyy_route(resolution, "reservation.preflight");
        let result = crate::features::cgyy::preflight_reservation(
            self.runtime_for(resolution.mode),
            request,
        )
        .await;
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
        let result = {
            let runtime = self.runtime_for(resolution.mode);
            runtime.begin_non_idempotent_operation();
            crate::features::cgyy::submit_reservation(runtime, request).await
        };
        self.finish_routed_write(resolution, result)
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

    /// 只读复核 action 所属分页内唯一 active 的图书馆预约。
    ///
    /// # Errors
    ///
    /// 会话所有权失效、图书馆路线不可用、目标不唯一或资格不足时返回带路线信息的错误。
    pub async fn preflight_libbook_cancel(
        &mut self,
        request: &LibBookCancelRequest,
    ) -> RoutedResult<LibBookCancelPreflight> {
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::LibBook))?;
        let result =
            crate::features::libbook::preflight_cancel(self.runtime_for(resolution.mode), request)
                .await;
        self.finish_routed(resolution, result)
    }

    /// 取消一笔图书馆座位预约。
    ///
    /// # Errors
    ///
    /// 会话所有权失效、图书馆路线不可用或取消失败时返回带路线信息的错误。
    pub async fn libbook_cancel_booking(
        &mut self,
        request: LibBookCancelRequest,
    ) -> RoutedResult<LibBookCancelResult> {
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::LibBook))?;
        let result = {
            let runtime = self.runtime_for(resolution.mode);
            runtime.begin_non_idempotent_operation();
            crate::features::libbook::cancel_booking(runtime, request).await
        };
        self.finish_routed_write(resolution, result)
    }
}

fn validate_cgyy_cancel_order_id(order_id: i32) -> std::result::Result<(), RoutedError> {
    if order_id <= 0 {
        return Err(RoutedError {
            error: invalid_input("订单标识必须为正数"),
            resolution: None,
        });
    }
    Ok(())
}
