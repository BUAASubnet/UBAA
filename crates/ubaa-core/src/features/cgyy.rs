//! 场馆预约只读响应解析。
#![allow(clippy::missing_errors_doc)]

use crate::domain::{
    CgyyActionResult, CgyyDayInfo, CgyyLockCode, CgyyOrder, CgyyOrdersPage, CgyyPurposeType,
    CgyySlotStatus, CgyySpaceAvailability, CgyyTimeSlot, CgyyVenueSite,
};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::HttpRequest;
use md5::{Digest, Md5};
use serde_json::{Map, Value};
use std::collections::BTreeMap;

const BASE_URL: &str = "https://cgyy.buaa.edu.cn/venue-zhjs-server";
const LOGIN_URL: &str = "https://cgyy.buaa.edu.cn/venue-zhjs-server/sso/manageLogin";
const PREFIX: &str = "c640ca392cd45fb3a55b00a63a86c618";
const APP_KEY: &str = "8fceb735082b5a529312040b58ea780b";
const SSO_COOKIE: &str = "sso_buaa_zhjs_token";

fn timestamp_millis() -> Result<i64> {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|_| error("系统时间无效"))?
        .as_millis()
        .try_into()
        .map_err(|_| error("系统时间无效"))
}

fn sign(path: &str, params: &BTreeMap<String, String>, timestamp: i64) -> String {
    let path = if path.starts_with('/') {
        path.to_owned()
    } else {
        format!("/{path}")
    };
    let mut payload = format!("{PREFIX}{path}");
    for (key, value) in params.iter().filter(|(_, value)| !value.is_empty()) {
        payload.push_str(key);
        payload.push_str(value);
    }
    payload.push_str(&timestamp.to_string());
    payload.push(' ');
    payload.push_str(PREFIX);
    format!("{:x}", Md5::digest(payload.as_bytes()))
}

fn signed_request(
    runtime: &crate::runtime::ClientRuntime,
    method: crate::ports::HttpMethod,
    path: &str,
    mut params: BTreeMap<String, String>,
    token: Option<&str>,
) -> Result<HttpRequest> {
    let timestamp = timestamp_millis()?;
    if method == crate::ports::HttpMethod::Get {
        params
            .entry("nocache".into())
            .or_insert_with(|| timestamp.to_string());
    }
    let signature = sign(path, &params, timestamp);
    let mut direct =
        url::Url::parse(&format!("{BASE_URL}{path}")).map_err(|_| error("场馆请求地址无效"))?;
    if method == crate::ports::HttpMethod::Get {
        direct.query_pairs_mut().extend_pairs(
            params
                .iter()
                .map(|(key, value)| (key.as_str(), value.as_str())),
        );
    }
    let mut request = match method {
        crate::ports::HttpMethod::Get => HttpRequest::get(runtime.url(direct.as_str())?),
        crate::ports::HttpMethod::Post => {
            HttpRequest::post(runtime.url(direct.as_str())?, Vec::new())
        }
    };
    request
        .headers
        .insert("Accept".into(), "application/json, text/plain, */*".into());
    request.headers.insert(
        "Referer".into(),
        runtime.url("https://cgyy.buaa.edu.cn/venue-zhjs/mobileReservation")?,
    );
    request.headers.insert("app-key".into(), APP_KEY.into());
    request
        .headers
        .insert("timestamp".into(), timestamp.to_string());
    request.headers.insert("sign".into(), signature);
    if method == crate::ports::HttpMethod::Post {
        request.headers.insert(
            "Content-Type".into(),
            "application/x-www-form-urlencoded".into(),
        );
    }
    if let Some(token) = token {
        request
            .headers
            .insert("cgAuthorization".into(), token.into());
    }
    Ok(request)
}

