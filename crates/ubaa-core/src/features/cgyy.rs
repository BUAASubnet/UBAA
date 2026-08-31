//! 场馆预约只读响应解析。
#![allow(clippy::missing_errors_doc)]

use crate::domain::{
    CgyyActionResult, CgyyDayInfo, CgyyLockCode, CgyyOrder, CgyyOrdersPage, CgyyPurposeType,
    CgyySlotStatus, CgyySpaceAvailability, CgyyTimeSlot, CgyyVenueSite,
};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::HttpRequest;
use base64::Engine as _;
use serde_json::{Map, Value};
use std::collections::BTreeMap;
use std::time::Instant;
use tracing::{debug, info, warn};

use super::cgyy_crypto::build_captcha_solution;
use super::cgyy_sign::{sign, timestamp_millis};

const BASE_URL: &str = "https://cgyy.buaa.edu.cn/venue-zhjs-server";
const LOGIN_URL: &str = "https://cgyy.buaa.edu.cn/venue-zhjs-server/sso/manageLogin";
const APP_KEY: &str = "8fceb735082b5a529312040b58ea780b";
const SSO_COOKIE: &str = "sso_buaa_zhjs_token";

/// 验证码挑战的脱敏结构；图像求解过程仅在 Core 内部流转。
#[allow(dead_code)]
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct CgyyCaptchaChallenge {
    pub(crate) secret_key: String,
    pub(crate) token: String,
    pub(crate) original_image_base64: String,
    pub(crate) jigsaw_image_base64: String,
}

/// 使用冻结验证码密钥生成校验点和预约提交凭据。
///
/// 图像求解器只需提供滑块横向位移；密钥、令牌和 AES-ECB/PKCS#7 细节不会暴露给宿主。
/// 复刻冻结旧版的滑块位移匹配算法。输入为去除可选 data URI 前缀后的图片字节。
#[allow(dead_code)]
pub(crate) fn solve_captcha_offset(original: &[u8], jigsaw: &[u8]) -> Result<u32> {
    let background =
        image::load_from_memory(original).map_err(|_| error("验证码背景图无法解析"))?;
    let piece = image::load_from_memory(jigsaw).map_err(|_| error("验证码滑块图无法解析"))?;
    let bg = background.to_rgba8();
    let fg = piece.to_rgba8();
    let bg_gray = gray_pixels(&bg);
    let fg_gray = gray_pixels(&fg);
    let mask = build_image_mask(&fg);
    let (min_x, min_y, max_x, max_y) =
        image_bounds(&mask).ok_or_else(|| error("验证码图片缺少有效掩码"))?;
    let cropped_gray = crop_gray(&fg_gray, min_x, min_y, max_x, max_y);
    let cropped_mask = crop_mask(&mask, min_x, min_y, max_x, max_y);
    let bg_edges = edge_detect(&bg_gray);
    let piece_edges = edge_detect(&cropped_gray);
    let bg_h = bg_edges.len();
    let bg_w = bg_edges.first().map_or(0, Vec::len);
    let piece_h = piece_edges.len();
    let piece_w = piece_edges.first().map_or(0, Vec::len);
    if bg_h < piece_h || bg_w < piece_w {
        return Err(error("验证码图片尺寸无效"));
    }
    let mut best_score = f64::NEG_INFINITY;
    let mut best_x = 0u32;
    for y in 0..=(bg_h - piece_h) {
        for x in 0..=(bg_w - piece_w) {
            let mut score = 0.0;
            let mut edge_pixels = 0usize;
            let mut mask_pixels = 0usize;
            for py in 0..piece_h {
                for px in 0..piece_w {
                    if !cropped_mask[py][px] {
                        continue;
                    }
                    mask_pixels += 1;
                    let piece_value = piece_edges[py][px];
                    let bg_value = bg_edges[y + py][x + px];
                    if piece_value > 0 {
                        edge_pixels += 1;
                        score += if bg_value > 0 { 3.0 } else { -1.5 };
                    } else if bg_value == 0 {
                        score += 0.15;
                    }
                }
            }
            if mask_pixels == 0 || edge_pixels == 0 {
                continue;
            }
            score /= f64::from(u32::try_from(edge_pixels).unwrap_or(u32::MAX));
            score += f64::from(u32::try_from(mask_pixels).unwrap_or(u32::MAX)) * 0.0001;
            if score > best_score {
                best_score = score;
                best_x = u32::try_from(x).unwrap_or(u32::MAX);
            }
        }
    }
    Ok(best_x)
}

fn gray_pixels(image: &image::RgbaImage) -> Vec<Vec<i32>> {
    image
        .rows()
        .map(|row| {
            row.map(|pixel| {
                (i32::from(pixel[0]) * 30 + i32::from(pixel[1]) * 59 + i32::from(pixel[2]) * 11)
                    / 100
            })
            .collect()
        })
        .collect()
}

fn build_image_mask(image: &image::RgbaImage) -> Vec<Vec<bool>> {
    image
        .rows()
        .map(|row| {
            row.map(|pixel| {
                if pixel[3] > 10 {
                    true
                } else {
                    let luminance = (i32::from(pixel[0]) * 30
                        + i32::from(pixel[1]) * 59
                        + i32::from(pixel[2]) * 11)
                        / 100;
                    luminance < 250
                }
            })
            .collect()
        })
        .collect()
}

