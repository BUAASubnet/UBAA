//! 杭州校区校园卡（易通一卡通 H5）余额只读查询，以及杭州/北京校区识别。
//!
//! 杭州校区学生同时持有北京校园卡账户（余额通常为 0），因此首页「校园卡」对杭州学生改读
//! 易通余额，北京学生仍走 `it.buaa.edu.cn`，两者互不影响、也不同时显示。
//!
//! 协议（2026-11-26 浏览器核对，证据见 `docs/protocol/parity/campus.md` 杭州校园卡）：
//!
//! 1. 经 hzsso 应用入口「易通系统-一卡通」（CAS 插件应用）跳到
//!    `221.12.169.12:18080/easytong_webapp/static/getAuthInfo.html?etToken=&AccNum=`，
//!    `AccNum` 为三次 Base64 编码的账号。
//! 2. `POST /easytong_app/GetAccInfo`、`/GetWalletMoney`，表单编码，请求头
//!    `h5Req: Y` 与 `Authorization: <etToken>`；参数按键名排序后的值以 `|` 相连，
//!    末尾拼前端常量 `Md5Key` 求 MD5 作 `Sign`。`code == 1` 成功，`40004` 为令牌无效。
//! 3. 余额与官方「余额查询」页一致：`GetWalletMoney.list[].ewalletMoney` 之和。
//!
//! 令牌与账号只在本次调用内存中使用，不写日志、不落盘。

use base64::Engine as _;
use base64::engine::general_purpose::STANDARD;
use chrono::{TimeZone as _, Utc};
use md5::{Digest, Md5};
use serde_json::Value;
use tracing::{debug, warn};

use crate::domain::CampusAmount;
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::HttpRequest;
use crate::runtime::ClientRuntime;

pub(crate) const FEATURE: &str = "杭州校园卡";
pub(crate) const EASYTONG_HOST: &str = "221.12.169.12";
const EASYTONG_ORIGIN: &str = "http://221.12.169.12:18080";
const AUTH_PATH: &str = "/easytong_webapp/static/getAuthInfo.html";
/// hzsso 门户「易通系统-一卡通」应用（`idaasplugin_cas`）的启动地址。
const EASYTONG_START: &str = "http://hzsso.buaa.edu.cn/api/bff/v1.2/enduser/portal/sso/go_a2c70d41711752874339a2f988e506ad2MG8YcfZPmG";
/// 易通 H5 前端公开下发的签名常量（`app.*.js` 模块 `Md5Key`），不是用户凭据。
const SIGN_KEY: &str = "ok15we1@oid8x5afd@";
const TOKEN_INVALID: i64 = 40004;

/// 已知杭州校区学号中的院系代码（用户提供：57 专项研究生、60、61、63）。
const HANGZHOU_DEPARTMENT_CODES: [&str; 4] = ["57", "60", "61", "63"];
/// 杭州校区院系名称关键字（门户 `info.depart`）。
/// 北京另有「中法工程师学院」，所以不能只匹配「中法」。
const HANGZHOU_DEPARTMENT_KEYWORDS: [&str; 3] = ["杭州", "中法航空", "中法未来"];

/// 按门户院系名称或学号院系代码判断是否杭州校区学生；两者都无证据时按北京处理。
pub(crate) fn is_hangzhou(department: Option<&str>, school_id: Option<&str>) -> bool {
    if department.is_some_and(|name| {
        HANGZHOU_DEPARTMENT_KEYWORDS
            .iter()
            .any(|keyword| name.contains(keyword))
    }) {
        return true;
    }
    school_id
        .and_then(department_code)
        .is_some_and(|code| HANGZHOU_DEPARTMENT_CODES.contains(&code))
}

/// 学号形如 `23611234`（年级 + 院系 + 序号）或 `ZY2657710`（字母前缀 + 年级 + 院系 + 序号）。
fn department_code(school_id: &str) -> Option<&str> {
    let digits = school_id
        .trim()
        .trim_start_matches(|c: char| c.is_ascii_alphabetic());
    if digits.len() < 6 || !digits.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    digits.get(2..4)
}

pub(crate) async fn balance(runtime: &mut ClientRuntime) -> Result<CampusAmount> {
    crate::features::hzsso::require_direct_route(runtime)?;
    let entry = crate::features::hzsso::enter_application(runtime, EASYTONG_START, FEATURE).await?;
    let credential = auth_info(&entry.final_url).ok_or_else(|| {
        warn!(target: "ubaa::hz_card", operation = "enter", "易通入口未返回登录凭证");
        changed("杭州校园卡入口未返回登录凭证")
    })?;
    debug!(target: "ubaa::hz_card", operation = "enter", token_len = credential.token.len(), "已进入易通");

    let account = call(
        runtime,
        &credential,
        "GetAccInfo",
        &[("AccNum", credential.account.clone())],
    )
    .await?;
    let epid = match account.get("epid") {
        Some(Value::Number(number)) => number.to_string(),
        Some(Value::String(text)) if is_digits(text) => text.clone(),
        _ => return Err(changed("杭州校园卡账户信息缺少卡户编号")),
    };
    let wallets = call(
        runtime,
        &credential,
        "GetWalletMoney",
        &[("AccNum", credential.account.clone()), ("EPID", epid)],
    )
    .await?;
    total_balance(&wallets)
}