async fn ensure_login(runtime: &mut crate::runtime::ClientRuntime) -> Result<String> {
    super::require_session(runtime)?;
    let state = runtime.feature_state();
    if let Some(token) = state.cgyy.token() {
        return Ok(token);
    }
    let _guard = state.cgyy.login_guard().await;
    if let Some(token) = state.cgyy.token() {
        return Ok(token);
    }
    let response =
        super::get_with_redirects(runtime, runtime.url(LOGIN_URL)?, &[], "场馆预约").await?;
    super::check_response(&response, "场馆预约")?;
    let sso_token = runtime
        .cookie_value(SSO_COOKIE)
        .ok_or_else(|| authentication_error("未获取到场馆预约 SSO 令牌"))?;
    let mut request = signed_request(
        runtime,
        crate::ports::HttpMethod::Post,
        "/api/login",
        BTreeMap::new(),
        None,
    )?;
    request.headers.insert("Sso-Token".into(), sso_token);
    let response = runtime.request(request).await?;
    super::check_response(&response, "场馆预约")?;
    let value = data(&super::body(&response))?;
    let token = value
        .get("token")
        .and_then(Value::as_object)
        .and_then(|token| string(token, "access_token"))
        .filter(|token| !token.is_empty())
        .ok_or_else(|| authentication_error("场馆预约登录未返回访问令牌"))?;
    state.cgyy.set(token.clone());
    Ok(token)
}

async fn get(
    runtime: &mut crate::runtime::ClientRuntime,
    path: &str,
    params: BTreeMap<String, String>,
) -> Result<String> {
    let token = ensure_login(runtime).await?;
    let request = signed_request(
        runtime,
        crate::ports::HttpMethod::Get,
        path,
        params,
        Some(&token),
    )?;
    let response = runtime.request(request).await?;
    super::check_response(&response, "场馆预约")?;
    Ok(super::body(&response))
}

pub(crate) async fn get_sites(
    runtime: &mut crate::runtime::ClientRuntime,
) -> Result<Vec<CgyyVenueSite>> {
    let params = [("page", "-1"), ("size", "-1"), ("reservationRoleId", "3")]
        .into_iter()
        .map(|(key, value)| (key.into(), value.into()))
        .collect();
    parse_sites(&get(runtime, "/api/front/website/venues", params).await?)
}

pub(crate) async fn get_purpose_types(
    runtime: &mut crate::runtime::ClientRuntime,
) -> Result<Vec<CgyyPurposeType>> {
    parse_purpose_types(&get(runtime, "/api/codes", BTreeMap::new()).await?)
}

pub(crate) async fn get_day_info(
    runtime: &mut crate::runtime::ClientRuntime,
    site_id: i32,
    date: &str,
) -> Result<CgyyDayInfo> {
    let params = [
        ("searchDate".into(), date.into()),
        ("venueSiteId".into(), site_id.to_string()),
    ]
    .into_iter()
    .collect();
    parse_day_info(
        &get(runtime, "/api/reservation/day/info", params).await?,
        site_id,
        date,
    )
}

pub(crate) async fn get_orders(
    runtime: &mut crate::runtime::ClientRuntime,
    page: i32,
    size: i32,
) -> Result<CgyyOrdersPage> {
    let params = [
        ("page".into(), page.to_string()),
        ("size".into(), size.to_string()),
    ]
    .into_iter()
    .collect();
    parse_orders(&get(runtime, "/api/orders/mine", params).await?)
}

pub(crate) async fn get_order_detail(
    runtime: &mut crate::runtime::ClientRuntime,
    id: i32,
) -> Result<CgyyOrder> {
    parse_order_detail(&get(runtime, &format!("/api/orders/{id}"), BTreeMap::new()).await?)
}

/// 查询当前用户可用的门锁码，保留上游结构为不透明 JSON。
pub(crate) async fn get_lock_code(
    runtime: &mut crate::runtime::ClientRuntime,
) -> Result<CgyyLockCode> {
    let value = get(runtime, "/api/orders/lock/code", BTreeMap::new()).await?;
    parse_lock_code(&value)
}