fn image_bounds(mask: &[Vec<bool>]) -> Option<(usize, usize, usize, usize)> {
    let mut bounds: Option<(usize, usize, usize, usize)> = None;
    for (y, row) in mask.iter().enumerate() {
        for (x, value) in row.iter().enumerate() {
            if !value {
                continue;
            }
            bounds = Some(match bounds {
                Some((min_x, min_y, max_x, max_y)) => {
                    (min_x.min(x), min_y.min(y), max_x.max(x), max_y.max(y))
                }
                None => (x, y, x, y),
            });
        }
    }
    bounds
}

fn crop_gray(
    source: &[Vec<i32>],
    min_x: usize,
    min_y: usize,
    max_x: usize,
    max_y: usize,
) -> Vec<Vec<i32>> {
    (min_y..=max_y)
        .map(|y| source[y][min_x..=max_x].to_vec())
        .collect()
}

fn crop_mask(
    source: &[Vec<bool>],
    min_x: usize,
    min_y: usize,
    max_x: usize,
    max_y: usize,
) -> Vec<Vec<bool>> {
    (min_y..=max_y)
        .map(|y| source[y][min_x..=max_x].to_vec())
        .collect()
}

fn edge_detect(gray: &[Vec<i32>]) -> Vec<Vec<u8>> {
    let height = gray.len();
    let width = gray.first().map_or(0, Vec::len);
    (0..height)
        .map(|y| {
            (0..width)
                .map(|x| {
                    let center = gray[y][x];
                    let right = gray[y][(x + 1).min(width.saturating_sub(1))];
                    let down = gray[(y + 1).min(height.saturating_sub(1))][x];
                    if (center - right).abs() + (center - down).abs() > 35 {
                        255
                    } else {
                        0
                    }
                })
                .collect()
        })
        .collect()
}

#[allow(dead_code)]
fn build_captcha_params(now: i64) -> BTreeMap<String, String> {
    [
        ("captchaType".into(), "blockPuzzle".into()),
        ("clientUid".into(), format!("slider-{now}")),
        ("ts".into(), now.to_string()),
    ]
    .into_iter()
    .collect()
}

#[allow(dead_code)]
fn parse_captcha_challenge(body: &str) -> Result<CgyyCaptchaChallenge> {
    let value = data(body)?;
    let success = value
        .get("success")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    if !success {
        return Err(error(
            value
                .get("repMsg")
                .and_then(Value::as_str)
                .unwrap_or("获取验证码失败"),
        ));
    }
    let rep_data = value
        .get("repData")
        .and_then(Value::as_object)
        .ok_or_else(|| error("验证码数据缺失"))?;
    let required = |key: &str| {
        rep_data
            .get(key)
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty())
            .map(str::to_owned)
            .ok_or_else(|| error("验证码数据缺失"))
    };
    Ok(CgyyCaptchaChallenge {
        secret_key: required("secretKey")?,
        token: required("token")?,
        original_image_base64: required("originalImageBase64")?,
        jigsaw_image_base64: required("jigsawImageBase64")?,
    })
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
    let request_url = runtime.url(direct.as_str())?;
    let mut request = match method {
        crate::ports::HttpMethod::Get => HttpRequest::get(request_url),
        crate::ports::HttpMethod::Post => HttpRequest::post(request_url, Vec::new()),
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
    debug!(
        target: "ubaa::cgyy",
        feature = "cgyy",
        route = ?runtime.mode(),
        operation = operation_name(method, path),
        method = method_name_value(method),
        path,
        request_url = %safe_url(&request.url),
        parameter_count = params.len(),
        token_present = token.is_some(),
        token_len = token.map_or(0, str::len),
        "已构造 Cgyy HTTP 请求"
    );
    Ok(request)
}

async fn ensure_login(runtime: &mut crate::runtime::ClientRuntime) -> Result<String> {
    super::require_session(runtime)?;
    let state = runtime.feature_state();
    if let Some(token) = state.cgyy.token() {
        debug!(target: "ubaa::cgyy", operation = "business_login", cached = true, "复用 Cgyy 业务会话");
        return Ok(token);
    }
    info!(target: "ubaa::cgyy", operation = "business_login", route = ?runtime.mode(), "开始建立 Cgyy 业务会话");
    let _guard = state.cgyy.login_guard().await;
    if let Some(token) = state.cgyy.token() {
        return Ok(token);
    }
    debug!(target: "ubaa::cgyy", operation = "business_login.sso", route = ?runtime.mode(), bootstrap_url = %safe_url(LOGIN_URL), "请求 Cgyy SSO 引导");
    let response =
        super::get_with_redirects(runtime, runtime.url(LOGIN_URL)?, &[], "场馆预约").await?;
    log_response(runtime, "business_login.sso", &response);
    super::check_response(&response, "场馆预约")?;
    let Some(sso_token) = runtime.cookie_value(SSO_COOKIE) else {
        warn!(target: "ubaa::cgyy", operation = "business_login.sso", route = ?runtime.mode(), sso_cookie_present = false, "Cgyy SSO 响应未写入令牌 Cookie");
        return Err(authentication_error("未获取到场馆预约 SSO 令牌"));
    };
    debug!(target: "ubaa::cgyy", operation = "business_login.sso", sso_cookie_present = true, sso_cookie_len = sso_token.len(), "已取得 Cgyy SSO Cookie");
    let mut request = signed_request(
        runtime,
        crate::ports::HttpMethod::Post,
        "/api/login",
        BTreeMap::new(),
        None,
    )?;
    request.headers.insert("Sso-Token".into(), sso_token);
    debug!(
        target: "ubaa::cgyy",
        operation = "business_login.api",
        route = ?runtime.mode(),
        body_len = request.body.len(),
        "发送 Cgyy 业务登录请求"
    );
    let response = runtime.request(request).await?;
    log_response(runtime, "business_login.api", &response);
    super::check_response(&response, "场馆预约")?;
    let value = data(&super::body(&response))?;
    let token = value
        .get("token")
        .and_then(Value::as_object)
        .and_then(|token| string(token, "access_token"))
        .filter(|token| !token.is_empty())
        .ok_or_else(|| authentication_error("场馆预约登录未返回访问令牌"))?;
    state.cgyy.set(token.clone());
    info!(target: "ubaa::cgyy", operation = "business_login", access_token_len = token.len(), "Cgyy 业务会话建立完成");
    Ok(token)
}

