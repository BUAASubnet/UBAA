//! 单路线诊断客户端的场馆查询与预约入口。

use crate::domain::{
    CgyyCancelOrderPreflight, CgyyCancelOrderRequest, CgyyCancelOrderResult, CgyyDayInfo,
    CgyyLockCode, CgyyOrder, CgyyOrdersPage, CgyyPurposeType, CgyyPurposeTypes,
    CgyyReservationPreflight, CgyyReservationResult, CgyyReservationSubmitRequest, CgyyVenueSite,
    FeatureResult,
};
use crate::error::Result;

use super::{RouteClient, invalid_input};

impl RouteClient {
    /// 查询场馆站点。
    ///
    /// # Errors
    ///
    /// 会话校验或清理、网络请求或上游响应处理失败时返回错误。
    pub async fn cgyy_sites(&mut self) -> Result<FeatureResult<Vec<CgyyVenueSite>>> {
        self.guard_session_ownership()?;
        let result = crate::features::cgyy::get_sites(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 查询场馆用途类型；上游不可用时由 feature 保留冻结静态回退。
    ///
    /// # Errors
    ///
    /// 会话校验或清理、网络请求或上游响应处理失败时返回错误。
    pub async fn cgyy_purpose_types(&mut self) -> Result<FeatureResult<Vec<CgyyPurposeType>>> {
        self.guard_session_ownership()?;
        let result = crate::features::cgyy::get_purpose_types(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 查询场馆用途并保留上游或静态回退来源诊断。
    ///
    /// # Errors
    ///
    /// 会话校验或清理、网络请求或上游响应处理失败时返回错误。
    pub async fn cgyy_purpose_types_diagnostics(
        &mut self,
    ) -> Result<FeatureResult<CgyyPurposeTypes>> {
        self.guard_session_ownership()?;
        let result = crate::features::cgyy::get_purpose_types_with_source(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(
            &self.runtime,
            CgyyPurposeTypes {
                items: data.0,
                source: data.1,
            },
        ))
    }

    /// 查询场馆日期可用性。
    ///
    /// # Errors
    ///
    /// 参数无效、会话校验失败、网络请求失败或上游响应处理失败时返回错误。
    pub async fn cgyy_day_info(
        &mut self,
        site_id: i32,
        date: &str,
    ) -> Result<FeatureResult<CgyyDayInfo>> {
        self.guard_session_ownership()?;
        if site_id <= 0 || date.trim().is_empty() {
            return Err(invalid_input("场馆站点和日期不能为空"));
        }
        let result = crate::features::cgyy::get_day_info(&mut self.runtime, site_id, date).await;
        let day_info = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, day_info))
    }

    /// 查询场馆订单分页。
    ///
    /// # Errors
    ///
    /// 参数无效、会话校验失败、网络请求失败或上游响应处理失败时返回错误。
    pub async fn cgyy_orders(
        &mut self,
        page: i32,
        size: i32,
    ) -> Result<FeatureResult<CgyyOrdersPage>> {
        self.guard_session_ownership()?;
        if page < 0 || size <= 0 {
            return Err(invalid_input("分页参数无效"));
        }
        let result = crate::features::cgyy::get_orders(&mut self.runtime, page, size).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 查询场馆订单详情。
    ///
    /// # Errors
    ///
    /// 参数无效、会话校验失败、网络请求失败或上游响应处理失败时返回错误。
    pub async fn cgyy_order_detail(&mut self, id: i32) -> Result<FeatureResult<CgyyOrder>> {
        self.guard_session_ownership()?;
        if id <= 0 {
            return Err(invalid_input("订单标识必须为正数"));
        }
        let result = crate::features::cgyy::get_order_detail(&mut self.runtime, id).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 查询场馆预约锁码。
    ///
    /// # Errors
    ///
    /// 会话校验或清理、网络请求或上游响应处理失败时返回错误。
    pub async fn cgyy_lock_code(&mut self) -> Result<FeatureResult<CgyyLockCode>> {
        self.guard_session_ownership()?;
        let result = crate::features::cgyy::get_lock_code(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 只读复核场馆预约订单的 typed 取消资格。
    ///
    /// # Errors
    ///
    /// 参数无效、会话所有权校验、网络读取或上游响应处理失败时返回错误。
    pub async fn preflight_cgyy_cancel(
        &mut self,
        request: &CgyyCancelOrderRequest,
    ) -> Result<FeatureResult<CgyyCancelOrderPreflight>> {
        self.guard_latest_session_ownership()?;
        let result =
            crate::features::cgyy::preflight_cancel_order(&mut self.runtime, request).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 取消场馆预约订单。
    ///
    /// # Errors
    ///
    /// 参数无效、会话所有权校验、网络写请求或上游响应处理失败时返回错误。
    pub async fn cgyy_cancel_order(
        &mut self,
        request: CgyyCancelOrderRequest,
    ) -> Result<FeatureResult<CgyyCancelOrderResult>> {
        self.guard_latest_session_ownership()?;
        self.runtime.begin_non_idempotent_operation();
        let result = crate::features::cgyy::cancel_order(&mut self.runtime, request).await;
        let data = self.finish_write_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 只读复核场馆预约的当前日期和唯一 typed 槽位目标。
    ///
    /// # Errors
    ///
    /// 会话所有权失效、目标不唯一、资格不足或上游结构变化时返回错误。
    pub async fn preflight_cgyy_reservation(
        &mut self,
        request: &CgyyReservationSubmitRequest,
    ) -> Result<FeatureResult<CgyyReservationPreflight>> {
        self.guard_latest_session_ownership()?;
        let result = crate::features::cgyy::preflight_reservation(&mut self.runtime, request).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 提交场馆预约；验证码材料可由调用方提供或由 Core 自动获取并校验。
    ///
    /// # Errors
    ///
    /// 会话所有权校验、网络写请求或上游响应处理失败时返回错误。
    pub async fn cgyy_submit_reservation(
        &mut self,
        request: CgyyReservationSubmitRequest,
    ) -> Result<FeatureResult<CgyyReservationResult>> {
        self.guard_latest_session_ownership()?;
        self.runtime.begin_non_idempotent_operation();
        let result = crate::features::cgyy::submit_reservation(&mut self.runtime, request).await;
        let data = self.finish_write_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }
}
