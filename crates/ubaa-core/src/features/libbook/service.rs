//! 图书馆 CAS/token 生命周期、业务请求与读写操作。

use serde_json::{Value, json};
use tracing::debug;

use crate::domain::{
    LibBookArea, LibBookAreaDetail, LibBookBookingsPage, LibBookCancelResult, LibBookLibrary,
    LibBookReserveRequest, LibBookReserveResult, LibBookSeat,
};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::HttpRequest;

use super::LibBookCredential;
use super::crypto::encrypt_reserve_request;
use super::parser::{
    envelope, error, is_expired_body, parse_area_detail_for, parse_areas, parse_bookings,
    parse_libraries, parse_seats,
};

const BASE_URL: &str = "https://booking.lib.buaa.edu.cn";
const CAS_URL: &str = "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fbooking.lib.buaa.edu.cn%2Fv4%2Flogin%2Fcas";
const REDIRECT_LIMIT: usize = 8;

/// 查询图书馆楼馆列表。
pub(crate) async fn get_libraries(
    runtime: &mut crate::runtime::ClientRuntime,
    day: &str,
) -> Result<Vec<LibBookLibrary>> {
    parse_libraries(&request_json(runtime, "space/pcTopFor", json!({"day": day}), true).await?)
}

/// 查询图书馆分区列表。
pub(crate) async fn get_areas(
    runtime: &mut crate::runtime::ClientRuntime,
    premises_id: &str,
    storey_id: Option<&str>,
    day: &str,
) -> Result<Vec<LibBookArea>> {
    let body = json!({"premisesIds": premises_id, "categoryIds": [], "storeyIds": storey_id.map_or_else(Vec::new, |id| vec![id]), "boutiqueIds": [], "date": day});
    parse_areas(&request_json(runtime, "space/pick", body, true).await?)
}

/// 查询分区详情。
pub(crate) async fn get_area_detail(
    runtime: &mut crate::runtime::ClientRuntime,
    area_id: &str,
) -> Result<LibBookAreaDetail> {
    parse_area_detail_for(
        area_id,
        &request_json(runtime, "Space/map", json!({"id": area_id}), true).await?,
    )
}

/// 查询指定日期和时段的座位。
pub(crate) async fn get_seats(
    runtime: &mut crate::runtime::ClientRuntime,
    area_id: &str,
    day: &str,
    start_time: &str,
    end_time: &str,
) -> Result<Vec<LibBookSeat>> {
    let body = json!({"id": area_id, "day": day, "label_id": [], "start_time": start_time, "end_time": end_time, "begdate": "", "enddate": ""});
    parse_seats(&request_json(runtime, "Space/seat", body, true).await?)
}

/// 查询当前用户的预约记录。
pub(crate) async fn get_bookings(
    runtime: &mut crate::runtime::ClientRuntime,
    page: i32,
    limit: i32,
) -> Result<LibBookBookingsPage> {
    if page <= 0 || limit <= 0 {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "分页参数无效",
        ));
    }
    parse_bookings(
        &request_json(
            runtime,
            "member/seat",
            json!({"type": "1", "page": page, "limit": limit}),
            true,
        )
        .await?,
    )
}

pub(crate) async fn reserve(
    runtime: &mut crate::runtime::ClientRuntime,
    request: LibBookReserveRequest,
) -> Result<LibBookReserveResult> {
    if request.seat_id.trim().is_empty()
        || request.segment.trim().is_empty()
        || request.day.trim().is_empty()
    {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "预约座位、时段和日期不能为空",
        ));
    }
    let body = json!({"aesjson": encrypt_reserve_request(&request)?});
    let response = request_json(runtime, "space/confirm", body, true).await?;
    let value = envelope(&response)?;
    let object = value.as_object();
    let success = object
        .and_then(|m| m.get("success"))
        .and_then(Value::as_bool)
        .or_else(|| {
            object
                .and_then(|m| m.get("status"))
                .and_then(Value::as_i64)
                .map(|v| v == 1)
        })
        .unwrap_or(true);
    let message = object
        .and_then(|m| m.get("message").or_else(|| m.get("msg")))
        .and_then(Value::as_str)
        .unwrap_or(if success {
            "预约成功"
        } else {
            "预约失败"
        })
        .to_owned();
    Ok(LibBookReserveResult {
        success,
        message,
        booking: None,
    })
}

