//! 校园卡充值的读取准备与写入口。
//!
//! 充值下单是一次真实的、不可重放的写操作；准备信息与下单共用同一路线解析。

use crate::domain::{CampusRechargeOrder, CampusRechargePreflight, ConnectionMode};

use super::super::client::{PreparedCampusRecharge, UbaaClient};
use super::super::routing::invalid_input;
use super::super::types::{Operation, Routed, RoutedResult};

impl UbaaClient {
    /// 读取充值前的卡序号与余额；不含 openid。
    ///
    /// # Errors
    ///
    /// 路线、会话、卡站点业务登录或解析错误时返回带路线信息的错误。
    pub async fn campus_recharge_preflight(&mut self) -> RoutedResult<CampusRechargePreflight> {
        let route = self.resolve_operation(Operation::CampusRecharge)?;
        let (route, result) = crate::facade::routing::read_with_fallback!(
            self,
            route,
            crate::features::campus::recharge_preflight(self.runtime_for(route.mode)).await
        );
        self.finish_routed(route, result)
    }

    /// 读取并记住固定到本次实际路线与会话的充值确认上下文。
    /// 同卡未消费的确认上下文变化时丢弃旧绑定，返回无确认数据的路线结果，要求重新准备。
    ///
    /// # Errors
    ///
    /// 读取失败保持原错误。
    pub async fn campus_recharge_preflight_for_confirmation(
        &mut self,
    ) -> RoutedResult<Option<CampusRechargePreflight>> {
        let Routed { data, resolution } = self.campus_recharge_preflight().await?;
        let route = resolution.mode;
        let runtime = self.runtime_for(route);
        let session_revision = runtime.session_revision();
        let authentication_generation = runtime.authentication_generation();

        if let Some(previous) = &self.prepared_campus_recharge
            && previous.idserial == data.idserial
        {
            if previous.route != route
                || previous.session_revision != session_revision
                || previous.authentication_generation != authentication_generation
            {
                // 接口只接收卡号，不能区分同卡的两次确认。不要替换未消费的绑定。
                self.prepared_campus_recharge = None;
                return Ok(Routed {
                    data: None,
                    resolution,
                });
            }
        } else {
            self.prepared_campus_recharge = Some(PreparedCampusRecharge {
                idserial: data.idserial.clone(),
                route,
                session_revision,
                authentication_generation,
            });
        }
        Ok(Routed {
            data: Some(data),
            resolution,
        })
    }

    /// 消费卡号匹配的确认上下文；调用方必须在同一个客户端锁内继续调用
    /// [`Self::campus_recharge_order_if_route_matches`]，由写入边界重新验证权威路线与会话。
    pub fn take_campus_recharge_preflight_route(
        &mut self,
        idserial: &str,
    ) -> Option<ConnectionMode> {
        if self.prepared_campus_recharge.as_ref()?.idserial != idserial {
            return None;
        }
        let prepared = self.prepared_campus_recharge.take()?;
        let runtime = self.runtime_for(prepared.route);
        (runtime.session_revision() == prepared.session_revision
            && runtime.authentication_generation() == prepared.authentication_generation)
            .then_some(prepared.route)
    }

    /// 仅创建充值订单并返回已验证的原商户收银台地址，不选择支付渠道。
    ///
    /// 下单请求至多发送一次；结果未知时不自动重试。
    ///
    /// # Errors
    ///
    /// 路线不可用、金额非法、会话所有权冲突或下单失败时返回错误。
    pub async fn campus_recharge_order(
        &mut self,
        idserial: &str,
        amount_fen: &str,
    ) -> RoutedResult<CampusRechargeOrder> {
        let fen = parse_fen(amount_fen).map_err(|error| super::super::types::RoutedError {
            error,
            resolution: None,
        })?;
        let resolution = self.resolve_write_operation_route(Operation::CampusRecharge, None)?;
        let result = {
            let runtime = self.runtime_for(resolution.mode);
            runtime.begin_non_idempotent_operation();
            crate::features::campus::recharge_order(runtime, idserial, &fen).await
        };
        self.finish_routed_write(resolution, result)
    }

    /// 仅在本次权威解析仍匹配确认路线时下单。
    /// 与 [`Self::campus_recharge_order`] 一样，不选择支付渠道。
    ///
    /// # Errors
    ///
    /// 路线已变化时在任何业务 HTTP 之前拒绝。
    pub async fn campus_recharge_order_if_route_matches(
        &mut self,
        idserial: &str,
        amount_fen: &str,
        expected_route: ConnectionMode,
    ) -> RoutedResult<CampusRechargeOrder> {
        let fen = parse_fen(amount_fen).map_err(|error| super::super::types::RoutedError {
            error,
            resolution: None,
        })?;
        let resolution =
            self.resolve_write_operation_route(Operation::CampusRecharge, Some(expected_route))?;
        let result = {
            let runtime = self.runtime_for(resolution.mode);
            runtime.begin_non_idempotent_operation();
            crate::features::campus::recharge_order(runtime, idserial, &fen).await
        };
        self.finish_routed_write(resolution, result)
    }
}

/// 金额以分为单位，只接受 1–100000 的十进制整数，与卡站点 1000 元上限一致。
fn parse_fen(value: &str) -> crate::error::Result<String> {
    let invalid = || invalid_input("充值金额必须为 1–100000 分之间的整数");
    if value.is_empty() || value.len() > 6 || !value.bytes().all(|b| b.is_ascii_digit()) {
        return Err(invalid());
    }
    let fen: u32 = value.parse().map_err(|_| invalid())?;
    if !(1..=100_000).contains(&fen) {
        return Err(invalid());
    }
    Ok(fen.to_string())
}

#[cfg(test)]
mod tests {
    use super::parse_fen;

    #[test]
    fn 金额只接受有效分值() {
        assert_eq!(parse_fen("1").expect("一分"), "1");
        assert_eq!(parse_fen("100").expect("一元"), "100");
        assert_eq!(parse_fen("100000").expect("上限"), "100000");
    }

    #[test]
    fn 越界与非数字被拒绝() {
        for bad in ["", "0", "0.5", "100001", "abc", "-1", " 1", "1.0"] {
            assert!(parse_fen(bad).is_err(), "{bad:?} 应被拒绝");
        }
    }
}
