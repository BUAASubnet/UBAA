//! 图书馆当前借阅与单本续借。复用已有路线的 SSO Cookie 建立图书馆业务会话。
use super::{decode, pairs};
use crate::domain::{
    ConnectionMode, LibraryLoan, LibraryLoanRenewRequest, LibraryLoanRenewResult,
    LibraryLoanStatus, LibraryLoans,
};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::{HttpRequest, HttpResponse};
use crate::runtime::ClientRuntime;
use serde_json::Value;
use url::Url;

const HOST: &str = "space.lib.buaa.edu.cn";
const ENTRY_PATH: &str = "/meta-local/opac/cas/rosetta";
const ENTRY: &str = "https://space.lib.buaa.edu.cn/meta-local/opac/cas/rosetta";
const LIST: &str = "https://space.lib.buaa.edu.cn/meta-local/opac/users/loans";
const MAX_RENEW: &str = "https://space.lib.buaa.edu.cn/meta-local/opac/users/loan_max_renew_times";
const RENEW: &str = "https://space.lib.buaa.edu.cn/meta-local/opac/users/batch_renew";
const PAGE_SIZE: u32 = 20;
const MAX_TOTAL: u32 = 10_000;
const MAX_ID: usize = 256;

fn invalid() -> UbaaError {
    UbaaError::upstream_changed("图书馆借阅响应与已验证版本不一致")
}

fn needs_session() -> UbaaError {
    UbaaError::authentication_required("图书馆会话需要恢复，请重新登录后重试")
}

fn unknown_write() -> UbaaError {
    UbaaError::outcome_unknown("续借请求可能已到达学校，请先刷新借阅记录核对")
}

fn is_entry(url: &Url) -> bool {
    url.host_str() == Some(HOST) && url.path() == ENTRY_PATH
}

async fn get(runtime: &mut ClientRuntime, direct: &str, api: bool) -> Result<HttpResponse> {
    crate::features::require_session(runtime)?;
    runtime.ensure_session_revision()?;
    let expected = runtime.url(direct)?;
    let mut request = HttpRequest::get(&expected).with_header(
        "Accept",
        if api {
            "application/json, text/plain, */*"
        } else {
            "text/html,*/*"
        },
    );
    if api {
        request = request
            .with_header("X-Hw-Lang", "chi")
            .with_header("X-Hw-explorer", "m")
            .with_header("X-CSRF-TOKEN", "");
    }
    let response = runtime
        .request_with_pre_send_check(request, ClientRuntime::ensure_session_revision)
        .await?;
    runtime.ensure_session_revision()?;
    if response.final_url != expected || response.body.len() > 2 * 1024 * 1024 {
        return Err(invalid());
    }
    if runtime.mode() == ConnectionMode::WebVpn
        && response.status == 302
        && response
            .header_first("Location")
            .and_then(|value| Url::parse(value).ok())
            .is_some_and(|url| {
                url.scheme() == "https"
                    && url.host_str() == Some(HOST)
                    && url.port_or_known_default() == Some(443)
            })
    {
        return Err(UbaaError::library_webvpn_unsupported());
    }
    Ok(response)
}

/// 只接受图书馆入口、携带 ticket 的入口回调和嵌套该入口的学校 SSO 登录页。
fn target(raw: &str, mode: ConnectionMode) -> Result<Url> {
    let url = decode(raw, mode)?;
    if url.host_str() == Some("sso.buaa.edu.cn") && url.path() == "/login" {
        let query = pairs(&url)?;
        if query.len() == 1
            && query
                .get("service")
                .and_then(|service| decode(service, mode).ok())
                .is_some_and(|service| is_entry(&service))
        {
            return Ok(url);
        }
    } else if is_entry(&url) {
        let query = pairs(&url)?;
        if query.is_empty()
            || query
                .iter()
                .all(|(key, value)| key == "ticket" && !value.is_empty())
        {
            return Ok(url);
        }
    }
    Err(invalid())
}

async fn activate(runtime: &mut ClientRuntime) -> Result<()> {
    let mut current = Url::parse(ENTRY).map_err(|_| invalid())?;
    for _ in 0..8 {
        let current_target = target(current.as_str(), runtime.mode())?;
        let response = get(runtime, current_target.as_str(), false).await?;
        if matches!(response.status, 301 | 302 | 303 | 307 | 308) {
            let location = response.header_first("location").ok_or_else(invalid)?;
            let next = crate::connection::business_redirect_target(&response.final_url, location)?;
            current = target(next.as_str(), runtime.mode())?;
            continue;
        }
        if matches!(response.status, 401 | 403) {
            return Err(needs_session());
        }
        if response.status == 200 {
            if is_entry(&current_target) {
                return Ok(());
            }
            if current_target.host_str() == Some("sso.buaa.edu.cn") {
                return Err(needs_session());
            }
            return Err(invalid());
        }
        if response.status >= 500 {
            return Err(UbaaError::upstream_unavailable("图书馆服务暂时不可用"));
        }
        return Err(invalid());
    }
    Err(invalid())
}