async fn business_request(
    runtime: &mut crate::runtime::ClientRuntime,
    method: crate::ports::HttpMethod,
    path: &str,
    params: BTreeMap<String, String>,
) -> Result<String> {
    let started = Instant::now();
    let operation = operation_name(method, path);
    info!(target: "ubaa::cgyy", feature = "cgyy", operation, method = method_name_value(method), path, "开始 Cgyy 请求");
    debug!(target: "ubaa::cgyy", feature = "cgyy", operation, parameter_keys = ?params.keys().collect::<Vec<_>>(), parameter_summary = ?safe_parameter_summary(&params), "构造 Cgyy 请求");
    for attempt in 0..2 {
        let access_token = match ensure_login(runtime).await {
            Ok(token) => token,
            Err(error) => {
                warn!(
                    target: "ubaa::cgyy",
                    feature = "cgyy",
                    route = ?runtime.mode(),
                    operation,
                    elapsed_ms = elapsed_millis(started),
                    error_code = ?error.code,
                    "Cgyy 业务登录失败"
                );
                return Err(error);
            }
        };
        let mut request =
            signed_request(runtime, method, path, params.clone(), Some(&access_token))?;
        if method == crate::ports::HttpMethod::Post {
            request.body = crate::upstream::encode_form(&params);
        }
        debug!(
            target: "ubaa::cgyy",
            feature = "cgyy",
            route = ?runtime.mode(),
            operation,
            attempt = attempt + 1,
            request_url = %safe_url(&request.url),
            body_len = request.body.len(),
            "发送 Cgyy HTTP 请求"
        );
        let response = runtime.request(request).await?;
        log_response(runtime, operation, &response);
        match check_business_response(&response, "场馆预约") {
            Ok(()) => {
                info!(target: "ubaa::cgyy", feature = "cgyy", operation, attempt = attempt + 1, elapsed_ms = elapsed_millis(started), "Cgyy 请求成功");
                return Ok(super::body(&response));
            }
            Err(error) if attempt == 0 && error.code == ErrorCode::AuthenticationRequired => {
                warn!(target: "ubaa::cgyy", feature = "cgyy", operation, attempt = attempt + 1, error_code = ?error.code, "Cgyy 业务会话失效，清理令牌并重试");
                runtime.feature_state().cgyy.clear();
            }
            Err(error) => {
                warn!(target: "ubaa::cgyy", feature = "cgyy", operation, attempt = attempt + 1, elapsed_ms = elapsed_millis(started), error_code = ?error.code, "Cgyy 请求失败");
                return Err(error);
            }
        }
    }
    unreachable!("场馆请求认证重试次数已耗尽")
}

/// 按冻结旧版 `LocalCgyyApi.requestJson` 的顺序检查响应。
/// Cgyy 上游曾出现 HTTP 状态与业务 `code` 不一致的响应，旧版以业务信封为准。
fn check_business_response(response: &crate::ports::HttpResponse, feature: &str) -> Result<()> {
    let text = super::body(response);
    if response.status == 401
        || is_sso_url(&response.final_url)
        || (text.contains("name=\"execution\"") && text.contains("username_password"))
    {
        debug!(target: "ubaa::cgyy", feature = "cgyy", response_status = response.status, auth_marker = true, "Cgyy 响应识别为认证失效");
        return Err(UbaaError::new(
            ErrorCode::AuthenticationRequired,
            ErrorKind::Authentication,
            false,
            format!("{feature}需要认证"),
        ));
    }
    let root = object(&text)?;
    let code = root.get("code").and_then(|value| {
        value
            .as_i64()
            .or_else(|| value.as_str()?.parse::<i64>().ok())
    });
    if code != Some(200) {
        warn!(target: "ubaa::cgyy", feature = "cgyy", response_status = response.status, business_code = ?code, "Cgyy 业务 code 非成功值");
        return Err(error(
            string(&root, "message").unwrap_or_else(|| "场馆预约请求失败".into()),
        ));
    }
    debug!(target: "ubaa::cgyy", feature = "cgyy", response_status = response.status, business_code = 200, "Cgyy 业务响应通过");
    Ok(())
}

