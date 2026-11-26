//! 门户身份资料及五项独立指标。
use super::{Service, activate, json, now, parser, persist, record};
use crate::domain::{CampusAmount, CampusMetric, CampusMetrics, PortalProfile};
use crate::error::{ErrorCode, ErrorKind, Result};
use crate::runtime::ClientRuntime;
use crate::session::business_cache::BusinessScope;
use serde_json::Value;

const BASE: &str = "https://it.buaa.edu.cn";
const INFO: &str = "https://it.buaa.edu.cn/personal/frontend/data/info";
const KEYS: [&str; 5] = [
    "net.netFee",
    "card.balance",
    "mail.unread",
    "book.bookNum",
    "wangPan.wangPan",
];

async fn authenticated_info(runtime: &mut ClientRuntime) -> Result<Value> {
    let scope = BusinessScope::Portal;
    let before = runtime.business_cookies_for_rejection(scope);
    let first = json(runtime, INFO).await;
    let requires_login = match &first {
        Ok(payload) => payload.get("e").and_then(Value::as_i64) == Some(10013),
        Err(error) => {
            before.is_some()
                && error.code == ErrorCode::UpstreamUnavailable
                && error.kind == ErrorKind::Authentication
        }
    };
    let payload = if requires_login {
        if let Some(rejected) = before {
            runtime.reject_business_session(scope, &rejected);
        }
        activate(runtime, Service::Portal).await?;
        json(runtime, INFO).await?
    } else {
        first?
    };
    parser::envelope(&payload)?;
    Ok(payload)
}

pub(crate) async fn get_profile(runtime: &mut ClientRuntime) -> Result<PortalProfile> {
    let payload = authenticated_info(runtime).await?;
    let result = parser::profile(&payload, now(runtime)?)?;
    persist(runtime)?;
    Ok(result)
}

fn item<'a>(items: &'a [Value], key: &str) -> Result<&'a Value> {
    let mut matches = items
        .iter()
        .filter(|item| item["key"].as_str() == Some(key));
    let item = matches.next().ok_or_else(parser::invalid)?;
    if matches.next().is_some() {
        return Err(parser::invalid());
    }
    Ok(item)
}

fn item_id<'a>(items: &'a [Value], key: &str) -> Result<&'a str> {
    parser::nonblank(&item(items, key)?["id"])
}

async fn detail(runtime: &mut ClientRuntime, items: &[Value], key: &str) -> Result<Value> {
    let id = item_id(items, key)?;
    let mut url = url::Url::parse(&format!("{BASE}/personal/frontend/data/detail"))
        .map_err(|_| parser::invalid())?;
    url.query_pairs_mut().append_pair("id", id);
    let payload = json(runtime, url.as_str()).await?;
    parser::envelope(&payload)?
        .get("data")
        .filter(|v| v.is_object())
        .cloned()
        .ok_or_else(parser::invalid)
}

async fn metric_amount(
    runtime: &mut ClientRuntime,
    items: &[Value],
    key: &str,
) -> Result<CampusMetric<CampusAmount>> {
    let result = detail(runtime, items, key)
        .await
        .and_then(|data| parser::amount(&data));
    record(result, now(runtime)?)
}

async fn metric_count(
    runtime: &mut ClientRuntime,
    items: &[Value],
    key: &str,
) -> Result<CampusMetric<u64>> {
    let result = detail(runtime, items, key)
        .await
        .and_then(|data| parser::count(&data));
    record(result, now(runtime)?)
}

/// 杭州校区学生只显示杭州易通余额（北京账户通常为 0，不同时显示）；失败只影响本项。
async fn hangzhou_card(runtime: &mut ClientRuntime) -> Result<CampusMetric<CampusAmount>> {
    let fetched_at = now(runtime)?;
    Ok(match super::hangzhou_card::balance(runtime).await {
        Ok(value) => CampusMetric::Success { value, fetched_at },
        Err(error) => {
            let message = if error.code == ErrorCode::Unsupported {
                error.message.clone()
            } else {
                "杭州校园卡余额暂时不可用".to_owned()
            };
            CampusMetric::Failure {
                error: crate::error::UbaaError::new(
                    error.code,
                    error.kind,
                    error.retryable,
                    message,
                ),
                fetched_at,
            }
        }
    })
}

/// 杭州校区学生的网费改读杭州认证网关；失败只影响本项，消息已是面向用户的说明。
async fn hangzhou_network(
    runtime: &mut ClientRuntime,
    school_id: Option<&str>,
) -> Result<CampusMetric<CampusAmount>> {
    let fetched_at = now(runtime)?;
    Ok(
        match super::hangzhou_network::balance(runtime, school_id).await {
            Ok(value) => CampusMetric::Success { value, fetched_at },
            Err(error) => CampusMetric::Failure { error, fetched_at },
        },
    )
}

async fn card(
    runtime: &mut ClientRuntime,
    items: &[Value],
    hangzhou: bool,
) -> Result<CampusMetric<CampusAmount>> {
    if hangzhou {
        return hangzhou_card(runtime).await;
    }
    if let Err(error) = item(items, KEYS[1]) {
        return record(Err(error), now(runtime)?);
    }
    let result = match json(runtime, &format!("{BASE}/buaa/frontend/card/balance")).await {
        Ok(payload) => parser::envelope(&payload).and_then(parser::amount),
        Err(error) => Err(error),
    };
    let result = match result {
        Err(error)
            if !error.is_session_conflict()
                && !error.is_campus_network_required()
                && error.code != crate::error::ErrorCode::AuthenticationRequired
                && matches!(
                    error.kind,
                    crate::error::ErrorKind::Network
                        | crate::error::ErrorKind::Upstream
                        | crate::error::ErrorKind::Parse
                        | crate::error::ErrorKind::Authentication
                ) =>
        {
            detail(runtime, items, KEYS[1])
                .await
                .and_then(|data| parser::amount(&data))
        }
        other => other,
    };
    record(result, now(runtime)?)
}

pub(crate) async fn get_metrics(runtime: &mut ClientRuntime) -> Result<CampusMetrics> {
    let info = authenticated_info(runtime).await?;
    let person = info.get("d").and_then(|d| d.get("info"));
    let text = |key: &str| {
        person
            .and_then(|person| person.get(key))
            .and_then(Value::as_str)
            .map(str::to_owned)
    };
    // 门户 `info.xgh` 为学工号；缺失时退回登录时记住的账号。
    let school_id = text("xgh").or_else(|| runtime.account_name().map(str::to_owned));
    let hangzhou =
        super::hangzhou_card::is_hangzhou(text("depart").as_deref(), school_id.as_deref());
    let payload = json(
        runtime,
        &format!("{BASE}/personal/frontend/data/items?type=personal_data"),
    )
    .await?;
    let items = parser::envelope(&payload)?
        .get("data")
        .and_then(Value::as_array)
        .ok_or_else(parser::invalid)?;
    let network_balance = if hangzhou {
        hangzhou_network(runtime, school_id.as_deref()).await?
    } else {
        metric_amount(runtime, items, KEYS[0]).await?
    };
    let card_balance = card(runtime, items, hangzhou).await?;
    let unread_mail = metric_count(runtime, items, KEYS[2]).await?;
    let borrowed_books = metric_count(runtime, items, KEYS[3]).await?;
    let cloud_storage_remaining = metric_amount(runtime, items, KEYS[4]).await?;
    persist(runtime)?;
    Ok(CampusMetrics {
        network_balance,
        card_balance,
        unread_mail,
        borrowed_books,
        cloud_storage_remaining,
    })
}
