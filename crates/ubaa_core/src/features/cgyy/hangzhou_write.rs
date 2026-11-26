//! 杭州空间预约写入：用户亲手完成的滑块验证码、提交预约、0 元确认与取消。
//!
//! 依据 `docs/protocol/parity/cgyy.md` 杭州专项记录（2026-11-25 账号本人浏览器实录，
//! 只记录了方法、路径、字段名与响应结构）：
//!
//! 1. `GET /api/reservation/day/info` 复核时段资格；
//! 2. `GET /api/captcha/get` → 用户拖动滑块 → `POST /api/captcha/check`（`pointJson`、`token`）；
//! 3. `POST /api/reservation/order/submit`，表单为 `captchaVerification`、`captchaToken`、
//!    `reservationOrderJson`、`reservationDate`、`weekStartDate`、`reservationType`、
//!    `orderPrice`、`orderPin`、`venueSiteId`、`phone`；返回 `data.{id,tradeNo,...}`；
//! 4. 订单进入 10 分钟待支付，`GET /api/venue/finances/order/detail` 确认 `payFee == 0` 后，
//!    `POST /api/venue/finances/order/pay`（`venueTradeNo`、`isApp=0`）完成 0 元确认；
//! 5. 取消：`GET /api/orders/cancel_tip`，再 `POST /api/venue/finances/order/cancel`
//!    （`venueTradeNo`、`handleReason`）。
//!
//! 验证码不由程序求解：位移来自用户拖动；`orderPin` 加密的是用户真实点击坐标。
//! 写请求一律不自动重试。

use std::collections::BTreeMap;

use aes::Aes128;
use cipher::{BlockModeEncrypt, KeyIvInit, block_padding::Pkcs7};
use serde_json::{Map, Value};

use crate::domain::{
    ActionEligibility, CgyyReservationSelection, HangzhouCgyyCancelPreflight,
    HangzhouCgyyCancelRequest, HangzhouCgyyCancelResult, HangzhouCgyyCaptchaChallenge,
    HangzhouCgyyReservationReceipt, HangzhouCgyyReservationRequest,
};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::{HttpMethod, HttpResponse};
use crate::runtime::ClientRuntime;

use super::auth::{business_request_at, ensure_login_at, get_at};
use super::captcha::{build_captcha_check_form, build_captcha_params, parse_captcha_challenge};
use super::crypto::build_captcha_solution_at;
use super::http::{log_response, signed_request_at};
use super::parser::{data, parse_day_context};
use super::read::day_body;
use super::sign::timestamp_millis;
use super::site::CgyySite;

const SITE: CgyySite = CgyySite::Hangzhou;
/// 杭州前端 `keySetPassword` 的 AES-128-CBC 公开常量（站点配置 `k`、`v`）。
const PIN_KEY: &[u8; 16] = b"c1h2i5n6g2o2k4a7";
const PIN_IV: &[u8; 16] = b"C2H3I4N5G2O3K1E4";
/// `RESERVATION_TYPE.COMMON`。
const RESERVATION_TYPE_COMMON: &str = "-1";
const MAX_REASON_CHARS: usize = 200;

/// 取一张新的滑块验证码交给用户拖动。
pub(crate) async fn hangzhou_captcha(
    runtime: &mut ClientRuntime,
) -> Result<HangzhouCgyyCaptchaChallenge> {
    super::super::hzsso::require_direct_route(runtime)?;
    let now = timestamp_millis()?;
    let body = get_at(runtime, SITE, "/api/captcha/get", build_captcha_params(now)).await?;
    let challenge = parse_captcha_challenge(&body)?;
    Ok(HangzhouCgyyCaptchaChallenge {
        token: challenge.token,
        secret_key: challenge.secret_key,
        original_image_base64: strip_data_url(&challenge.original_image_base64),
        jigsaw_image_base64: strip_data_url(&challenge.jigsaw_image_base64),
    })
}