fn operation_name(method: crate::ports::HttpMethod, path: &str) -> &'static str {
    match path {
        "/api/orders/mine" => "orders.list",
        path if path.starts_with("/api/orders/") && !path.contains("/lock/") => {
            "orders.detail_or_cancel"
        }
        "/api/orders/lock/code" => "orders.lock_code",
        "/api/front/website/venues" => "sites.list",
        "/api/reservation/day/info" => "day.info",
        "/api/codes" => "purposes.list",
        "/api/login" => "business_login.api",
        _ if method == crate::ports::HttpMethod::Post => "business.write",
        _ => "business.read",
    }
}

const fn method_name_value(method: crate::ports::HttpMethod) -> &'static str {
    match method {
        crate::ports::HttpMethod::Get => "GET",
        crate::ports::HttpMethod::Post => "POST",
    }
}

fn safe_parameter_summary(params: &BTreeMap<String, String>) -> BTreeMap<String, String> {
    params
        .iter()
        .map(|(key, value)| {
            let safe = matches!(
                key.as_str(),
                "page" | "size" | "reservationRoleId" | "venueSiteId" | "searchDate"
            );
            (
                key.clone(),
                if safe {
                    value.clone()
                } else {
                    format!("<存在，长度={}", value.len()) + ">"
                },
            )
        })
        .collect()
}

fn log_response(
    runtime: &crate::runtime::ClientRuntime,
    operation: &str,
    response: &crate::ports::HttpResponse,
) {
    let body = &response.body;
    debug!(
        target: "ubaa::cgyy",
        feature = "cgyy",
        route = ?runtime.mode(),
        operation,
        status = response.status,
        final_url = %safe_url(&response.final_url),
        body_len = body.len(),
        body_sha1 = %sha1_hex(body),
        content_type = ?response.headers.get("content-type").and_then(|values| values.first()),
        "收到 Cgyy 响应"
    );
}

fn safe_url(value: &str) -> String {
    url::Url::parse(value).map_or_else(
        |_| "<无效 URL>".into(),
        |parsed| {
            let host = parsed.host_str().unwrap_or("<无主机>");
            format!("{}://{}{}", parsed.scheme(), host, parsed.path())
        },
    )
}

fn sha1_hex(value: &[u8]) -> String {
    use sha1::{Digest, Sha1};
    use std::fmt::Write as _;
    let mut result = String::with_capacity(40);
    for byte in Sha1::digest(value) {
        write!(&mut result, "{byte:02x}").expect("写入 String 不会失败");
    }
    result
}

fn elapsed_millis(started: Instant) -> u64 {
    u64::try_from(started.elapsed().as_millis()).unwrap_or(u64::MAX)
}

fn is_sso_url(candidate: &str) -> bool {
    let direct =
        crate::connection::from_webvpn_url(candidate).unwrap_or_else(|_| candidate.to_owned());
    url::Url::parse(&direct)
        .ok()
        .and_then(|url| url.host_str().map(str::to_ascii_lowercase))
        .is_some_and(|host| host == "sso.buaa.edu.cn")
}

