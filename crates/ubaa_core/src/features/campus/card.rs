//! 卡站点登录、充值下单与收银台地址。
//!
//! 冻结旧版与 buaa-api 都没有校园卡充值的同源协议；本模块的九列依据来自用户
//! 提供的抓包和本会话实测，记录在 `docs/protocol/parity/campus.md`。

use super::{CARD_BASE, CARD_PREFIX, envelope, parser};
use crate::domain::{CampusRechargeOrder, CampusRechargePreflight};
use crate::error::{ErrorKind, Result, UbaaError};
use crate::ports::HttpRequest;
use crate::runtime::ClientRuntime;
use serde_json::Value;
use url::Url;

const SSO_LOGIN: &str = "https://sso.buaa.edu.cn/login";
const CASHIER_HOST: &str = "cashier.cc-pay.cn";
const CARD_SERVICE_PATH: &str = "/card/home/sisUstbMiniReturnPage/112233/6/auth";
/// `goIndex` 跳转的用户类型与授权回调路径段一致。
const PATH_USERTYPE: &str = "6";
const PAYLOAD_USERTYPE: &str = "1";
const PAY_WAY_HCT: &str = "10";

fn invalid() -> UbaaError {
    UbaaError::upstream_changed("校园卡响应不符合已验证的格式")
}

fn is_redirect(status: u16) -> bool {
    matches!(status, 301 | 302 | 303 | 307 | 308)
}

/// 回调只允许精确落在卡站点固定组织段与授权路径上，且必须携带唯一非空 ticket。
fn callback_url(url: &Url) -> bool {
    if url.scheme() != "https"
        || url.port_or_known_default() != Some(443)
        || !url.username().is_empty()
        || url.password().is_some()
        || url.fragment().is_some()
    {
        return false;
    }
    if url.host_str() != Some("m.icw.buaa.edu.cn") || url.path() != CARD_SERVICE_PATH {
        return false;
    }
    let mut ticket = None;
    for (key, value) in url.query_pairs() {
        if key != "ticket" || value.is_empty() || ticket.is_some() {
            return false;
        }
        ticket = Some(value);
    }
    ticket.is_some()
}

fn next_location(response: &crate::ports::HttpResponse, runtime: &ClientRuntime) -> Result<Url> {
    let location = Url::parse(&response.final_url)
        .map_err(|_| invalid())?
        .join(response.header_first("location").ok_or_else(invalid)?)
        .map_err(|_| invalid())?;
    super::decode(location.as_str(), runtime.mode())
}

/// 已认证会话下换取卡站点 openid。
///
/// SSO 已登录时 `/login?service=` 直接 302 出带 ticket 的回调；回调再 302 到
/// `/card/goIndex?openid=…&usertype=6`。openid 是账号级凭据，只留在路线内存。
async fn fetch_openid(runtime: &mut ClientRuntime) -> Result<String> {
    let service = format!("{CARD_BASE}{CARD_SERVICE_PATH}");
    let mut login = Url::parse(&runtime.url(SSO_LOGIN)?).map_err(|_| invalid())?;
    login.query_pairs_mut().append_pair("service", &service);

    let mut current = login.as_str().to_owned();
    for _ in 0..10 {
        let referer = runtime.url(&format!("{CARD_BASE}{CARD_PREFIX}/"))?;
        let request = HttpRequest::get(current.clone())
            .with_header("Accept", "text/html,*/*")
            .with_header("Referer", referer);
        let response = runtime
            .request_with_pre_send_check(request, ClientRuntime::ensure_session_revision)
            .await?;
        runtime.ensure_session_revision()?;
        if !is_redirect(response.status) {
            // 卡站点以 302 交出 openid；任何页面都偏离已验证行为。
            return Err(invalid());
        }
        let next = next_location(&response, runtime)?;
        if next.host_str() == Some("sso.buaa.edu.cn") {
            return Err(parser::business_login_required());
        }
        if next.host_str() == Some("m.icw.buaa.edu.cn") && next.path() == goindex_path() {
            return openid_from(&next);
        }
        if !callback_url(&next) {
            return Err(invalid());
        }
        current = runtime.url(next.as_str())?;
    }
    Err(invalid())
}

fn goindex_path() -> String {
    format!("{CARD_PREFIX}/goIndex")
}

/// `/card/goIndex` 必须只携带 openid 与 usertype，openid 为 64–128 位大写十六进制。
fn openid_from(url: &Url) -> Result<String> {
    let mut openid = None;
    let mut usertype_seen = false;
    for (key, value) in url.query_pairs() {
        match key.as_ref() {
            "openid" if openid.is_none() => openid = Some(value.into_owned()),
            "usertype" if !usertype_seen && value == PATH_USERTYPE => usertype_seen = true,
            _ => return Err(invalid()),
        }
    }
    let openid = openid.ok_or_else(invalid)?;
    if !usertype_seen
        || !(64..=128).contains(&openid.len())
        || !openid
            .bytes()
            .all(|b| b.is_ascii_hexdigit() && !b.is_ascii_lowercase())
    {
        return Err(invalid());
    }
    Ok(openid)
}

/// 复用路线内存中的 openid；缺失时重新登录卡站点。
async fn ensure_openid(runtime: &mut ClientRuntime) -> Result<String> {
    crate::features::require_session(runtime)?;
    let state = runtime.feature_state();
    if let Some(value) = state.campus_card.token() {
        return Ok(value);
    }
    let _guard = state.campus_card.login_guard().await;
    if let Some(value) = state.campus_card.token() {
        return Ok(value);
    }
    let generation = state.campus_card.generation();
    let value = fetch_openid(runtime).await?;
    if !state
        .campus_card
        .store_credential(generation, value.clone())
    {
        return Err(invalid());
    }
    Ok(value)
}