pub(crate) async fn cancel_booking(
    runtime: &mut crate::runtime::ClientRuntime,
    booking_id: &str,
) -> Result<LibBookCancelResult> {
    if booking_id.trim().is_empty() {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "预约编号不能为空",
        ));
    }
    let response = request_json(runtime, "space/cancel", json!({"id": booking_id}), true).await?;
    let value = envelope(&response)?;
    let object = value.as_object();
    let success = object
        .and_then(|m| m.get("success"))
        .and_then(Value::as_bool)
        .or_else(|| {
            object
                .and_then(|m| m.get("status"))
                .and_then(Value::as_i64)
                .map(|v| v == 1)
        })
        .unwrap_or(true);
    let message = object
        .and_then(|m| m.get("message").or_else(|| m.get("msg")))
        .and_then(Value::as_str)
        .unwrap_or(if success {
            "取消成功"
        } else {
            "取消失败"
        })
        .to_owned();
    Ok(LibBookCancelResult { success, message })
}

async fn request_json(
    runtime: &mut crate::runtime::ClientRuntime,
    path: &str,
    body: Value,
    allow_retry: bool,
) -> Result<String> {
    crate::features::require_session(runtime)?;
    let credential = current_credential(runtime).await?;
    let url = runtime.url(&format!("{BASE_URL}/v4/{path}"))?;
    let request_body = serde_json::to_vec(&body).map_err(|_| error("图书馆请求参数无效"))?;
    let authorization = format!("bearer{}", credential.token);
    let referer = format!("{BASE_URL}/");
    let response = crate::features::post_json(
        runtime,
        url,
        request_body,
        &[
            ("Authorization", &authorization),
            ("Origin", BASE_URL),
            ("Referer", &referer),
            ("X-Requested-With", "XMLHttpRequest"),
        ],
    )
    .await?;
    debug!(
        target: "ubaa::libbook",
        operation = path,
        route = ?runtime.mode(),
        status = response.status,
        final_url = %safe_url(&response.final_url),
        body_len = response.body.len(),
        body_shape = %safe_body_shape(&response.body),
        "图书馆业务响应摘要"
    );
    if response.status == 401 || (allow_retry && is_expired_body(&crate::features::body(&response)))
    {
        if allow_retry {
            runtime.feature_state().libbook.clear_credential();
            return Box::pin(request_json(runtime, path, body, false)).await;
        }
        return Err(UbaaError::new(
            ErrorCode::AuthenticationRequired,
            ErrorKind::Authentication,
            false,
            "图书馆业务会话已失效",
        ));
    }
    if response.status != 200 {
        return Err(UbaaError::new(
            ErrorCode::UpstreamUnavailable,
            ErrorKind::Upstream,
            true,
            "图书馆服务暂时不可用",
        ));
    }
    Ok(crate::features::body(&response))
}

fn safe_url(value: &str) -> String {
    url::Url::parse(value).map_or_else(
        |_| "<无效 URL>".to_owned(),
        |url| {
            format!(
                "{}://{}{}",
                url.scheme(),
                url.host_str().unwrap_or("<无主机>"),
                url.path()
            )
        },
    )
}

fn safe_body_shape(body: &[u8]) -> String {
    let Ok(value) = serde_json::from_slice::<Value>(body) else {
        return "非 JSON".to_owned();
    };
    let Some(object) = value.as_object() else {
        return format!("顶层={}", json_kind(&value));
    };
    let mut keys = object.keys().cloned().collect::<Vec<_>>();
    keys.sort_unstable();
    let code = object.get("code").map_or_else(
        || "无 code".to_owned(),
        |value| format!("code={}", safe_scalar(value)),
    );
    let data = object.get("data").map_or_else(
        || "无 data".to_owned(),
        |value| format!("data={}", json_kind(value)),
    );
    format!("{}; keys={}; {}", code, keys.join(","), data)
}