/// 解析门锁码响应，仅保留不透明的业务数据。
pub fn parse_lock_code(body: &str) -> Result<CgyyLockCode> {
    let root = object(body)?;
    Ok(CgyyLockCode {
        raw_data: root.get("data").cloned().unwrap_or(Value::Object(root)),
    })
}

/// 取消指定场馆预约订单。
pub(crate) async fn cancel_order(
    runtime: &mut crate::runtime::ClientRuntime,
    id: i32,
) -> Result<CgyyActionResult> {
    let token = ensure_login(runtime).await?;
    let request = signed_request(
        runtime,
        crate::ports::HttpMethod::Post,
        &format!("/api/orders/new/cancel/{id}"),
        BTreeMap::new(),
        Some(&token),
    )?;
    let response = runtime.request(request).await?;
    super::check_response(&response, "场馆预约")?;
    parse_action_result(&super::body(&response))
}

/// 解析场馆预约写操作响应。
pub fn parse_action_result(body: &str) -> Result<CgyyActionResult> {
    let root = object(body)?;
    let message = string(&root, "message").unwrap_or_default();
    let value = data(body)?;
    let order = value.as_object().map(parse_order);
    Ok(CgyyActionResult { message, order })
}

fn authentication_error(message: &str) -> UbaaError {
    UbaaError::new(
        ErrorCode::AuthenticationRequired,
        ErrorKind::Authentication,
        false,
        message,
    )
}

fn error(message: impl Into<String>) -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        message,
    )
}

fn object(body: &str) -> Result<Map<String, Value>> {
    let value: Value = serde_json::from_str(body).map_err(|_| error("场馆预约响应无法解析"))?;
    value
        .as_object()
        .cloned()
        .ok_or_else(|| error("场馆预约响应结构无效"))
}

fn data(body: &str) -> Result<Value> {
    let root = object(body)?;
    let success = root.get("success").and_then(Value::as_bool);
    let code = root.get("code").and_then(Value::as_i64);
    if success == Some(false) || code.is_some_and(|value| value != 0 && value != 200) {
        let message = string(&root, "message").unwrap_or_else(|| "场馆预约请求失败".into());
        return Err(error(message));
    }
    Ok(root.get("data").cloned().unwrap_or(Value::Object(root)))
}

fn string(map: &Map<String, Value>, key: &str) -> Option<String> {
    map.get(key).and_then(Value::as_str).map(str::to_owned)
}

fn int(map: &Map<String, Value>, key: &str) -> Option<i32> {
    map.get(key)
        .and_then(|value| value.as_i64().or_else(|| value.as_str()?.parse().ok()))
        .and_then(|value| i32::try_from(value).ok())
}

fn bool_value(map: &Map<String, Value>, key: &str) -> Option<bool> {
    map.get(key).and_then(|value| {
        value.as_bool().or_else(|| match value.as_str()? {
            "true" => Some(true),
            "false" => Some(false),
            _ => None,
        })
    })
}

/// 解析场馆站点列表。
pub fn parse_sites(body: &str) -> Result<Vec<CgyyVenueSite>> {
    let value = data(body)?;
    let values = value
        .as_array()
        .or_else(|| value.as_object()?.get("content")?.as_array())
        .ok_or_else(|| error("场馆站点响应结构无效"))?;
    Ok(values
        .iter()
        .filter_map(Value::as_object)
        .map(|item| CgyyVenueSite {
            id: int(item, "id").unwrap_or_default(),
            site_name: string(item, "siteName").unwrap_or_default(),
            venue_name: string(item, "venueName").unwrap_or_default(),
            campus_name: string(item, "campusName").unwrap_or_default(),
            seat_count: int(item, "seatCount"),
            reservation_space_count: int(item, "reservationSpaceCount"),
            site_telephone: string(item, "siteTelephone"),
            open_start_date: string(item, "openStartDate"),
            open_end_date: string(item, "openEndDate"),
        })
        .collect())
}