async fn get(
    runtime: &mut crate::runtime::ClientRuntime,
    path: &str,
    params: BTreeMap<String, String>,
) -> Result<String> {
    business_request(runtime, crate::ports::HttpMethod::Get, path, params).await
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
    // 冻结旧版在已有主会话后对动态用途接口使用 runCatching；请求或解析异常
    // 都回退到静态定义，而没有主会话仍由登录前置返回认证错误。
    super::require_session(runtime)?;
    match get(runtime, "/api/codes", BTreeMap::new()).await {
        Ok(body) => parse_purpose_types(&body).or_else(|_| Ok(fallback_purpose_types())),
        Err(_) => Ok(fallback_purpose_types()),
    }
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

/// 解析门锁码响应，仅保留是否存在数据的安全摘要。
pub fn parse_lock_code(body: &str) -> Result<CgyyLockCode> {
    let root = success_root(body)?;
    Ok(CgyyLockCode {
        available: !root.get("data").is_none_or(Value::is_null),
    })
}

/// 取消指定场馆预约订单。
pub(crate) async fn cancel_order(
    runtime: &mut crate::runtime::ClientRuntime,
    id: i32,
) -> Result<CgyyActionResult> {
    let body = business_request(
        runtime,
        crate::ports::HttpMethod::Post,
        &format!("/api/orders/new/cancel/{id}"),
        BTreeMap::new(),
    )
    .await?;
    parse_action_result(&body)
}

fn reservation_order_json(
    selections: &[crate::domain::CgyyReservationSelection],
) -> Result<String> {
    serde_json::to_string(selections).map_err(|_| error("预约时段无法编码"))
}

/// 构造冻结实现要求的预约提交表单。
#[must_use]
pub fn build_submit_form(
    request: &crate::domain::CgyyReservationSubmitRequest,
    token: &str,
    reservation_order_json: &str,
) -> BTreeMap<String, String> {
    let mut form = BTreeMap::new();
    form.insert("venueSiteId".into(), request.venue_site_id.to_string());
    form.insert("reservationDate".into(), request.reservation_date.clone());
    form.insert("reservationOrderJson".into(), reservation_order_json.into());
    form.insert("weekStartDate".into(), request.reservation_date.clone());
    form.insert("phone".into(), request.phone.trim().into());
    form.insert("theme".into(), request.theme.trim().into());
    form.insert("purposeType".into(), request.purpose_type.to_string());
    form.insert("joinerNum".into(), request.joiner_num.to_string());
    form.insert(
        "activityContent".into(),
        request.activity_content.trim().into(),
    );
    form.insert("joiners".into(), request.joiners.trim().into());
    form.insert(
        "isPhilosophySocialSciences".into(),
        if request.is_philosophy_social_sciences {
            "1"
        } else {
            "0"
        }
        .into(),
    );
    form.insert(
        "isOffSchoolJoiner".into(),
        if request.is_off_school_joiner {
            "1"
        } else {
            "0"
        }
        .into(),
    );
    form.insert(
        "captchaVerification".into(),
        request.captcha_verification.clone(),
    );
    form.insert("token".into(), token.into());
    form
}

/// 构造冻结验证码校验表单。
#[must_use]
pub fn build_captcha_check_form(point_json: &str, token: &str) -> BTreeMap<String, String> {
    [
        ("pointJson".into(), point_json.into()),
        ("token".into(), token.into()),
    ]
    .into_iter()
    .collect()
}

/// 提交场馆预约；验证码材料可由调用方提供或由 Core 自动获取并校验。
pub(crate) async fn submit_reservation(
    runtime: &mut crate::runtime::ClientRuntime,
    mut request: crate::domain::CgyyReservationSubmitRequest,
) -> Result<crate::domain::CgyyReservationResult> {
    validate_submit_request(&request)?;
    let day = get_day_info(runtime, request.venue_site_id, &request.reservation_date).await?;
    let token = day
        .reservation_token
        .ok_or_else(|| error("预约上下文 token 缺失，请刷新后重试"))?;
    let space_id = request.selections[0].space_id;
    if request
        .selections
        .iter()
        .any(|item| item.space_id != space_id)
    {
        return Err(error("同次预约只能选择同一房间的时段"));
    }
    let space = day
        .spaces
        .iter()
        .find(|item| item.space_id == space_id)
        .ok_or_else(|| error("所选房间不存在或已失效"))?;
    for selection in &request.selections {
        let slot = space
            .slots
            .iter()
            .find(|slot| slot.time_id == selection.time_id)
            .ok_or_else(|| error("所选时段不存在或已失效"))?;
        if !slot.is_reservable {
            return Err(error("所选时段已不可预约，请刷新后重试"));
        }
    }
    let order_json = reservation_order_json(&request.selections)?;
    let context_form = [
        ("venueSiteId".into(), request.venue_site_id.to_string()),
        ("reservationDate".into(), request.reservation_date.clone()),
        ("weekStartDate".into(), request.reservation_date.clone()),
        ("reservationOrderJson".into(), order_json.clone()),
        ("token".into(), token.clone()),
    ]
    .into_iter()
    .collect();
    let context_body = business_request(
        runtime,
        crate::ports::HttpMethod::Post,
        "/api/reservation/order/info",
        context_form,
    )
    .await?;
    data(&context_body)?;

    let external = !request.captcha_verification.trim().is_empty()
        && !request.captcha_point_json.trim().is_empty()
        && !request.captcha_token.trim().is_empty();
    if external {
        check_captcha(runtime, &request).await?;
        return submit_order(runtime, &request, &token, &order_json).await;
    }
    let mut last_error = None;
    for _ in 0..3 {
        match prepare_captcha_once(runtime, &mut request).await {
            Ok(()) => match submit_order(runtime, &request, &token, &order_json).await {
                Ok(result) => return Ok(result),
                Err(error) => last_error = Some(error),
            },
            Err(error) => last_error = Some(error),
        }
    }
    Err(last_error.unwrap_or_else(|| error("验证码处理失败")))
}

async fn submit_order(
    runtime: &mut crate::runtime::ClientRuntime,
    request: &crate::domain::CgyyReservationSubmitRequest,
    token: &str,
    order_json: &str,
) -> Result<crate::domain::CgyyReservationResult> {
    let form = build_submit_form(request, token, order_json);
    let body = business_request(
        runtime,
        crate::ports::HttpMethod::Post,
        "/api/reservation/order/submit",
        form,
    )
    .await?;
    let root = object(&body)?;
    let message = string(&root, "message").unwrap_or_else(|| "预约提交完成".into());
    let value = data(&body)?;
    let order = value
        .as_object()
        .and_then(|map| map.get("orderInfo"))
        .and_then(Value::as_object)
        .map(parse_order);
    Ok(crate::domain::CgyyReservationResult {
        success: true,
        message,
        order,
    })
}

fn validate_submit_request(request: &crate::domain::CgyyReservationSubmitRequest) -> Result<()> {
    if request.venue_site_id <= 0 || request.reservation_date.trim().is_empty() {
        return Err(error("场馆站点和预约日期不能为空"));
    }
    if request.selections.is_empty()
        || request
            .selections
            .iter()
            .any(|item| item.space_id <= 0 || item.time_id <= 0)
    {
        return Err(error("至少选择一个有效的预约时段"));
    }
    let has_external = !request.captcha_verification.trim().is_empty()
        || !request.captcha_point_json.trim().is_empty();
    let external = !request.captcha_verification.trim().is_empty()
        && !request.captcha_point_json.trim().is_empty()
        && !request.captcha_token.trim().is_empty();
    let has_solver_input = request
        .captcha_secret_key
        .as_deref()
        .is_some_and(|value| !value.is_empty())
        || request
            .captcha_original_image_base64
            .as_deref()
            .is_some_and(|value| !value.is_empty())
        || request
            .captcha_jigsaw_image_base64
            .as_deref()
            .is_some_and(|value| !value.is_empty());
    let has_captcha_token = !request.captcha_token.trim().is_empty();
    let solver_input = request
        .captcha_secret_key
        .as_deref()
        .is_some_and(|value| !value.is_empty())
        && request
            .captcha_original_image_base64
            .as_deref()
            .is_some_and(|value| !value.is_empty())
        && !request.captcha_token.trim().is_empty()
        && !has_external;
    if (has_external && !external)
        || (has_solver_input && !solver_input)
        || (external && has_solver_input)
        || (!external && !solver_input && (has_external || has_solver_input || has_captcha_token))
    {
        return Err(error("验证码材料不完整或相互冲突"));
    }
    if !external && !solver_input {
        return Ok(());
    }
    Ok(())
}

async fn prepare_captcha_once(
    runtime: &mut crate::runtime::ClientRuntime,
    request: &mut crate::domain::CgyyReservationSubmitRequest,
) -> Result<()> {
    let challenge = if let (Some(secret_key), Some(original), Some(jigsaw)) = (
        request.captcha_secret_key.as_deref(),
        request.captcha_original_image_base64.as_deref(),
        request.captcha_jigsaw_image_base64.as_deref(),
    ) {
        CgyyCaptchaChallenge {
            secret_key: secret_key.to_owned(),
            token: request.captcha_token.clone(),
            original_image_base64: original.to_owned(),
            jigsaw_image_base64: jigsaw.to_owned(),
        }
    } else {
        get_captcha(runtime).await?
    };
    if challenge.token.is_empty() {
        return Err(error("验证码挑战令牌缺失"));
    }
    let original = decode_captcha_image(&challenge.original_image_base64)?;
    let jigsaw = decode_captcha_image(&challenge.jigsaw_image_base64)?;
    let offset = solve_captcha_offset(&original, &jigsaw)?;
    let (point_json, verification) =
        build_captcha_solution(&challenge.secret_key, &challenge.token, offset)?;
    request.captcha_point_json = point_json;
    request.captcha_token = challenge.token;
    request.captcha_verification = verification;
    check_captcha(runtime, request).await
}

async fn get_captcha(runtime: &mut crate::runtime::ClientRuntime) -> Result<CgyyCaptchaChallenge> {
    let now = timestamp_millis()?;
    let body = get(runtime, "/api/captcha/get", build_captcha_params(now)).await?;
    parse_captcha_challenge(&body)
}

fn decode_captcha_image(value: &str) -> Result<Vec<u8>> {
    let encoded = value.split_once("base64,").map_or(value, |(_, data)| data);
    base64::engine::general_purpose::STANDARD
        .decode(encoded)
        .map_err(|_| error("验证码图片编码无效"))
}

async fn check_captcha(
    runtime: &mut crate::runtime::ClientRuntime,
    request: &crate::domain::CgyyReservationSubmitRequest,
) -> Result<()> {
    let form = build_captcha_check_form(&request.captcha_point_json, &request.captcha_token);
    let body = business_request(
        runtime,
        crate::ports::HttpMethod::Post,
        "/api/captcha/check",
        form,
    )
    .await?;
    if data(&body)?.get("success").and_then(Value::as_bool) != Some(true) {
        return Err(error("验证码校验失败"));
    }
    Ok(())
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

fn success_root(body: &str) -> Result<Map<String, Value>> {
    let root = object(body)?;
    let code = root.get("code").and_then(|value| {
        value
            .as_i64()
            .or_else(|| value.as_str()?.parse::<i64>().ok())
    });
    if code != Some(200) {
        let message = string(&root, "message").unwrap_or_else(|| "场馆预约请求失败".into());
        return Err(error(message));
    }
    Ok(root)
}

fn data(body: &str) -> Result<Value> {
    let root = success_root(body)?;
    Ok(root.get("data").cloned().unwrap_or(Value::Null))
}

fn string(map: &Map<String, Value>, key: &str) -> Option<String> {
    let value = map.get(key)?;
    value
        .as_str()
        .map(str::to_owned)
        .or_else(|| value.as_i64().map(|number| number.to_string()))
        .or_else(|| value.as_u64().map(|number| number.to_string()))
        .or_else(|| value.as_f64().map(|number| number.to_string()))
        .or_else(|| value.as_bool().map(|boolean| boolean.to_string()))
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
        .or_else(|| {
            value
                .as_object()
                .and_then(|map| map.get("content"))
                .and_then(Value::as_array)
        })
        .ok_or_else(|| error("场馆站点响应结构无效"))?;
    let mut flattened = Vec::new();
    for item in values {
        let Some(map) = item.as_object() else {
            continue;
        };
        if let Some(site_list) = map.get("siteList").and_then(Value::as_array) {
            for site in site_list {
                let Some(site_map) = site.as_object() else {
                    continue;
                };
                let mut merged = site_map.clone();
                for key in ["venueName", "campusName"] {
                    if !merged.contains_key(key)
                        && let Some(value) = map.get(key)
                    {
                        merged.insert(key.to_owned(), value.clone());
                    }
                }
                flattened.push(merged);
            }
        } else {
            flattened.push(map.clone());
        }
    }
    Ok(flattened
        .iter()
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
    let root = success_root(body)?
        .get("data")
        .and_then(Value::as_object)
        .cloned()
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
        .map(|space| {
            let mut slots: Vec<_> = time_slots
                .iter()
                .filter_map(|slot| {
                    space
                        .get(&slot.id.to_string())
                        .and_then(Value::as_object)
                        .map(|raw| parse_slot(slot.id, raw))
                })
                .collect();
            slots.sort_by_key(|slot| slot.time_id);
            CgyySpaceAvailability {
                space_id: int(space, "id").unwrap_or_default(),
                space_name: string(space, "spaceName").unwrap_or_default(),
                venue_site_id: int(space, "venueSiteId").unwrap_or(venue_site_id),
                venue_space_group_id: int(space, "venueSpaceGroupId"),
                slots,
            }
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
        reservation_token: string(&root, "token"),
        reservation_total_num: int(&root, "reservationTotalNum"),
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
        .cloned()
        .or_else(|| value.is_null().then(Map::new))
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
        total_elements: int(&root, "totalElements").unwrap_or_default(),
        total_pages: int(&root, "totalPages").unwrap_or_default(),
        size: int(&root, "size").unwrap_or(20),
        number: int(&root, "number").unwrap_or_default(),
    })
}

/// 解析单个预约订单详情。
pub fn parse_order_detail(body: &str) -> Result<CgyyOrder> {
    let value = data(body)?;
    value
        .as_object()
        .cloned()
        .or_else(|| value.is_null().then(Map::new))
        .map(|root| parse_order(&root))
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
    use super::{
        build_captcha_check_form, build_captcha_params, build_captcha_solution, build_submit_form,
        check_business_response, parse_action_result, parse_captcha_challenge, parse_sites, sign,
        signed_request, validate_submit_request,
    };
    use crate::domain::{CgyyReservationSelection, CgyyReservationSubmitRequest, ConnectionMode};
    use crate::ports::{HttpMethod, HttpRequest, HttpResponse, HttpTransport};
    use crate::runtime::ClientRuntime;
    use crate::session::FileSessionStore;
    use async_trait::async_trait;

    #[test]
    fn 签名排除冻结审计字段() {
        let timestamp = 1_710_000_000_000;
        let mut noisy = std::collections::BTreeMap::from([
            ("a".to_owned(), "1".to_owned()),
            ("b".to_owned(), "2".to_owned()),
            ("id".to_owned(), "123".to_owned()),
            ("creator".to_owned(), "operator".to_owned()),
            ("gmtModified".to_owned(), "today".to_owned()),
        ]);
        let clean = std::collections::BTreeMap::from([
            ("a".to_owned(), "1".to_owned()),
            ("b".to_owned(), "2".to_owned()),
        ]);
        assert_eq!(
            sign("/api/test", &clean, timestamp),
            sign("/api/test", &noisy, timestamp)
        );
        noisy.insert("_rowKey".to_owned(), "row".to_owned());
        assert_eq!(
            sign("/api/test", &clean, timestamp),
            sign("/api/test", &noisy, timestamp)
        );
    }

    #[test]
    fn 解析取消订单成功消息() {
        let result = parse_action_result(r#"{"code":200,"message":"取消成功","data":null}"#)
            .expect("应解析成功");
        assert_eq!(result.message, "取消成功");
        assert!(result.order.is_none());
    }

    #[test]
    fn 业务响应按旧版允许状态码异常但业务代码成功() {
        let response = HttpResponse::new(
            500,
            "https://cgyy.buaa.edu.cn/venue-zhjs-server/api/orders/mine",
            br#"{"code":200,"data":{"content":[]}}"#.to_vec(),
        );
        assert!(check_business_response(&response, "订单").is_ok());
    }

    #[test]
    fn 场馆站点数字原语按冻结实现转为文本() {
        let body = r#"{"code":200,"data":[{"id":7,"siteName":8,"venueName":9,"campusName":10}]}"#;
        let sites = parse_sites(body).expect("解析站点");
        assert_eq!(sites[0].site_name, "8");
        assert_eq!(sites[0].venue_name, "9");
        assert_eq!(sites[0].campus_name, "10");
    }

    #[test]
    fn 预约提交表单匹配冻结字段() {
        let request = CgyyReservationSubmitRequest {
            venue_site_id: 7,
            reservation_date: "2026-08-28".into(),
            selections: vec![CgyyReservationSelection {
                space_id: 11,
                time_id: 3,
                venue_space_group_id: None,
            }],
            phone: "010-00000000".into(),
            theme: "测试".into(),
            purpose_type: 1,
            joiner_num: 2,
            activity_content: "内容".into(),
            joiners: "甲,乙".into(),
            is_philosophy_social_sciences: false,
            is_off_school_joiner: true,
            captcha_verification: "verification".into(),
            captcha_point_json: "[{\"x\":1,\"y\":2}]".into(),
            captcha_token: "captcha-token".into(),
            captcha_secret_key: None,
            captcha_original_image_base64: None,
            captcha_jigsaw_image_base64: None,
        };
        let form = build_submit_form(&request, "token", "[{\"spaceId\":11,\"timeId\":3}]");
        assert_eq!(form.get("venueSiteId").map(String::as_str), Some("7"));
        assert_eq!(
            form.get("reservationOrderJson").map(String::as_str),
            Some("[{\"spaceId\":11,\"timeId\":3}]")
        );
        assert_eq!(
            form.get("isPhilosophySocialSciences").map(String::as_str),
            Some("0")
        );
        assert_eq!(form.get("isOffSchoolJoiner").map(String::as_str), Some("1"));
        assert_eq!(
            form.get("captchaVerification").map(String::as_str),
            Some("verification")
        );
        let captcha = build_captcha_check_form("points", "challenge");
        assert_eq!(captcha.get("pointJson").map(String::as_str), Some("points"));
        assert_eq!(captcha.get("token").map(String::as_str), Some("challenge"));
    }

    #[test]
    fn 验证码挑战请求参数和响应字段匹配冻结协议() {
        let params = build_captcha_params(1234);
        assert_eq!(
            params.get("captchaType").map(String::as_str),
            Some("blockPuzzle")
        );
        assert_eq!(
            params.get("clientUid").map(String::as_str),
            Some("slider-1234")
        );
        assert_eq!(params.get("ts").map(String::as_str), Some("1234"));

        let challenge = parse_captcha_challenge(
            r#"{"code":200,"data":{"success":true,"repData":{"secretKey":"key","token":"token","originalImageBase64":"bg","jigsawImageBase64":"piece"}}}"#,
        )
        .expect("应解析验证码挑战");
        assert_eq!(challenge.secret_key, "key");
        assert_eq!(challenge.token, "token");
        assert_eq!(challenge.original_image_base64, "bg");
        assert_eq!(challenge.jigsaw_image_base64, "piece");
    }

    #[test]
    fn web_vpn模式下场馆签名请求使用_webvpn地址() {
        let root = std::env::temp_dir().join(format!("ubaa-cgyy-url-{}", std::process::id()));
        let runtime = ClientRuntime::new(
            ConnectionMode::WebVpn,
            NoNetworkTransport,
            FileSessionStore::new(&root).unwrap(),
        )
        .unwrap();
        let request = signed_request(
            &runtime,
            HttpMethod::Get,
            "/api/front/website/venues",
            std::collections::BTreeMap::new(),
            Some("token-safe"),
        )
        .unwrap();
        let url = url::Url::parse(&request.url).unwrap();
        assert_eq!(url.host_str(), Some("d.buaa.edu.cn"));
        let direct = crate::connection::from_webvpn_url(&request.url).unwrap();
        assert_eq!(
            url::Url::parse(&direct).unwrap().host_str(),
            Some("cgyy.buaa.edu.cn")
        );
        let _ = std::fs::remove_dir_all(root);
    }

    struct NoNetworkTransport;

    #[async_trait]
    impl HttpTransport for NoNetworkTransport {
        async fn execute(&self, _request: HttpRequest) -> crate::error::Result<HttpResponse> {
            panic!("请求构造测试不应访问网络");
        }
    }

    #[test]
    fn 验证码位移凭据使用冻结_aes_ecb_pkcs7_向量() {
        let (point, verification) =
            build_captcha_solution("0123456789abcdef", "token", 12).expect("应生成验证码凭据");
        assert_eq!(point, "//vojImUw+QfCP7LYCytFg==");
        assert!(!verification.is_empty());
    }

    #[test]
    fn 验证码位移求解拒绝非法图片() {
        assert!(super::solve_captcha_offset(b"not-an-image", b"not-an-image").is_err());
    }

    #[test]
    fn 验证码位移求解匹配内存_png_图案() {
        use image::{DynamicImage, ImageFormat, Rgba, RgbaImage};
        use std::io::Cursor;

        fn encode(image: RgbaImage) -> Vec<u8> {
            let mut output = Cursor::new(Vec::new());
            DynamicImage::ImageRgba8(image)
                .write_to(&mut output, ImageFormat::Png)
                .expect("测试图片应可编码");
            output.into_inner()
        }

        let mut background = RgbaImage::from_pixel(64, 32, Rgba([255, 255, 255, 255]));
        let mut piece = RgbaImage::from_pixel(12, 12, Rgba([255, 255, 255, 0]));
        for y in 0..12 {
            for x in 0..12 {
                let border = x == 0 || y == 0 || x == 11 || y == 11;
                if border {
                    piece.put_pixel(x, y, Rgba([0, 0, 0, 255]));
                    background.put_pixel(30 + x, 10 + y, Rgba([0, 0, 0, 255]));
                }
            }
        }
        let offset = super::solve_captcha_offset(&encode(background), &encode(piece))
            .expect("应匹配测试滑块");
        // 算法匹配的是白色背景到黑色边框的边界，因此横坐标为 29。
        assert_eq!(offset, 29);
    }

    #[test]
    fn 预约请求省略验证码时允许内部挑战流程() {
        let request = CgyyReservationSubmitRequest {
            venue_site_id: 4,
            reservation_date: "2026-03-29".into(),
            selections: vec![CgyyReservationSelection {
                space_id: 6,
                time_id: 242,
                venue_space_group_id: None,
            }],
            phone: "010-00000000".into(),
            theme: "测试预约".into(),
            purpose_type: 1,
            joiner_num: 1,
            activity_content: "测试内容".into(),
            joiners: "测试人员".into(),
            is_philosophy_social_sciences: false,
            is_off_school_joiner: false,
            ..Default::default()
        };

        assert!(validate_submit_request(&request).is_ok());
    }
}