fn json_kind(value: &Value) -> &'static str {
    match value {
        Value::Null => "null",
        Value::Bool(_) => "bool",
        Value::Number(_) => "number",
        Value::String(_) => "string",
        Value::Array(_) => "array",
        Value::Object(_) => "object",
    }
}

fn safe_scalar(value: &Value) -> String {
    match value {
        Value::Number(number) => number.to_string(),
        Value::Bool(value) => value.to_string(),
        Value::String(value) => format!("字符串(len={})", value.len()),
        _ => json_kind(value).to_owned(),
    }
}

async fn current_credential(
    runtime: &mut crate::runtime::ClientRuntime,
) -> Result<LibBookCredential> {
    let state = runtime.feature_state();
    if let Some(value) = state.libbook.credential() {
        return Ok(value);
    }
    let _guard = state.libbook.login_guard().await;
    if let Some(value) = state.libbook.credential() {
        return Ok(value);
    }
    let cas = fetch_cas(runtime).await?;
    let body = serde_json::to_vec(&json!({"cas": cas})).map_err(|_| error("图书馆登录参数无效"))?;
    let url = runtime.url(&format!("{BASE_URL}/v4/login/user"))?;
    let response = crate::features::post_json(runtime, url, body, &[("Origin", BASE_URL)]).await?;
    if response.status != 200 {
        return Err(UbaaError::new(
            ErrorCode::AuthenticationRequired,
            ErrorKind::Authentication,
            false,
            "图书馆登录失败",
        ));
    }
    let value: Value =
        serde_json::from_slice(&response.body).map_err(|_| error("图书馆登录响应无法解析"))?;
    let token = value
        .pointer("/data/member/token")
        .and_then(Value::as_str)
        .filter(|v| !v.is_empty())
        .ok_or_else(|| {
            UbaaError::new(
                ErrorCode::AuthenticationRequired,
                ErrorKind::Authentication,
                false,
                "图书馆登录响应缺少 token",
            )
        })?
        .to_owned();
    let credential = LibBookCredential { token };
    state.libbook.set(credential.clone());
    Ok(credential)
}

async fn fetch_cas(runtime: &mut crate::runtime::ClientRuntime) -> Result<String> {
    let mut current = CAS_URL.to_owned();
    for _ in 0..REDIRECT_LIMIT {
        let response = runtime
            .request(HttpRequest::get(runtime.url(&current)?))
            .await?;
        if let Some(value) = cas_from_url(&response.final_url) {
            return Ok(value);
        }
        let location = response
            .headers
            .iter()
            .find(|(name, _)| name.eq_ignore_ascii_case("location"))
            .and_then(|(_, values)| values.first())
            .ok_or_else(|| error("图书馆 CAS 登录跳转缺少目标地址"))?;
        let direct_final = crate::connection::from_webvpn_url(&response.final_url)
            .unwrap_or_else(|_| response.final_url.clone());
        let direct_location =
            crate::connection::from_webvpn_url(location).unwrap_or_else(|_| location.clone());
        let target = url::Url::parse(&direct_final)
            .map_err(|_| error("图书馆登录跳转地址无效"))?
            .join(&direct_location)
            .map_err(|_| error("图书馆登录跳转地址无效"))?;
        if !matches!(
            target.host_str(),
            Some("sso.buaa.edu.cn" | "booking.lib.buaa.edu.cn")
        ) {
            return Err(error("图书馆登录跳转到未允许的主机"));
        }
        current = target.to_string();
        if let Some(value) = cas_from_url(&current) {
            return Ok(value);
        }
    }
    Err(error("图书馆登录跳转次数超过限制"))
}

fn cas_from_url(raw: &str) -> Option<String> {
    let url = url::Url::parse(raw).ok()?;
    url.query_pairs()
        .find(|(key, _)| key.eq_ignore_ascii_case("cas"))
        .map(|(_, value)| value.into_owned())
        .or_else(|| {
            url.fragment().and_then(|fragment| {
                let query = fragment
                    .split_once('?')
                    .map_or(fragment, |(_, query)| query);
                url::form_urlencoded::parse(query.as_bytes())
                    .find(|(key, _)| key.eq_ignore_ascii_case("cas"))
                    .map(|(_, value)| value.into_owned())
            })
        })
}