/// 解析用途类型；上游未返回有效类型时使用冻结实现中的静态定义。
pub fn parse_purpose_types(body: &str) -> Result<Vec<CgyyPurposeType>> {
    let value = data(body)?;
    let mut result = Vec::new();
    collect_purpose_types(&value, &mut result);
    result.sort_by_key(|item| item.key);
    result.dedup_by_key(|item| item.key);
    Ok(if result.is_empty() {
        fallback_purpose_types()
    } else {
        result
    })
}

fn collect_purpose_types(value: &Value, result: &mut Vec<CgyyPurposeType>) {
    match value {
        Value::Array(values) => values
            .iter()
            .for_each(|value| collect_purpose_types(value, result)),
        Value::Object(map) => {
            let key = int(map, "key")
                .or_else(|| int(map, "value"))
                .or_else(|| int(map, "id"));
            let name = string(map, "name");
            if let (Some(key), Some(name)) = (key, name)
                && name.contains('类')
            {
                result.push(CgyyPurposeType { key, name });
            }
            map.values()
                .for_each(|value| collect_purpose_types(value, result));
        }
        _ => {}
    }
}

fn fallback_purpose_types() -> Vec<CgyyPurposeType> {
    [
        "导学活动类",
        "学业支持类（串讲、答疑、学习小组讨论等）",
        "学术研讨类（竞赛、答辩、展示等小组讨论）",
        "党建活动类",
        "工作会议类（单位工作例会、学生组织工作会议等）",
        "团队建设类（班级、社团、学生会等学生组织团建）",
        "培训面试类（梦拓、学生组织培训及面试等）",
        "博雅课程类",
        "讲座、沙龙研讨类",
        "其他特色活动类",
    ]
    .into_iter()
    .enumerate()
    .map(|(index, name)| CgyyPurposeType {
        key: i32::try_from(index + 1).unwrap_or_default(),
        name: name.into(),
    })
    .collect()
}

/// 解析指定站点和日期的可预约信息。
pub fn parse_day_info(
    body: &str,
    venue_site_id: i32,
    reservation_date: &str,
) -> Result<CgyyDayInfo> {
    let value = data(body)?;
    let root = value
        .as_object()
        .ok_or_else(|| error("场馆日期响应结构无效"))?;
    let time_slots: Vec<_> = root
        .get("spaceTimeInfo")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_object)
        .filter_map(|slot| {
            Some(CgyyTimeSlot {
                id: int(slot, "id")?,
                begin_time: string(slot, "beginTime")?,
                end_time: string(slot, "endTime")?,
                label: format!(
                    "{}-{}",
                    string(slot, "beginTime")?,
                    string(slot, "endTime")?
                ),
            })
        })
        .collect();
    let date_map = root
        .get("reservationDateSpaceInfo")
        .and_then(Value::as_object);
    let date_key = date_map
        .and_then(|map| {
            map.contains_key(reservation_date)
                .then_some(reservation_date.to_owned())
                .or_else(|| map.keys().next().cloned())
        })
        .unwrap_or_else(|| reservation_date.to_owned());
    let mut spaces: Vec<_> = date_map
        .and_then(|map| map.get(&date_key))
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_object)
        .map(|space| CgyySpaceAvailability {
            space_id: int(space, "id").unwrap_or_default(),
            space_name: string(space, "spaceName").unwrap_or_default(),
            venue_site_id: int(space, "venueSiteId").unwrap_or(venue_site_id),
            venue_space_group_id: int(space, "venueSpaceGroupId"),
            slots: time_slots
                .iter()
                .filter_map(|slot| {
                    space
                        .get(&slot.id.to_string())
                        .and_then(Value::as_object)
                        .map(|raw| parse_slot(slot.id, raw))
                })
                .collect(),
        })
        .collect();
    spaces.sort_by(|left, right| left.space_name.cmp(&right.space_name));
    let available_dates = root
        .get("ableReservationDateList")
        .or_else(|| root.get("reservationDateList"))
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .map(str::to_owned)
        .collect();
    Ok(CgyyDayInfo {
        venue_site_id,
        reservation_date: date_key,
        available_dates,
        time_slots,
        spaces,
        reservation_token: string(root, "token"),
        reservation_total_num: int(root, "reservationTotalNum"),
    })
}