/// 复核资格 → 校验用户滑块 → 提交一次 → 确认 0 元订单。
pub(crate) async fn hangzhou_submit_reservation(
    runtime: &mut ClientRuntime,
    request: HangzhouCgyyReservationRequest,
) -> Result<HangzhouCgyyReservationReceipt> {
    super::super::hzsso::require_direct_route(runtime)?;
    validate_request(&request)?;
    let week_start_date = preflight(runtime, &request).await?;

    let input = &request.user_input;
    let (point_json, verification) = build_captcha_solution_at(
        &input.captcha_secret_key,
        &input.captcha_token,
        input.slider_offset_x,
    )?;
    let check = business_request_at(
        runtime,
        SITE,
        HttpMethod::Post,
        "/api/captcha/check",
        build_captcha_check_form(&point_json, &input.captcha_token),
    )
    .await?;
    if data(&check)?.get("success").and_then(Value::as_bool) != Some(true) {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            true,
            "滑块位置不对，请重新拖动验证码",
        )
        .with_diagnostic("captcha", "check_rejected"));
    }

    let form = submit_form(&request, &week_start_date, &verification);
    let root = send_write(
        runtime,
        "/api/reservation/order/submit",
        form,
        "reservation.submit",
    )
    .await
    .map_err(|error| error.with_diagnostic("hz_write", "submit"))?;
    let order = root
        .get("data")
        .and_then(Value::as_object)
        .ok_or_else(submit_unknown)?;
    let trade_no = order
        .get("tradeNo")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
        .ok_or_else(submit_unknown)?;
    let receipt = HangzhouCgyyReservationReceipt {
        order_id: order.get("id").and_then(Value::as_i64).unwrap_or_default(),
        trade_no: trade_no.clone(),
        reservation_start_date: text(order, "reservationStartDate"),
        reservation_end_date: text(order, "reservationEndDate"),
    };

    confirm_free_order(runtime, &trade_no).await?;
    Ok(receipt)
}

/// 取消前读取网页同款提醒。
pub(crate) async fn hangzhou_preflight_cancel(
    runtime: &mut ClientRuntime,
    request: &HangzhouCgyyCancelRequest,
) -> Result<HangzhouCgyyCancelPreflight> {
    super::super::hzsso::require_direct_route(runtime)?;
    let request = normalize_cancel(request)?;
    let body = get_at(runtime, SITE, "/api/orders/cancel_tip", BTreeMap::new()).await?;
    let tip = data(&body)?
        .get("tip")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|tip| !tip.is_empty())
        .map(str::to_owned);
    Ok(HangzhouCgyyCancelPreflight {
        trade_no: request.trade_no,
        tip,
    })
}

/// 只发送一次取消请求。
pub(crate) async fn hangzhou_cancel_order(
    runtime: &mut ClientRuntime,
    request: HangzhouCgyyCancelRequest,
) -> Result<HangzhouCgyyCancelResult> {
    let preflight = hangzhou_preflight_cancel(runtime, &request).await?;
    let request = normalize_cancel(&request)?;
    let form = [
        ("venueTradeNo".into(), preflight.trade_no),
        ("handleReason".into(), request.reason),
    ]
    .into_iter()
    .collect();
    send_write(
        runtime,
        "/api/venue/finances/order/cancel",
        form,
        "orders.cancel",
    )
    .await
    .map_err(|error| {
        if error.code == ErrorCode::OutcomeUnknown {
            UbaaError::outcome_unknown(
                "杭州预约取消请求已发送，结果未知，请刷新“我的预约”后再决定是否重试",
            )
        } else {
            error
        }
    })?;
    Ok(HangzhouCgyyCancelResult {
        success: true,
        message: "已取消杭州空间预约".into(),
    })
}

const MAX_SELECTIONS: usize = 48;

