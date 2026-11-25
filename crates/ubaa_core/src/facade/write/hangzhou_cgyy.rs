//! 杭州校区空间预约（hzsm）读取时段、验证码与写入入口。
//!
//! 路线语义同 [`UbaaClient::hangzhou_cgyy_sites`]：沿用研讨室路线策略，杭州主机只验证过直连，
//! 非直连由 feature 直接返回 `unsupported` 且不发请求。

use crate::connection::RouteResolution;
use crate::domain::{
    CgyyDayInfo, ConnectionMode, HangzhouCgyyCancelPreflight, HangzhouCgyyCancelRequest,
    HangzhouCgyyCancelResult, HangzhouCgyyCaptchaChallenge, HangzhouCgyyReservationReceipt,
    HangzhouCgyyReservationRequest, ReadonlyFeature,
};
use crate::error::UbaaError;

use super::super::client::UbaaClient;
use super::super::routing::invalid_input;
use super::super::types::{Operation, RoutedResult};

impl UbaaClient {
    /// 查询杭州空间预约某场地某日的空间与时段。
    ///
    /// # Errors
    ///
    /// 路线解析、参数无效、非直连路线、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn hangzhou_cgyy_day_info(
        &mut self,
        venue_site_id: i32,
        date: &str,
    ) -> RoutedResult<CgyyDayInfo> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Cgyy))?;
        self.log_cgyy_route(resolution, "hangzhou.day.info");
        let runtime = self.runtime_for(resolution.mode);
        let result = if venue_site_id <= 0 || date.trim().is_empty() {
            Err(invalid_input("场地和日期不能为空"))
        } else {
            crate::features::cgyy::get_hangzhou_day_info(runtime, venue_site_id, date.trim())
                .await
                .map_err(UbaaError::for_facade)
        };
        self.finish_routed(resolution, result)
    }

    /// 取一张杭州滑块验证码交给用户拖动。只读，不产生预约。
    ///
    /// # Errors
    ///
    /// 路线解析、非直连路线、会话校验或上游请求失败时返回错误。
    pub async fn hangzhou_cgyy_captcha(&mut self) -> RoutedResult<HangzhouCgyyCaptchaChallenge> {
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Cgyy))?;
        self.log_cgyy_route(resolution, "hangzhou.captcha");
        let result = crate::features::cgyy::hangzhou_captcha(self.runtime_for(resolution.mode))
            .await
            .map_err(UbaaError::for_facade);
        self.finish_routed(resolution, result)
    }

    /// 复核资格、校验用户滑块、提交一次并完成 0 元确认。
    ///
    /// # Errors
    ///
    /// 资格、验证码、付费场地或上游拒绝时返回错误；请求已发出但结果不确定时返回
    /// `outcome_unknown`，不自动重试。
    pub async fn hangzhou_cgyy_submit_reservation(
        &mut self,
        request: HangzhouCgyyReservationRequest,
    ) -> RoutedResult<HangzhouCgyyReservationReceipt> {
        let resolution = self.resolve_write_route(ReadonlyFeature::Cgyy, None)?;
        self.hangzhou_cgyy_submit_reservation_resolved(request, resolution)
            .await
    }

    /// 仅当本次权威解析仍匹配确认路线时提交；路线冲突在任何业务 HTTP 之前返回。
    ///
    /// # Errors
    ///
    /// 同 [`Self::hangzhou_cgyy_submit_reservation`]，另含路线已变化。
    pub async fn hangzhou_cgyy_submit_reservation_if_route_matches(
        &mut self,
        request: HangzhouCgyyReservationRequest,
        expected_route: ConnectionMode,
    ) -> RoutedResult<HangzhouCgyyReservationReceipt> {
        let resolution = self.resolve_write_route(ReadonlyFeature::Cgyy, Some(expected_route))?;
        self.hangzhou_cgyy_submit_reservation_resolved(request, resolution)
            .await
    }

    async fn hangzhou_cgyy_submit_reservation_resolved(
        &mut self,
        request: HangzhouCgyyReservationRequest,
        resolution: RouteResolution,
    ) -> RoutedResult<HangzhouCgyyReservationReceipt> {
        self.log_cgyy_route(resolution, "hangzhou.reservation.submit");
        let result = {
            let runtime = self.runtime_for(resolution.mode);
            runtime.begin_non_idempotent_operation();
            crate::features::cgyy::hangzhou_submit_reservation(runtime, request).await
        };
        self.finish_routed_write(resolution, result)
    }

    /// 读取取消提醒并校验订单号与原因，不发送取消。
    ///
    /// # Errors
    ///
    /// 路线解析、参数无效、非直连路线、会话校验或上游请求失败时返回错误。
    pub async fn preflight_hangzhou_cgyy_cancel(
        &mut self,
        request: &HangzhouCgyyCancelRequest,
    ) -> RoutedResult<HangzhouCgyyCancelPreflight> {
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Cgyy))?;
        self.log_cgyy_route(resolution, "hangzhou.orders.cancel.preflight");
        let result = crate::features::cgyy::hangzhou_preflight_cancel(
            self.runtime_for(resolution.mode),
            request,
        )
        .await;
        self.finish_routed(resolution, result)
    }

    /// 发送一次杭州订单取消。
    ///
    /// # Errors
    ///
    /// 参数无效、上游拒绝或结果未知时返回错误，不自动重试。
    pub async fn hangzhou_cgyy_cancel_order(
        &mut self,
        request: HangzhouCgyyCancelRequest,
    ) -> RoutedResult<HangzhouCgyyCancelResult> {
        let resolution = self.resolve_write_route(ReadonlyFeature::Cgyy, None)?;
        self.hangzhou_cgyy_cancel_order_resolved(request, resolution)
            .await
    }

    /// 仅当本次权威解析仍匹配确认路线时取消；路线冲突在任何业务 HTTP 之前返回。
    ///
    /// # Errors
    ///
    /// 同 [`Self::hangzhou_cgyy_cancel_order`]，另含路线已变化。
    pub async fn hangzhou_cgyy_cancel_order_if_route_matches(
        &mut self,
        request: HangzhouCgyyCancelRequest,
        expected_route: ConnectionMode,
    ) -> RoutedResult<HangzhouCgyyCancelResult> {
        let resolution = self.resolve_write_route(ReadonlyFeature::Cgyy, Some(expected_route))?;
        self.hangzhou_cgyy_cancel_order_resolved(request, resolution)
            .await
    }

    async fn hangzhou_cgyy_cancel_order_resolved(
        &mut self,
        request: HangzhouCgyyCancelRequest,
        resolution: RouteResolution,
    ) -> RoutedResult<HangzhouCgyyCancelResult> {
        self.log_cgyy_route(resolution, "hangzhou.orders.cancel");
        let result = {
            let runtime = self.runtime_for(resolution.mode);
            runtime.begin_non_idempotent_operation();
            crate::features::cgyy::hangzhou_cancel_order(runtime, request).await
        };
        self.finish_routed_write(resolution, result)
    }
}