fn text(value: &Value) -> Option<String> {
    value
        .as_str()
        .map(str::trim)
        .filter(|value| {
            !value.is_empty() && value.len() <= 512 && !value.chars().any(char::is_control)
        })
        .map(Into::into)
}

fn optional_text(value: Option<&Value>) -> Option<String> {
    value.and_then(text)
}

fn identifier(value: &Value) -> Option<String> {
    match value {
        Value::String(_) => text(value),
        Value::Number(number) => number.as_u64().map(|value| value.to_string()),
        _ => None,
    }
}

fn count(value: &Value) -> Option<u32> {
    let parsed = match value {
        Value::Number(number) => number.as_u64(),
        Value::String(value) => value.trim().parse::<u64>().ok(),
        _ => None,
    }?;
    u32::try_from(parsed)
        .ok()
        .filter(|value| *value <= 1_000_000)
}

fn envelope(payload: &Value) -> Result<(&Value, Option<&Value>)> {
    let object = payload.as_object().ok_or_else(invalid)?;
    let code = object.get("code").and_then(Value::as_i64);
    if code != Some(0) {
        return Err(invalid());
    }
    Ok((object.get("data").ok_or_else(invalid)?, object.get("msg")))
}

fn status(value: Option<&Value>) -> LibraryLoanStatus {
    match value.and_then(Value::as_str).map(str::trim) {
        Some("overdue") => LibraryLoanStatus::Overdue,
        Some("soon") => LibraryLoanStatus::Soon,
        Some("normal") => LibraryLoanStatus::Normal,
        _ => LibraryLoanStatus::Other,
    }
}

fn loan(value: &Value) -> Result<(LibraryLoan, Option<String>)> {
    let object = value.as_object().ok_or_else(invalid)?;
    let id = object
        .get("loanId")
        .and_then(identifier)
        .filter(|value| value.len() <= MAX_ID)
        .ok_or_else(invalid)?;
    let title = object.get("title").and_then(text).ok_or_else(invalid)?;
    // Direct 列表样本只证明条码位于 item.barCode；顶层同名字段不作为回退。
    let bar_code = object
        .get("item")
        .and_then(Value::as_object)
        .and_then(|item| item.get("barCode"))
        .and_then(identifier);
    let author = optional_text(object.get("author"));
    let loan_date = optional_text(object.get("loanDate"));
    let due_date = optional_text(object.get("dueDate"));
    let renew_times = match object.get("renewTimes") {
        Some(value) => Some(count(value).ok_or_else(invalid)?),
        None => None,
    };
    let location = optional_text(object.get("location"));
    let status = status(object.get("loanStatus"));
    Ok((
        LibraryLoan {
            id: id.clone(),
            title,
            author,
            loan_date,
            due_date,
            renew_times,
            can_renew_times: None,
            status,
            location,
        },
        bar_code,
    ))
}

fn parse_page(value: &Value, page: u32) -> Result<(Vec<LibraryLoan>, Vec<Option<String>>, u32)> {
    let data = value.as_object().ok_or_else(invalid)?;
    let current = data.get("currentPage").and_then(Value::as_u64);
    let size = data.get("pageSize").and_then(Value::as_u64);
    let total = data.get("total").and_then(Value::as_u64);
    let total_page = data.get("totalPage").and_then(Value::as_u64);
    let items = data.get("items").and_then(Value::as_array);
    let (Some(current), Some(size), Some(total), Some(total_page), Some(items)) =
        (current, size, total, total_page, items)
    else {
        return Err(invalid());
    };
    if current != u64::from(page)
        || size == 0
        || size > u64::from(PAGE_SIZE)
        || total > u64::from(MAX_TOTAL)
        || items.len() as u64 > size
        || items.len() as u64 > u64::from(PAGE_SIZE)
    {
        return Err(invalid());
    }
    let expected_pages = if total == 0 { 0 } else { total.div_ceil(size) };
    if total_page != expected_pages && !(total == 0 && total_page == 1) {
        return Err(invalid());
    }
    let mut entries = Vec::with_capacity(items.len());
    let mut bar_codes = Vec::with_capacity(items.len());
    for item in items {
        let (entry, bar_code) = loan(item)?;
        entries.push(entry);
        bar_codes.push(bar_code);
    }
    Ok((
        entries,
        bar_codes,
        u32::try_from(total).map_err(|_| invalid())?,
    ))
}