struct Credential {
    token: String,
    account: String,
}

fn auth_info(url: &str) -> Option<Credential> {
    let url = url::Url::parse(url).ok()?;
    if url.host_str()? != EASYTONG_HOST || url.path() != AUTH_PATH {
        return None;
    }
    let mut token = None;
    let mut account = None;
    for (key, value) in url.query_pairs() {
        match key.as_ref() {
            "etToken" => token = Some(value.into_owned()),
            "AccNum" => account = decode_account(&value),
            _ => {}
        }
    }
    Some(Credential {
        token: token.filter(|t| !t.is_empty() && t.len() <= 4096)?,
        account: account?,
    })
}

/// 易通 `isEncode` 开启时 `AccNum` 经三次 Base64 编码；解码后应为纯数字账号。
fn decode_account(raw: &str) -> Option<String> {
    let mut text = raw.trim().to_owned();
    for _ in 0..3 {
        let padded = match text.len() % 4 {
            2 => format!("{text}=="),
            3 => format!("{text}="),
            _ => text.clone(),
        };
        text = String::from_utf8(STANDARD.decode(padded).ok()?).ok()?;
    }
    is_digits(&text).then_some(text)
}

fn is_digits(text: &str) -> bool {
    !text.is_empty() && text.len() <= 32 && text.bytes().all(|b| b.is_ascii_digit())
}

fn beijing_time(runtime: &ClientRuntime) -> Result<String> {
    let seconds = super::now(runtime)?;
    let time = Utc
        .timestamp_opt(seconds, 0)
        .single()
        .ok_or_else(|| UbaaError::parse_error("读取时间无效"))?;
    Ok(time
        .with_timezone(&chrono_tz::Asia::Shanghai)
        .format("%Y%m%d%H%M%S")
        .to_string())
}

/// 与易通 H5 的 axios 拦截器一致：补 `Time`，按键名排序取值以 `|` 连接后拼常量求 MD5。
fn signed_form(params: &[(&str, String)], time: &str) -> String {
    let mut pairs: Vec<(&str, String)> = params.to_vec();
    pairs.push(("Time", time.to_owned()));
    pairs.sort_by(|a, b| a.0.cmp(b.0));
    let mut plain = String::new();
    for (_, value) in &pairs {
        plain.push_str(value);
        plain.push('|');
    }
    plain.push_str(SIGN_KEY);
    let sign = hex::encode(Md5::digest(plain.as_bytes()));
    pairs.push(("Sign", sign));
    pairs.push(("ContentType", "application/json".to_owned()));
    let mut form = url::form_urlencoded::Serializer::new(String::new());
    for (key, value) in &pairs {
        form.append_pair(key, value);
    }
    form.finish()
}

async fn call(
    runtime: &mut ClientRuntime,
    credential: &Credential,
    method: &str,
    params: &[(&str, String)],
) -> Result<Value> {
    let time = beijing_time(runtime)?;
    let mut request = HttpRequest::post(
        format!("{EASYTONG_ORIGIN}/easytong_app/{method}"),
        signed_form(params, &time).into_bytes(),
    );
    request.headers.insert(
        "Content-Type".into(),
        "application/x-www-form-urlencoded".into(),
    );
    request.headers.insert("h5Req".into(), "Y".into());
    request
        .headers
        .insert("Authorization".into(), credential.token.clone());
    let response = runtime.request(request).await?;
    debug!(target: "ubaa::hz_card", operation = method, status = response.status, body_len = response.body.len(), "收到易通响应");
    if response.status != 200 {
        return Err(crate::features::http::http_status_error(&response, FEATURE));
    }
    let payload: Value =
        serde_json::from_slice(&response.body).map_err(|_| changed("杭州校园卡响应不是 JSON"))?;
    match payload.get("code").and_then(Value::as_i64) {
        Some(1) => Ok(payload),
        Some(TOKEN_INVALID) => Err(UbaaError::new(
            ErrorCode::AuthenticationRequired,
            ErrorKind::Authentication,
            false,
            "杭州校园卡登录已失效",
        )),
        Some(_) => Err(UbaaError::upstream_unavailable("杭州校园卡服务暂时不可用")),
        None => Err(changed("杭州校园卡响应缺少状态码")),
    }
}