fn validate_request(request: &HangzhouCgyyReservationRequest) -> Result<()> {
    if request.venue_site_id <= 0 || request.reservation_date.trim().is_empty() {
        return Err(invalid_input("场地和预约日期不能为空"));
    }
    // 官网（BUAA_H3I）不限两段、也不要求相邻，单次上限由站点配置在服务端决定；
    // 这里只挡掉空选择和明显异常的数量（一天的时段数不会超过 48）。
    if !(1..=MAX_SELECTIONS).contains(&request.selections.len())
        || request
            .selections
            .iter()
            .any(|item| item.space_id <= 0 || item.time_id <= 0)
    {
        return Err(invalid_input("请选择有效时段"));
    }
    let first = &request.selections[0];
    if request
        .selections
        .iter()
        .any(|item| item.space_id != first.space_id)
    {
        return Err(invalid_input("同次预约必须选择同一房间"));
    }
    let mut times: Vec<_> = request.selections.iter().map(|item| item.time_id).collect();
    times.sort_unstable();
    times.dedup();
    if times.len() != request.selections.len() {
        return Err(invalid_input("同次预约不能重复选择时段"));
    }
    let phone = request.phone.trim();
    if phone.len() != 11 || !phone.starts_with('1') || !phone.bytes().all(|b| b.is_ascii_digit()) {
        return Err(invalid_input("请填写正确的 11 位手机号"));
    }
    let input = &request.user_input;
    if input.captcha_token.trim().is_empty()
        || input.captcha_secret_key.trim().is_empty()
        || !input.slider_offset_x.is_finite()
        || input.slider_offset_x < 0.0
    {
        return Err(invalid_input("请先完成滑块验证码"));
    }
    Ok(())
}

/// 重新读取当天时段，确认免费、时段可约且相邻；返回网页同款 `weekStartDate`。
async fn preflight(
    runtime: &mut ClientRuntime,
    request: &HangzhouCgyyReservationRequest,
) -> Result<String> {
    let body = day_body(
        runtime,
        SITE,
        request.venue_site_id,
        &request.reservation_date,
    )
    .await?;
    let root = data(&body)?;
    if root.get("isFee").and_then(Value::as_i64).unwrap_or(0) != 0 {
        return Err(invalid_input("该场地需要付费，UBAA 只支持免费场地预约"));
    }
    let context = parse_day_context(&body, request.venue_site_id, &request.reservation_date)?;
    if !context.requested_date_exact {
        return Err(changed("预约日期已不在可约范围内，请刷新后重试"));
    }
    let space_id = request.selections[0].space_id;
    let spaces: Vec<_> = context
        .info
        .spaces
        .iter()
        .filter(|space| space.space_id == space_id)
        .collect();
    let [space] = spaces.as_slice() else {
        return Err(changed("预约房间已变化，请刷新后重试"));
    };
    for selection in &request.selections {
        let slots: Vec<_> = space
            .slots
            .iter()
            .filter(|slot| slot.time_id == selection.time_id)
            .collect();
        let [slot] = slots.as_slice() else {
            return Err(changed("预约时段已变化，请刷新后重试"));
        };
        if slot.reservation_eligibility != ActionEligibility::Allowed {
            return Err(UbaaError::new(
                ErrorCode::InvalidInput,
                ErrorKind::Input,
                true,
                "所选时段已不可预约，请刷新后重新选择",
            ));
        }
        if slot.reservation_target.is_none() {
            return Err(changed("预约时段缺少必要字段"));
        }
    }
    // `reservationTotalNum` 在官网是单个时段可容纳的人数（`alreadyNum < reservationTotalNum`
    // 才可选），不是单次可选的时段数，所以不在这里限制数量；数量上限交给服务端。
    Ok(root
        .get("reservationDateList")
        .and_then(Value::as_array)
        .and_then(|dates| dates.first())
        .and_then(Value::as_str)
        .unwrap_or(&request.reservation_date)
        .to_owned())
}

fn submit_form(
    request: &HangzhouCgyyReservationRequest,
    week_start_date: &str,
    verification: &str,
) -> BTreeMap<String, String> {
    let input = &request.user_input;
    let mut form = BTreeMap::new();
    form.insert("captchaVerification".into(), verification.to_owned());
    form.insert("captchaToken".into(), input.captcha_token.clone());
    form.insert(
        "reservationOrderJson".into(),
        reservation_order_json(&request.selections),
    );
    form.insert("reservationDate".into(), request.reservation_date.clone());
    form.insert("weekStartDate".into(), week_start_date.to_owned());
    form.insert("reservationType".into(), RESERVATION_TYPE_COMMON.into());
    form.insert("orderPrice".into(), "0".into());
    form.insert("orderPin".into(), order_pin(input.tap_x, input.tap_y));
    form.insert("venueSiteId".into(), request.venue_site_id.to_string());
    form.insert("phone".into(), request.phone.trim().to_owned());
    form
}