fn is_ascii_token(value: &str, max: usize) -> bool {
    !value.is_empty() && value.len() <= max && value.bytes().all(|b| b.is_ascii_alphanumeric())
}

/// 调用卡站点接口并解开响应信封。写请求走不可重放边界。
async fn call(
    runtime: &mut ClientRuntime,
    path: &str,
    payload: &Value,
    non_idempotent: bool,
) -> Result<Value> {
    crate::features::require_session(runtime)?;
    runtime.ensure_session_revision()?;
    let envelope = envelope::seal(payload)?;
    let referer = runtime.url(&format!("{CARD_BASE}{CARD_PREFIX}/"))?;
    let body =
        serde_json::to_vec(&serde_json::json!({ "datajson": envelope })).map_err(|_| invalid())?;
    let mut request = HttpRequest::post(
        runtime.url(&format!("{CARD_BASE}{CARD_PREFIX}{path}"))?,
        body,
    );
    for (name, value) in [
        ("Content-Type", "application/json"),
        ("Accept", "*/*"),
        ("X-Requested-With", "XMLHttpRequest"),
        ("session-type", "uniapp"),
        ("isWechatApp", "true"),
        ("orgid", "2"),
        ("Referer", referer.as_str()),
    ] {
        request = request.with_header(name, value);
    }
    let response = if non_idempotent {
        runtime
            .request_non_idempotent_with_pre_send_check(
                request,
                ClientRuntime::ensure_session_revision,
            )
            .await?
    } else {
        runtime
            .request_with_pre_send_check(request, ClientRuntime::ensure_session_revision)
            .await?
    };
    runtime.ensure_session_revision()?;
    match response.status {
        200 => {}
        401 | 403 => return Err(parser::business_login_required()),
        500..=599 => return Err(UbaaError::upstream_unavailable("校园卡服务暂时不可用")),
        _ => return Err(invalid()),
    }
    if response.body.len() > 2 * 1024 * 1024 {
        return Err(invalid());
    }
    let body: Value = serde_json::from_slice(&response.body).map_err(|_| invalid())?;
    let blob = body
        .get("datajson")
        .and_then(Value::as_str)
        .ok_or_else(invalid)?;
    envelope::open(blob)
}

fn success_field<'a>(payload: &'a Value, field: &str) -> Result<&'a Value> {
    match payload.get("success").and_then(Value::as_bool) {
        Some(true) => payload.get(field).ok_or_else(invalid),
        Some(false) => Err(UbaaError::new(
            crate::error::ErrorCode::UpstreamUnavailable,
            ErrorKind::Upstream,
            false,
            "校园卡服务拒绝了本次请求",
        )),
        None => Err(invalid()),
    }
}

/// 读取卡序号与余额，作为充值前的准备信息。
pub(crate) async fn preflight(runtime: &mut ClientRuntime) -> Result<CampusRechargePreflight> {
    let openid = ensure_openid(runtime).await?;
    let payload = call(
        runtime,
        "/cardpay/openCardPay",
        &serde_json::json!({ "openid": openid }),
        false,
    )
    .await?;
    let card = success_field(&payload, "data")?
        .get("cardPay")
        .ok_or_else(invalid)?;
    let idserial = card
        .get("idserial")
        .and_then(Value::as_str)
        .filter(|v| is_ascii_token(v, 32))
        .ok_or_else(invalid)?
        .to_owned();
    let balance = card
        .get("cardbal")
        .and_then(Value::as_str)
        .filter(|v| !v.is_empty() && v.len() <= 32 && !v.chars().any(char::is_control))
        .ok_or_else(invalid)?
        .to_owned();
    Ok(CampusRechargePreflight {
        idserial,
        balance,
        fetched_at: super::now(runtime)?,
    })
}

/// 创建一笔不可重放的充值订单，返回已验证的商户收银台地址，不选择支付渠道。
pub(crate) async fn order(
    runtime: &mut ClientRuntime,
    idserial: &str,
    fen: &str,
) -> Result<CampusRechargeOrder> {
    if !is_ascii_token(idserial, 32) || fen.is_empty() || !fen.bytes().all(|b| b.is_ascii_digit()) {
        return Err(invalid());
    }
    let openid = ensure_openid(runtime).await?;
    let payload = call(
        runtime,
        &format!("/recharge/rechargeByHct?openid={openid}"),
        &serde_json::json!({
            "idserial": idserial,
            "txamt": fen,
            "payway": "",
            "openid": openid,
            "payWay": PAY_WAY_HCT,
            "tradetype": "WAP",
            "usertype": PAYLOAD_USERTYPE,
            "orgid": "2",
        }),
        true,
    )
    .await?;
    let result = success_field(&payload, "resultData")?;
    let orderno = result
        .get("orderno")
        .and_then(Value::as_str)
        .filter(|v| is_ascii_token(v, 64))
        .ok_or_else(invalid)?
        .to_owned();
    let cashier_url = result
        .get("mweb_url")
        .and_then(Value::as_str)
        .and_then(|value| Url::parse(value).ok())
        .filter(|url| {
            url.scheme() == "https"
                && url.host_str() == Some(CASHIER_HOST)
                && url.port_or_known_default() == Some(443)
                && url.username().is_empty()
                && url.password().is_none()
                && url.fragment().is_none()
                && url.path() == "/cashier"
                && url
                    .query_pairs()
                    .eq([("id".into(), orderno.as_str().into())])
        })
        .ok_or_else(invalid)?
        .into();
    Ok(CampusRechargeOrder {
        orderno,
        cashier_url,
        amount_fen: fen.to_owned(),
        fetched_at: super::now(runtime)?,
    })
}