/// 续借上限是列表之外的独立只读条件；条件数据不可用时保留可续借次数未知。
async fn max_renew_times(
    runtime: &mut ClientRuntime,
    page: u32,
    require_conditions: bool,
) -> Result<std::collections::HashMap<String, u32>> {
    let url = format!("{MAX_RENEW}?page={page}&pageSize={PAGE_SIZE}");
    let response = match get(runtime, &url, true).await {
        Err(error)
            if !require_conditions && error.code == ErrorCode::Timeout && error.retryable =>
        {
            runtime.check_authentication_scope()?;
            runtime.ensure_session_revision()?;
            return Ok(std::collections::HashMap::new());
        }
        result => result?,
    };
    if matches!(response.status, 401 | 403) {
        return Err(needs_session());
    }
    let missing = || {
        if require_conditions {
            Err(invalid())
        } else {
            Ok(std::collections::HashMap::new())
        }
    };
    if require_conditions && response.status >= 500 {
        return Err(UbaaError::upstream_unavailable("图书馆服务暂时不可用"));
    }
    if response.status != 200 {
        return missing();
    }
    let Ok(payload) = serde_json::from_slice::<Value>(&response.body) else {
        return missing();
    };
    let Ok((data, _)) = envelope(&payload) else {
        return missing();
    };
    let Some(items) = data.get("items").and_then(Value::as_array) else {
        return missing();
    };
    let mut result = std::collections::HashMap::with_capacity(items.len());
    for item in items {
        let Some(object) = item.as_object() else {
            return missing();
        };
        let Some(bar_code) = object.get("barCode").and_then(identifier) else {
            return missing();
        };
        let Some(max) = object.get("maxRenewTimes").and_then(count) else {
            return missing();
        };
        result.insert(bar_code, max);
    }
    Ok(result)
}

async fn list_all(runtime: &mut ClientRuntime, require_conditions: bool) -> Result<LibraryLoans> {
    let mut entries = Vec::new();
    let mut seen = std::collections::HashSet::new();
    let mut total = None;
    let mut page_number = 1;
    loop {
        let url = format!("{LIST}?page={page_number}&pageSize={PAGE_SIZE}");
        let response = get(runtime, &url, true).await?;
        if matches!(response.status, 401 | 403) {
            return Err(needs_session());
        }
        if response.status >= 500 {
            return Err(UbaaError::upstream_unavailable("图书馆服务暂时不可用"));
        }
        if response.status != 200 {
            return Err(invalid());
        }
        let payload: Value = serde_json::from_slice(&response.body).map_err(|_| {
            UbaaError::parse_error("无法解析当前借阅")
                .with_diagnostic("parse", "library_loans_json_invalid")
                .with_response(&response.body, Some(response.status))
        })?;
        let (data, _) = envelope(&payload)?;
        let (rows, bar_codes, page_total) = parse_page(data, page_number)?;
        if total.is_some_and(|total| total != page_total) {
            return Err(invalid());
        }
        total = Some(page_total);
        let empty = rows.is_empty();
        if !rows.is_empty() {
            let renew_limits = max_renew_times(runtime, page_number, require_conditions).await?;
            for (mut row, bar_code) in rows.into_iter().zip(bar_codes) {
                if !seen.insert(row.id.clone()) {
                    return Err(invalid());
                }
                row.can_renew_times = bar_code.and_then(|bar_code| {
                    row.renew_times.and_then(|renewed| {
                        renew_limits
                            .get(&bar_code)
                            .map(|limit| limit.saturating_sub(renewed))
                    })
                });
                entries.push(row);
            }
        }
        let total = total.expect("本页已确认总数");
        if entries.len() == usize::try_from(total).unwrap_or(usize::MAX) {
            return Ok(LibraryLoans { entries, total });
        }
        if empty || entries.len() > usize::try_from(total).unwrap_or(0) {
            return Err(invalid());
        }
        page_number += 1;
    }
}

pub(crate) async fn current_loans(runtime: &mut ClientRuntime) -> Result<LibraryLoans> {
    read_loans(runtime, false).await
}

async fn read_loans(runtime: &mut ClientRuntime, require_conditions: bool) -> Result<LibraryLoans> {
    crate::features::require_session(runtime)?;
    match list_all(runtime, require_conditions).await {
        Ok(value) => Ok(value),
        Err(error) if error.code == ErrorCode::AuthenticationRequired => {
            activate(runtime).await?;
            list_all(runtime, require_conditions).await
        }
        Err(error) => Err(error),
    }
}