fn parse_slot(time_id: i32, raw: &Map<String, Value>) -> CgyySlotStatus {
    let reservation_status = int(raw, "reservationStatus").unwrap_or_default();
    let trade_no = string(raw, "tradeNo");
    let order_id = int(raw, "orderId");
    let take_up = bool_value(raw, "takeUp");
    CgyySlotStatus {
        time_id,
        reservation_status,
        is_reservable: reservation_status == 1
            && trade_no.is_none()
            && order_id.is_none()
            && take_up != Some(true),
        start_date: string(raw, "startDate"),
        end_date: string(raw, "endDate"),
        trade_no,
        order_id,
        use_num: int(raw, "useNum"),
        already_num: int(raw, "alreadyNum"),
        take_up,
        take_up_explain: string(raw, "takeUpExplain"),
    }
}

/// 解析预约订单分页。
pub fn parse_orders(body: &str) -> Result<CgyyOrdersPage> {
    let value = data(body)?;
    let root = value
        .as_object()
        .ok_or_else(|| error("场馆订单响应结构无效"))?;
    Ok(CgyyOrdersPage {
        content: root
            .get("content")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(Value::as_object)
            .map(parse_order)
            .collect(),
        total_elements: int(root, "totalElements").unwrap_or_default(),
        total_pages: int(root, "totalPages").unwrap_or_default(),
        size: int(root, "size").unwrap_or(20),
        number: int(root, "number").unwrap_or_default(),
    })
}

/// 解析单个预约订单详情。
pub fn parse_order_detail(body: &str) -> Result<CgyyOrder> {
    let value = data(body)?;
    value
        .as_object()
        .map(parse_order)
        .ok_or_else(|| error("场馆订单详情结构无效"))
}

fn parse_order(raw: &Map<String, Value>) -> CgyyOrder {
    let purpose_type = int(raw, "purposeType");
    CgyyOrder {
        id: int(raw, "id").unwrap_or_default(),
        trade_no: string(raw, "tradeNo"),
        venue_site_id: int(raw, "venueSiteId"),
        reservation_date: string(raw, "reservationDate"),
        reservation_date_detail: string(raw, "reservationDateDetail"),
        venue_space_name: string(raw, "venueSpaceName"),
        campus_name: string(raw, "campusName"),
        venue_name: string(raw, "venueName"),
        site_name: string(raw, "siteName"),
        reservation_start_date: string(raw, "reservationStartDate"),
        reservation_end_date: string(raw, "reservationEndDate"),
        phone: string(raw, "phone"),
        order_status: int(raw, "orderStatus"),
        pay_status: int(raw, "payStatus"),
        check_status: int(raw, "checkStatus"),
        theme: string(raw, "theme"),
        purpose_type,
        purpose_type_name: purpose_type.and_then(|key| {
            fallback_purpose_types()
                .into_iter()
                .find(|item| item.key == key)
                .map(|item| item.name)
        }),
        joiner_num: int(raw, "joinerNum"),
        activity_content: string(raw, "activityContent"),
        joiners: string(raw, "joiners"),
        check_content: string(raw, "checkContent"),
        handle_reason: string(raw, "handleReason"),
        remark: string(raw, "remark"),
    }
}

#[cfg(test)]
mod tests {
    use super::parse_action_result;

    #[test]
    fn 解析取消订单成功消息() {
        let result = parse_action_result(r#"{"code":200,"message":"取消成功","data":null}"#)
            .expect("应解析成功");
        assert_eq!(result.message, "取消成功");
        assert!(result.order.is_none());
    }
}