/// 网页按 `"timeId_spaceId_dateIndex"` 拆分后提交字符串形式的 `spaceId`/`timeId`。
pub(crate) fn reservation_order_json(selections: &[CgyyReservationSelection]) -> String {
    let items: Vec<Value> = selections
        .iter()
        .map(|item| {
            let mut map = Map::new();
            map.insert("spaceId".into(), Value::String(item.space_id.to_string()));
            map.insert("timeId".into(), Value::String(item.time_id.to_string()));
            Value::Object(map)
        })
        .collect();
    Value::Array(items).to_string()
}

/// 网页 `keySetPassword("clientX,clientY")`：AES-128-CBC/PKCS#7，小写十六进制密文。
pub(crate) fn order_pin(tap_x: i32, tap_y: i32) -> String {
    let plain = format!("{tap_x},{tap_y}");
    let bytes = cbc::Encryptor::<Aes128>::new(PIN_KEY.into(), PIN_IV.into())
        .encrypt_padded_vec::<Pkcs7>(plain.as_bytes());
    hex::encode(bytes)
}

/// 0 元订单必须调用一次 `order/pay` 才会生效；有费用时不支付，交给用户在网页处理。
async fn confirm_free_order(runtime: &mut ClientRuntime, trade_no: &str) -> Result<()> {
    let params = [("venueTradeNo".into(), trade_no.to_owned())]
        .into_iter()
        .collect();
    let detail = get_at(runtime, SITE, "/api/venue/finances/order/detail", params)
        .await
        .map_err(|_| unconfirmed(trade_no))?;
    let fee = data(&detail)
        .ok()
        .and_then(|value| value.get("payFee").and_then(Value::as_f64));
    match fee {
        Some(fee) if fee.abs() < f64::EPSILON => {}
        Some(_) => {
            return Err(UbaaError::new(
                ErrorCode::BusinessRejected,
                ErrorKind::Upstream,
                false,
                format!(
                    "预约已提交（订单 {trade_no}），但场馆要求付费；UBAA 不代为支付，未支付订单会在约 10 分钟后自动关闭"
                ),
            ));
        }
        None => return Err(unconfirmed(trade_no)),
    }
    let form = [
        ("venueTradeNo".into(), trade_no.to_owned()),
        ("isApp".into(), "0".into()),
    ]
    .into_iter()
    .collect();
    send_write(
        runtime,
        "/api/venue/finances/order/pay",
        form,
        "orders.confirm_free",
    )
    .await
    .map_err(|_| unconfirmed(trade_no))?;
    Ok(())
}

/// 签名后只发送一次非幂等 POST；`code != 200` 为业务拒绝，其余不确定情况为结果未知。
async fn send_write(
    runtime: &mut ClientRuntime,
    path: &str,
    form: BTreeMap<String, String>,
    operation: &str,
) -> Result<Map<String, Value>> {
    let access_token = ensure_login_at(runtime, SITE).await?;
    let mut request = signed_request_at(
        runtime,
        SITE,
        HttpMethod::Post,
        path,
        form.clone(),
        Some(&access_token),
    )?;
    request.body = crate::upstream::encode_form(&form);
    let expected_final_url = request.url.clone();
    let response = runtime.request_non_idempotent(request).await?;
    log_response(runtime, operation, &response);
    parse_write_root(&response, &expected_final_url)
}