fn normalize_id(raw: &str) -> Result<String> {
    let value = raw.trim();
    if value.is_empty()
        || value.len() > MAX_ID
        || value.chars().any(char::is_control)
        || value.chars().any(char::is_whitespace)
    {
        return Err(UbaaError::invalid_input(
            "续借目标无效，请刷新借阅记录后重试",
        ));
    }
    Ok(value.into())
}

pub(crate) async fn renew_preflight(
    runtime: &mut ClientRuntime,
    loan_id: &str,
) -> Result<LibraryLoan> {
    let loan_id = normalize_id(loan_id)?;
    let loans = read_loans(runtime, true).await?;
    let mut matches = loans.entries.into_iter().filter(|loan| loan.id == loan_id);
    let Some(loan) = matches.next() else {
        return Err(
            UbaaError::invalid_input("借阅记录已不在当前借阅中，无法续借")
                .with_diagnostic("preflight", "library_renew_unavailable"),
        );
    };
    if matches.next().is_some() {
        return Err(invalid());
    }
    if loan.can_renew_times.unwrap_or(0) == 0 {
        return Err(
            UbaaError::invalid_input("这本书当前不可续借，请刷新后查看借阅记录")
                .with_diagnostic("preflight", "library_renew_unavailable"),
        );
    }
    Ok(loan)
}

pub(crate) async fn renew(
    runtime: &mut ClientRuntime,
    request: LibraryLoanRenewRequest,
) -> Result<LibraryLoanRenewResult> {
    let current = renew_preflight(runtime, &request.loan_id).await?;
    if current.due_date != request.due_date
        || current.renew_times != request.renew_times
        || current.can_renew_times != request.can_renew_times
    {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            true,
            "续借目标已变化，请刷新后重试",
        )
        .with_diagnostic("preflight", "library_renew_changed"));
    }
    let loan_id = current.id;
    let body = serde_json::to_vec(&serde_json::json!({
        "loanIds": [loan_id.clone()],
        "source": 1,
    }))
    .map_err(|_| invalid())?;
    let expected = runtime.url(RENEW)?;
    let request = HttpRequest::post(&expected, body)
        .with_header("Content-Type", "application/json")
        .with_header("Accept", "application/json, text/plain, */*")
        .with_header("X-Hw-Lang", "chi")
        .with_header("X-Hw-explorer", "m")
        .with_header("X-CSRF-TOKEN", "");
    let response = runtime
        .request_non_idempotent(request)
        .await
        .map_err(|error| {
            if error.code == ErrorCode::OutcomeUnknown {
                unknown_write()
            } else {
                error
            }
        })?;
    // 写请求已经离开本机；登录页、非 200 或不可解析的正文都不能推导为失败。
    if response.final_url != expected || response.status != 200 {
        return Err(unknown_write());
    }
    let payload: Value = serde_json::from_slice(&response.body).map_err(|_| unknown_write())?;
    let Some(object) = payload.as_object() else {
        return Err(unknown_write());
    };
    let code = match object.get("code") {
        Some(Value::Number(code)) if code.is_i64() || code.is_u64() => code,
        _ => return Err(unknown_write()),
    };
    if code.as_i64() != Some(0) {
        return Err(renew_rejection(object.get("msg")));
    }
    match object.get("data") {
        Some(Value::Object(failures)) if failures.contains_key(&loan_id) => {
            Err(renew_rejection(failures.get(&loan_id)))
        }
        Some(Value::Null) => Ok(LibraryLoanRenewResult {
            loan_id,
            success: true,
        }),
        Some(Value::Object(failures)) if failures.is_empty() => Ok(LibraryLoanRenewResult {
            loan_id,
            success: true,
        }),
        _ => Err(unknown_write()),
    }
}

fn renew_rejection(reason: Option<&Value>) -> UbaaError {
    let error = UbaaError::new(
        ErrorCode::BusinessRejected,
        ErrorKind::Upstream,
        false,
        "学校未接受本次续借，请刷新后查看借阅记录",
    );
    match reason.and_then(Value::as_str).map(str::trim) {
        Some("META-403060: 不允许续借,未达到到期前续借天数") => error
            .with_diagnostic("response", "library_renew_rejected_with_message")
            .with_private_display_message("尚未进入续借窗口，请稍后再试".to_owned()),
        _ => error.with_diagnostic("response", "library_renew_rejected"),
    }
}
