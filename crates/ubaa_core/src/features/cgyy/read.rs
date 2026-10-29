//! 场馆站点、用途、日期、订单与锁码只读操作。

use std::collections::BTreeMap;

use crate::domain::{
    CgyyDayInfo, CgyyLockCode, CgyyOrder, CgyyOrdersPage, CgyyPurposeSource, CgyyPurposeType,
    CgyyVenueSite,
};
use crate::error::{ErrorCode, Result};
use crate::runtime::ClientRuntime;

use super::auth::get;
use super::parser::{
    CgyyDayContext, fallback_purpose_types, parse_day_context, parse_lock_code,
    parse_order_detail_at, parse_orders_at, parse_orders_for_cache,
    parse_purpose_types_with_source, parse_sites,
};

pub(crate) async fn get_sites(runtime: &mut ClientRuntime) -> Result<Vec<CgyyVenueSite>> {
    let params = [("page", "-1"), ("size", "-1"), ("reservationRoleId", "3")]
        .into_iter()
        .map(|(key, value)| (key.into(), value.into()))
        .collect();
    parse_sites(&get(runtime, "/api/front/website/venues", params).await?)
}

pub(crate) async fn get_purpose_types(runtime: &mut ClientRuntime) -> Result<Vec<CgyyPurposeType>> {
    Ok(get_purpose_types_with_source(runtime).await?.0)
}

pub(crate) async fn get_purpose_types_with_source(
    runtime: &mut ClientRuntime,
) -> Result<(Vec<CgyyPurposeType>, CgyyPurposeSource)> {
    // 保留冻结实现的静态回退语义，但认证失效必须向上游报告，不能伪装成成功。
    super::super::require_session(runtime)?;
    match get(runtime, "/api/codes", BTreeMap::new()).await {
        Ok(body) => match parse_purpose_types_with_source(&body) {
            Ok(result) => Ok(result),
            Err(_) => Ok((fallback_purpose_types(), CgyyPurposeSource::StaticFallback)),
        },
        Err(error) if error.code == ErrorCode::AuthenticationRequired => Err(error),
        Err(_) => Ok((fallback_purpose_types(), CgyyPurposeSource::StaticFallback)),
    }
}

pub(crate) async fn get_day_info(
    runtime: &mut ClientRuntime,
    site_id: i32,
    date: &str,
) -> Result<CgyyDayInfo> {
    Ok(get_day_context(runtime, site_id, date).await?.info)
}

pub(super) async fn get_day_context(
    runtime: &mut ClientRuntime,
    site_id: i32,
    date: &str,
) -> Result<CgyyDayContext> {
    let params = [
        ("searchDate".into(), date.into()),
        ("venueSiteId".into(), site_id.to_string()),
    ]
    .into_iter()
    .collect();
    parse_day_context(
        &get(runtime, "/api/reservation/day/info", params).await?,
        site_id,
        date,
    )
}

pub(crate) async fn get_orders(
    runtime: &mut ClientRuntime,
    page: i32,
    size: i32,
) -> Result<CgyyOrdersPage> {
    let body = orders_body(runtime, page, size).await?;
    parse_orders_at(&body, crate::time::shanghai_datetime(runtime.now()))
}

pub(crate) async fn get_orders_observed(
    runtime: &mut ClientRuntime,
    page: i32,
    size: i32,
) -> Result<(CgyyOrdersPage, bool)> {
    let body = orders_body(runtime, page, size).await?;
    parse_orders_for_cache(
        &body,
        crate::time::shanghai_datetime(runtime.now()),
        page,
        size,
    )
}

async fn orders_body(runtime: &mut ClientRuntime, page: i32, size: i32) -> Result<String> {
    let params = [
        ("page".into(), page.to_string()),
        ("size".into(), size.to_string()),
    ]
    .into_iter()
    .collect();
    get(runtime, "/api/orders/mine", params).await
}

pub(crate) async fn get_order_detail(runtime: &mut ClientRuntime, id: i32) -> Result<CgyyOrder> {
    let body = get(runtime, &format!("/api/orders/{id}"), BTreeMap::new()).await?;
    let data = super::parser::data(&body)?;
    if data.get("orderInfo").is_some() {
        return wrapped_order_detail(&data, id, crate::time::shanghai_datetime(runtime.now()));
    }
    let order = parse_order_detail_at(&body, crate::time::shanghai_datetime(runtime.now()))?;
    // 空信封兼容仍留在 parser；具体订单读取不能成功返回编号0或其他订单。
    if order.id <= 0 || order.id != id {
        tracing::debug!(target: "ubaa::cgyy", operation = "orders.detail",
            response_identity_present = order.id > 0, identity_matches = false,
            "订单详情响应缺少匹配的目标身份");
        return Err(super::parser::error("场馆订单详情缺失或与请求目标不符"));
    }
    Ok(order)
}

/// 实时详情使用独立包装且不回传列表数字编号；该编号只绑定请求上下文。
fn wrapped_order_detail(
    data: &serde_json::Value,
    requested_id: i32,
    now: chrono::NaiveDateTime,
) -> Result<CgyyOrder> {
    let raw = data
        .get("orderInfo")
        .and_then(serde_json::Value::as_object)
        .ok_or_else(|| super::parser::error("场馆订单详情包装结构无效"))?;
    let mut order = super::parser::parse_order_at(raw, now);
    if requested_id <= 0
        || (raw.contains_key("id") && order.id != requested_id)
        || order
            .trade_no
            .as_deref()
            .is_none_or(|value| value.trim().is_empty())
        || order.venue_site_id.is_none_or(|value| value <= 0)
        || order.order_status.is_none()
    {
        return Err(super::parser::error("场馆订单详情缺少订单依据或身份不符"));
    }
    order.id = requested_id;
    if let Some(venue) = data
        .get("venueInfoBean")
        .and_then(serde_json::Value::as_object)
    {
        order.venue_name = order
            .venue_name
            .or_else(|| super::parser::string(venue, "venueName"));
        order.site_name = order
            .site_name
            .or_else(|| super::parser::string(venue, "siteName"));
        order.campus_name = order
            .campus_name
            .or_else(|| super::parser::string(venue, "campusName"));
    }
    // 新包装的展示证据不扩展旧取消协议的 fresh authority。
    order.cancel_eligibility = crate::domain::ActionEligibility::Unknown;
    order.cancel_target = None;
    order.cancelled_target = None;
    Ok(order)
}

/// 查询当前用户可用的门锁码，保留上游结构为不透明 JSON。
pub(crate) async fn get_lock_code(runtime: &mut ClientRuntime) -> Result<CgyyLockCode> {
    let value = get(runtime, "/api/orders/lock/code", BTreeMap::new()).await?;
    parse_lock_code(&value)
}
