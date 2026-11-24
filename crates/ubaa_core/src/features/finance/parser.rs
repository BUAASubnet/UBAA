use crate::domain::FinanceIncome;
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use serde_json::Value;

#[track_caller]
pub(super) fn failure(stage: &'static str, reason: &'static str) -> UbaaError {
    UbaaError::upstream_changed("财务响应结构异常，请稍后重试").with_diagnostic(stage, reason)
}

pub(super) fn envelope(bytes: &[u8], stage: &'static str) -> Result<Value> {
    let result = (|| {
        let value: Value =
            serde_json::from_slice(bytes).map_err(|_| failure(stage, "json_invalid"))?;
        match value.get("code").and_then(Value::as_i64) {
            Some(200) => match value.get("data") {
                None => Err(failure(stage, "data_missing")),
                Some(Value::Null) => Err(failure(stage, "data_null")),
                Some(data) if data.is_object() => Ok(data.clone()),
                Some(_) => Err(failure(stage, "data_type_invalid")),
            },
            Some(401) => Err(UbaaError::new(
                ErrorCode::AuthenticationRequired,
                ErrorKind::Authentication,
                false,
                "财务登录已失效",
            )
            .with_diagnostic(stage, "business_session_required")),
            Some(_) => Err(failure(stage, "business_rejected")),
            None => Err(failure(stage, "business_code_invalid")),
        }
    })();
    result.map_err(|error| error.with_business_response(bytes, None, "code"))
}

#[cfg(test)]
pub(super) fn cents(value: &Value) -> Result<Option<i64>> {
    amount(value, "amount")
}

fn amount(value: &Value, field: &'static str) -> Result<Option<i64>> {
    if value.is_null() {
        return Ok(None);
    }
    let number = value
        .as_number()
        .ok_or_else(|| failure("income_fields", amount_reason(field, "type_invalid")))?
        .to_string();
    let (negative, text) = number
        .strip_prefix('-')
        .map_or((false, number.as_str()), |s| (true, s));
    let (whole, fraction) = text.split_once('.').unwrap_or((text, ""));
    if fraction.len() > 2
        || !whole.bytes().all(|b| b.is_ascii_digit())
        || !fraction.bytes().all(|b| b.is_ascii_digit())
    {
        return Err(failure(
            "income_fields",
            amount_reason(field, "format_invalid"),
        ));
    }
    let whole = whole
        .parse::<i64>()
        .map_err(|_| failure("income_fields", amount_reason(field, "out_of_range")))?;
    let fraction = match fraction.len() {
        0 => 0,
        1 => {
            fraction
                .parse::<i64>()
                .map_err(|_| failure("income_fields", amount_reason(field, "format_invalid")))?
                * 10
        }
        _ => fraction
            .parse::<i64>()
            .map_err(|_| failure("income_fields", amount_reason(field, "format_invalid")))?,
    };
    let value = whole
        .checked_mul(100)
        .and_then(|v| v.checked_add(fraction))
        .ok_or_else(|| failure("income_fields", amount_reason(field, "out_of_range")))?;
    Ok(Some(if negative { -value } else { value }))
}

fn amount_reason(field: &'static str, suffix: &'static str) -> &'static str {
    match (field, suffix) {
        ("je", "type_invalid") => "je_type_invalid",
        ("je", "format_invalid") => "je_format_invalid",
        ("je", "out_of_range") => "je_out_of_range",
        ("se", "type_invalid") => "se_type_invalid",
        ("se", "format_invalid") => "se_format_invalid",
        ("se", "out_of_range") => "se_out_of_range",
        ("sfje", "type_invalid") => "sfje_type_invalid",
        ("sfje", "format_invalid") => "sfje_format_invalid",
        ("sfje", "out_of_range") => "sfje_out_of_range",
        ("amount", "type_invalid") => "amount_type_invalid",
        ("amount", "format_invalid") => "amount_format_invalid",
        ("amount", "out_of_range") => "amount_out_of_range",
        _ => "amount_invalid",
    }
}

pub(super) fn page(value: &Value) -> Result<(Vec<Value>, usize)> {
    let (rows, total) = if value.get("mx").is_some() || value.get("total").is_some() {
        ("mx", "total")
    } else {
        ("data", "count")
    };
    let rows = match value.get(rows) {
        None => return Err(failure("income_pagination", "rows_missing")),
        Some(Value::Null) => return Err(failure("income_pagination", "rows_null")),
        Some(Value::Array(rows)) => rows.clone(),
        Some(_) => return Err(failure("income_pagination", "rows_type_invalid")),
    };
    let total = match value.get(total) {
        None => return Err(failure("income_pagination", "total_missing")),
        Some(Value::Null) => return Err(failure("income_pagination", "total_null")),
        Some(total) => total
            .as_u64()
            .and_then(|n| usize::try_from(n).ok())
            .ok_or_else(|| failure("income_pagination", "total_invalid"))?,
    };
    if total > u32::MAX as usize || rows.len() > total {
        return Err(failure("income_pagination", "total_inconsistent"));
    }
    Ok((rows, total))
}

fn text_reason(field: &str) -> &'static str {
    match field {
        "lsh" => "lsh_type_invalid",
        "ffxmmc" => "ffxmmc_type_invalid",
        "zy" => "zy_type_invalid",
        "slbfb" => "slbfb_type_invalid",
        "lrrq" => "lrrq_type_invalid",
        "nian" => "nian_type_invalid",
        "yue" => "yue_type_invalid",
        _ => "field_type_invalid",
    }
}

fn text(value: &Value, key: &str) -> Result<Option<String>> {
    match value.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(s)) => Ok((!s.is_empty()).then(|| s.clone())),
        Some(_) => Err(failure("income_fields", text_reason(key))),
    }
}

fn display_text(value: &Value, key: &str) -> Option<String> {
    let text = value.get(key)?.as_str()?.trim();
    (!text.is_empty()).then(|| text.to_owned())
}

fn record_id(value: &Value) -> Result<String> {
    match value.get("lsh") {
        None => Err(failure("income_fields", "lsh_missing")),
        Some(Value::Null) => Err(failure("income_fields", "lsh_null")),
        Some(Value::String(value)) if value.is_empty() => {
            Err(failure("income_fields", "lsh_empty"))
        }
        Some(Value::String(value)) => Ok(value.clone()),
        Some(_) => Err(failure("income_fields", "lsh_type_invalid")),
    }
}

pub(super) fn income(value: &Value) -> Result<FinanceIncome> {
    if !value.is_object() {
        return Err(failure("income_fields", "record_type_invalid"));
    }
    Ok(FinanceIncome {
        id: record_id(value)?,
        project: text(value, "ffxmmc")?,
        description: text(value, "zy")?,
        department: display_text(value, "bmmc"),
        project_code: display_text(value, "xmbh"),
        project_name: display_text(value, "xmmc"),
        amount_cents: amount(&value["je"], "je")?,
        tax_cents: amount(&value["se"], "se")?,
        paid_cents: amount(&value["sfje"], "sfje")?,
        tax_rate: text(value, "slbfb")?,
        recorded_date: text(value, "lrrq")?,
        year: text(value, "nian")?,
        month: text(value, "yue")?,
    })
}
