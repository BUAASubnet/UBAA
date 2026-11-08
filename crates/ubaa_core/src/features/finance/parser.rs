use crate::domain::FinanceIncome;
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use serde_json::Value;
pub(super) fn invalid() -> UbaaError {
    UbaaError::upstream_changed("财务响应结构异常，请稍后重试")
}
pub(super) fn envelope(bytes: &[u8]) -> Result<Value> {
    let v: Value = serde_json::from_slice(bytes).map_err(|_| invalid())?;
    match v.get("code").and_then(Value::as_i64) {
        Some(200) => v
            .get("data")
            .filter(|v| v.is_object())
            .cloned()
            .ok_or_else(invalid),
        Some(401) => Err(UbaaError::new(
            ErrorCode::AuthenticationRequired,
            ErrorKind::Authentication,
            false,
            "财务登录已失效",
        )),
        _ => Err(invalid()),
    }
}
pub(super) fn cents(v: &Value) -> Result<Option<i64>> {
    if v.is_null() {
        return Ok(None);
    }
    let number = v.as_number().ok_or_else(invalid)?.to_string();
    let (negative, text) = number
        .strip_prefix('-')
        .map_or((false, number.as_str()), |s| (true, s));
    let (whole, fraction) = text.split_once('.').unwrap_or((text, ""));
    if fraction.len() > 2
        || !whole.bytes().all(|b| b.is_ascii_digit())
        || !fraction.bytes().all(|b| b.is_ascii_digit())
    {
        return Err(invalid());
    }
    let whole = whole.parse::<i64>().map_err(|_| invalid())?;
    let fraction = match fraction.len() {
        0 => 0,
        1 => fraction.parse::<i64>().map_err(|_| invalid())? * 10,
        _ => fraction.parse::<i64>().map_err(|_| invalid())?,
    };
    let value = whole
        .checked_mul(100)
        .and_then(|v| v.checked_add(fraction))
        .ok_or_else(invalid)?;
    Ok(Some(if negative { -value } else { value }))
}
pub(super) fn page(v: &Value) -> Result<(Vec<Value>, usize)> {
    let (rows, total) = if v.get("mx").is_some() || v.get("total").is_some() {
        ("mx", "total")
    } else {
        ("data", "count")
    };
    let rows = v
        .get(rows)
        .and_then(Value::as_array)
        .ok_or_else(invalid)?
        .clone();
    let total = v
        .get(total)
        .and_then(Value::as_u64)
        .and_then(|n| usize::try_from(n).ok())
        .ok_or_else(invalid)?;
    if total > u32::MAX as usize || rows.len() > total {
        return Err(invalid());
    }
    Ok((rows, total))
}
fn text(v: &Value, key: &str) -> Result<Option<String>> {
    match v.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(s)) => Ok((!s.is_empty()).then(|| s.clone())),
        _ => Err(invalid()),
    }
}
pub(super) fn income(v: &Value) -> Result<FinanceIncome> {
    if !v.is_object() {
        return Err(invalid());
    }
    Ok(FinanceIncome {
        id: text(v, "lsh")?.ok_or_else(invalid)?,
        project: text(v, "ffxmmc")?,
        description: text(v, "zy")?,
        amount_cents: cents(&v["je"])?,
        tax_cents: cents(&v["se"])?,
        paid_cents: cents(&v["sfje"])?,
        tax_rate: text(v, "slbfb")?,
        recorded_date: text(v, "lrrq")?,
        year: text(v, "nian")?,
        month: text(v, "yue")?,
    })
}