/// 官方「余额查询」页的总钱包余额：各钱包 `ewalletMoney`（元，两位小数）之和。
fn total_balance(payload: &Value) -> Result<CampusAmount> {
    let list = payload
        .get("list")
        .and_then(Value::as_array)
        .ok_or_else(|| changed("杭州校园卡钱包列表缺失"))?;
    let mut cents: i64 = 0;
    for wallet in list {
        let amount = match wallet.get("ewalletMoney") {
            Some(Value::String(text)) => yuan_to_cents(text),
            Some(Value::Number(number)) => yuan_to_cents(&number.to_string()),
            _ => None,
        }
        .ok_or_else(|| changed("杭州校园卡钱包金额格式变化"))?;
        cents = cents
            .checked_add(amount)
            .ok_or_else(|| changed("杭州校园卡钱包金额格式变化"))?;
    }
    let sign = if cents < 0 { "-" } else { "" };
    let abs = cents.unsigned_abs();
    Ok(CampusAmount {
        value: format!("{sign}{}.{:02}", abs / 100, abs % 100),
        unit: "元".into(),
    })
}

fn yuan_to_cents(text: &str) -> Option<i64> {
    let text = text.trim();
    let (negative, digits) = match text.strip_prefix('-') {
        Some(rest) => (true, rest),
        None => (false, text),
    };
    let (whole, fraction) = digits.split_once('.').unwrap_or((digits, ""));
    if whole.is_empty()
        || whole.len() > 12
        || fraction.len() > 2
        || !whole.bytes().all(|b| b.is_ascii_digit())
        || !fraction.bytes().all(|b| b.is_ascii_digit())
    {
        return None;
    }
    let fraction = format!("{fraction:0<2}");
    let value = whole.parse::<i64>().ok()? * 100 + fraction.parse::<i64>().ok()?;
    Some(if negative { -value } else { value })
}

#[track_caller]
fn changed(message: &str) -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        message,
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn 按院系名称或学号代码识别杭州校区() {
        assert!(is_hangzhou(Some("中法航空学院"), None));
        assert!(is_hangzhou(Some("北京航空航天大学中法未来科技学院"), None));
        assert!(is_hangzhou(None, Some("ZY2657710")));
        assert!(is_hangzhou(Some("未知"), Some("23611234")));
        assert!(is_hangzhou(None, Some("24631234")));
        assert!(is_hangzhou(None, Some("25601234")));
        assert!(!is_hangzhou(Some("计算机学院"), Some("23061234")));
        assert!(!is_hangzhou(Some("计算机学院"), Some("SY2306123")));
        assert!(!is_hangzhou(Some("中法工程师学院"), None));
        assert!(!is_hangzhou(None, None));
        assert!(!is_hangzhou(None, Some("abc")));
    }

    #[test]
    fn 账号经三次base64解码且只接受数字() {
        let encoded = STANDARD.encode(STANDARD.encode(STANDARD.encode("10000")));
        assert_eq!(decode_account(&encoded).as_deref(), Some("10000"));
        assert_eq!(
            decode_account(encoded.trim_end_matches('=')).as_deref(),
            Some("10000")
        );
        let letters = STANDARD.encode(STANDARD.encode(STANDARD.encode("abc")));
        assert_eq!(decode_account(&letters), None);
    }

    #[test]
    fn 只从易通授权页取凭证() {
        let account = STANDARD.encode(STANDARD.encode(STANDARD.encode("10000")));
        let url = format!(
            "http://221.12.169.12:18080/easytong_webapp/static/getAuthInfo.html?etToken=tok&jumpMod=homeIndex&AccNum={account}"
        );
        let credential = auth_info(&url).expect("凭证");
        assert_eq!(credential.token, "tok");
        assert_eq!(credential.account, "10000");
        assert!(auth_info(&url.replace("221.12.169.12", "example.com")).is_none());
        assert!(auth_info(&url.replace("etToken=tok", "etToken=")).is_none());
    }

    #[test]
    fn 签名与易通前端拦截器一致() {
        let form = signed_form(
            &[("AccNum", "10000".into()), ("EPID", "1".into())],
            "20261126120000",
        );
        let pairs: Vec<(String, String)> = url::form_urlencoded::parse(form.as_bytes())
            .into_owned()
            .collect();
        let keys: Vec<&str> = pairs.iter().map(|(k, _)| k.as_str()).collect();
        assert_eq!(keys, ["AccNum", "EPID", "Time", "Sign", "ContentType"]);
        // Python hashlib 独立计算的 md5("10000|1|20261126120000|" + SIGN_KEY)。
        assert_eq!(pairs[3].1, "7a795687c19a4c89e64ddfb043a0ab51");
    }

    #[test]
    fn 总余额为各钱包之和() {
        let payload = json!({"code":1,"list":[
            {"ewalletMoney":"15.00","walletMoney":15.0},
            {"ewalletMoney":"0.5","walletMoney":0.5},
            {"ewalletMoney":"0.00","walletMoney":0}
        ]});
        assert_eq!(total_balance(&payload).unwrap().value, "15.50");
        assert_eq!(
            total_balance(&json!({"code":1,"list":[]})).unwrap().value,
            "0.00"
        );
        assert!(total_balance(&json!({"code":1,"list":[{"ewalletMoney":"1.234"}]})).is_err());
        assert!(total_balance(&json!({"code":1})).is_err());
    }
}