fn parse_write_root(
    response: &HttpResponse,
    expected_final_url: &str,
) -> Result<Map<String, Value>> {
    let unknown = || {
        UbaaError::outcome_unknown(
            "杭州空间预约请求已发送，结果未知，请先刷新“我的预约”再决定是否重试",
        )
        .with_response(&response.body, Some(response.status))
    };
    if response.status != 200 || response.final_url != expected_final_url {
        return Err(unknown());
    }
    let root = serde_json::from_slice::<Value>(&response.body)
        .ok()
        .and_then(|value| value.as_object().cloned())
        .ok_or_else(unknown)?;
    match root.get("code").and_then(Value::as_i64) {
        Some(200) => Ok(root),
        Some(_) => {
            let message = root
                .get("message")
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|message| !message.is_empty())
                .unwrap_or("场馆系统拒绝了该请求");
            Err(
                UbaaError::business_rejected(message.to_owned()).with_business_response(
                    &response.body,
                    Some(response.status),
                    "code",
                ),
            )
        }
        None => Err(unknown()),
    }
}

fn normalize_cancel(request: &HangzhouCgyyCancelRequest) -> Result<HangzhouCgyyCancelRequest> {
    let trade_no = request.trade_no.trim();
    if trade_no.is_empty() || !trade_no.chars().all(|c| c.is_ascii_alphanumeric()) {
        return Err(invalid_input("订单号无效"));
    }
    let reason = request.reason.trim();
    if reason.is_empty() {
        return Err(invalid_input("请填写取消原因"));
    }
    if reason.chars().count() > MAX_REASON_CHARS {
        return Err(invalid_input("取消原因不能超过 200 字"));
    }
    Ok(HangzhouCgyyCancelRequest {
        trade_no: trade_no.to_owned(),
        reason: reason.to_owned(),
    })
}

fn strip_data_url(value: &str) -> String {
    value
        .split_once("base64,")
        .map_or(value, |(_, data)| data)
        .to_owned()
}

fn text(map: &Map<String, Value>, key: &str) -> Option<String> {
    map.get(key)
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
}

#[track_caller]
fn invalid_input(message: &'static str) -> UbaaError {
    UbaaError::new(ErrorCode::InvalidInput, ErrorKind::Input, false, message)
}

#[track_caller]
fn changed(message: &'static str) -> UbaaError {
    UbaaError::upstream_changed(message).with_diagnostic("preflight", "authority_check_failed")
}

#[track_caller]
fn submit_unknown() -> UbaaError {
    UbaaError::outcome_unknown(
        "杭州空间预约已发送，但未返回订单号，请先刷新“我的预约”再决定是否重试",
    )
}

#[track_caller]
fn unconfirmed(trade_no: &str) -> UbaaError {
    UbaaError::outcome_unknown(format!(
        "预约已提交（订单 {trade_no}），但 0 元确认结果未知；请在 10 分钟内到网页“我的预约”核对，未确认的订单会自动关闭"
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 点击坐标按网页同款aes_cbc加密为小写十六进制() {
        let pin = order_pin(612, 418);
        assert_eq!(pin.len(), 32);
        assert!(
            pin.bytes()
                .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
        );
        let decrypted = {
            use cipher::BlockModeDecrypt;
            cbc::Decryptor::<Aes128>::new(PIN_KEY.into(), PIN_IV.into())
                .decrypt_padded_vec::<Pkcs7>(&hex::decode(&pin).unwrap())
                .unwrap()
        };
        assert_eq!(decrypted, b"612,418");
    }

    #[test]
    fn 预约时段json使用字符串身份且不带空间组() {
        let json = reservation_order_json(&[CgyyReservationSelection {
            space_id: 70,
            time_id: 331_101,
            venue_space_group_id: None,
        }]);
        assert_eq!(json, r#"[{"spaceId":"70","timeId":"331101"}]"#);
    }

    #[test]
    fn 取消原因与订单号经过规范化校验() {
        let ok = normalize_cancel(&HangzhouCgyyCancelRequest {
            trade_no: " D261125000791 ".into(),
            reason: " 临时有事 ".into(),
        })
        .unwrap();
        assert_eq!(ok.trade_no, "D261125000791");
        assert_eq!(ok.reason, "临时有事");
        assert!(
            normalize_cancel(&HangzhouCgyyCancelRequest {
                trade_no: "D1".into(),
                reason: "   ".into(),
            })
            .is_err()
        );
        assert!(
            normalize_cancel(&HangzhouCgyyCancelRequest {
                trade_no: "D1/../x".into(),
                reason: "x".into(),
            })
            .is_err()
        );
    }
}
