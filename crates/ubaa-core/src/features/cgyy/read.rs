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
    parse_order_detail_at, parse_orders_at, parse_purpose_types_with_source, parse_sites,
    shanghai_datetime,
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
    let params = [
        ("page".into(), page.to_string()),
        ("size".into(), size.to_string()),
    ]
    .into_iter()
    .collect();
    let body = get(runtime, "/api/orders/mine", params).await?;
    parse_orders_at(&body, shanghai_datetime(runtime.now()))
}

pub(crate) async fn get_order_detail(runtime: &mut ClientRuntime, id: i32) -> Result<CgyyOrder> {
    let body = get(runtime, &format!("/api/orders/{id}"), BTreeMap::new()).await?;
    parse_order_detail_at(&body, shanghai_datetime(runtime.now()))
}

/// 查询当前用户可用的门锁码，保留上游结构为不透明 JSON。
pub(crate) async fn get_lock_code(runtime: &mut ClientRuntime) -> Result<CgyyLockCode> {
    let value = get(runtime, "/api/orders/lock/code", BTreeMap::new()).await?;
    parse_lock_code(&value)
}
